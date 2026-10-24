#!/usr/bin/env python3
"""Verify generated star-skin assets and catalog invariants."""

from __future__ import annotations

import json
import subprocess
import struct
import sys
import tempfile
from collections import Counter
from pathlib import Path

import sync_star_skin_collection as sync


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def png_info(path: Path) -> tuple[int, int, int]:
    data = path.read_bytes()[:26]
    require(data[:8] == b"\x89PNG\r\n\x1a\n", f"Not a PNG: {path}")
    require(data[12:16] == b"IHDR", f"Missing PNG IHDR: {path}")
    width, height = struct.unpack(">II", data[16:24])
    color_type = data[25]
    return width, height, color_type


def main() -> int:
    items = sync.build_items()
    sources = sorted(sync.SOURCE_DIR.glob("*.png"))
    require(len(sources) == 101, f"Expected 101 source PNGs, found {len(sources)}")
    require(len(sync.EXCLUDED_SOURCE_SLUGS) == 13, "Expected 13 stable legacy exclusions")
    require(len(items) == 88, f"Expected 88 generated looks, found {len(items)}")

    ids = [f'collection.{item["slug"]}' for item in items]
    assets = [str(item["asset_name"]) for item in items]
    require(len(ids) == len(set(ids)), "Collection IDs must be unique")
    require(len(assets) == len(set(assets)), "Collection asset names must be unique")
    require(all(item["zh"] and item["ko"] and item["en"] for item in items), "Every look needs all three names")

    expected_prices = {"common": 220, "rare": 300, "epic": 380, "legendary": 480}
    for item in items:
        require(item["price"] == expected_prices[item["rarity"]], f'Bad price for {item["slug"]}')

        image_set = sync.ASSET_CATALOG / f'{item["asset_name"]}.imageset'
        contents_path = image_set / "Contents.json"
        require(contents_path.exists(), f"Missing asset metadata: {contents_path}")
        contents = json.loads(contents_path.read_text(encoding="utf-8"))
        filename = contents["images"][0]["filename"]
        image_path = image_set / filename
        require(image_path.exists(), f"Missing generated image: {image_path}")
        width, height, color_type = png_info(image_path)
        require(max(width, height) <= 512, f"Oversized generated image: {image_path} ({width}x{height})")
        require(min(width, height) >= 450, f"Unexpectedly small generated image: {image_path} ({width}x{height})")
        require(color_type in {4, 6}, f"Generated artwork lost alpha: {image_path} (PNG color type {color_type})")

    expected_manifest = sync.generated_manifest(items)
    require(sync.GENERATED_SWIFT.read_text(encoding="utf-8") == expected_manifest, "Generated Swift catalog is stale")
    generated_sets = list(sync.ASSET_CATALOG.glob("SkinCollection*.imageset"))
    require(len(generated_sets) == len(items), "Generated imageset count does not match manifest")

    # Existing 20 looks are still represented by Classic plus 19 Persona sets.
    legacy_persona_sets = list(sync.ASSET_CATALOG.glob("Persona*.imageset"))
    require(len(legacy_persona_sets) == 19, f"Expected 19 existing Persona assets, found {len(legacy_persona_sets)}")
    require((sync.ASSET_CATALOG / "StarPet.imageset").exists(), "Classic StarPet asset is missing")

    swift_sources = [
        sync.REPO_ROOT / "ios/StarCompanion/StarCompanion/AuthModels.swift",
        sync.REPO_ROOT / "ios/StarCompanion/StarCompanion/TarotDeck.swift",
        sync.REPO_ROOT / "ios/StarCompanion/StarCompanion/HomeVisitExchange.swift",
        sync.REPO_ROOT / "ios/StarCompanion/StarCompanion/StarLifeModels.swift",
        sync.REPO_ROOT / "ios/StarCompanion/StarCompanion/Models.swift",
        sync.REPO_ROOT / "ios/StarCompanion/StarCompanion/StarSkinCatalog.swift",
        sync.GENERATED_SWIFT,
        sync.REPO_ROOT / "scripts/verify_star_skin_wardrobe.swift",
    ]
    with tempfile.TemporaryDirectory(prefix="star-skin-verifier-") as temporary_directory:
        verifier_binary = Path(temporary_directory) / "verify-star-skin-wardrobe"
        subprocess.run(
            ["/usr/bin/xcrun", "swiftc", *(str(path) for path in swift_sources), "-o", str(verifier_binary)],
            check=True,
        )
        swift_result = subprocess.run(
            [str(verifier_binary)],
            check=True,
            capture_output=True,
            text=True,
        )
        print(swift_result.stdout.strip())

    distribution = Counter(str(item["rarity"]) for item in items)
    print(
        "Verified 101 source PNGs -> 88 generated collection looks + 13 legacy duplicates; "
        "20 existing looks preserved; rarity distribution: "
        + ", ".join(f"{name}={distribution[name]}" for name in expected_prices)
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as error:
        print(f"Verification failed: {error}", file=sys.stderr)
        raise SystemExit(1)
