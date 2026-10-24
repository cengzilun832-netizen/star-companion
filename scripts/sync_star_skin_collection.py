#!/usr/bin/env python3
"""Sync the source star-skin collection into the iOS asset catalog.

The script owns only `SkinCollection*.imageset` directories and the generated
Swift manifest. Existing hand-curated Persona assets are never modified.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = REPO_ROOT / "assets/pet/skins/collection"
ASSET_CATALOG = REPO_ROOT / "ios/StarCompanion/StarCompanion/Assets.xcassets"
GENERATED_SWIFT = REPO_ROOT / "ios/StarCompanion/StarCompanion/StarSkinCatalog.generated.swift"

# These source images already ship under stable legacy Persona IDs. Keeping
# them out of the generated section prevents duplicate shop cards and preserves
# every existing account's selection and ownership data.
EXCLUDED_SOURCE_SLUGS = {
    "abyssal-jelly",
    "aurora-whisper",
    "dream-pajamas",
    "frog-prince",
    "halloween-ghost-star",
    "hanbok-cloud",
    # Exact duplicate of the stable Mid-Autumn PersonaMoonRabbit artwork.
    # Keep one shop card and migrate the former collection ID in StarWardrobe.
    "jade-rabbit",
    "moon-witch",
    "nova-mecha",
    "obsidian-night",
    "planet-ring",
    "sakura-mist",
    "strawberry-mousse",
}

# Slugs are usually composed from these reusable words. Missing translations
# deliberately fall back to the English title in the app rather than exposing
# a raw filename or an awkward machine-looking placeholder.
ZH_TOKENS = {
    "afterglow": "餘曉", "amethyst": "紫水晶", "anemone": "銀蓮", "angel": "天使",
    "aquamarine": "海藍寶", "arcade": "街機", "autumn": "秋日", "ballet": "芭蕾",
    "bamboo": "竹影", "bell": "鈴", "blue": "蒼藍", "bluebell": "風鈴草",
    "blueberry": "藍莓", "book": "魔書", "breeze": "微風", "candy": "糖",
    "camellia": "山茶", "caramel": "焦糖", "celadon": "青瓷", "celeste": "蒼穹",
    "choir": "合唱團", "chrome": "鏡銀", "circuit": "電路", "citrine": "黃水晶",
    "clockwork": "齒輪", "cloud": "雲朵", "cocoa": "可可", "comet": "彗星",
    "coral": "珊瑚", "cosmic": "宇宙", "cosmos": "星海", "cotton": "棉花",
    "crane": "仙鶴", "current": "流光", "dawn": "黎明", "dew": "露珠", "diamond": "鑽石",
    "digital": "數位", "dragon": "龍", "dream": "夢境", "dynamic": "靈動",
    "eclipse": "月蝕", "egg": "之卵", "emerald": "祖母綠", "enchanted": "魔法",
    "fairy": "精靈", "fan": "月扇", "firefly": "螢火", "fizz": "氣泡",
    "frost": "霜晶", "galaxy": "銀河", "genie": "精靈", "glass": "琉璃",
    "glide": "滑翔", "glow": "微光", "golden": "金色", "goose": "鵝",
    "gravity": "引力", "grape": "葡萄", "grove": "森林", "halo": "光環",
    "heart": "心語", "hood": "兜帽", "hologram": "全息", "hydrangea": "繡球花",
    "idol": "偶像", "ink": "墨色", "island": "星島", "jade": "翡翠",
    "jelly": "果凍", "kintsugi": "金繕", "knot": "結", "lantern": "燈籠",
    "lavender": "薰衣草", "lace": "蕾絲", "lemon": "檸檬", "liquid": "流體",
    "lotus": "蓮花", "macaron": "馬卡龍", "magic": "魔法", "manta": "魔鬼魚",
    "maple": "楓紅", "matcha": "抹茶", "meringue": "雪白糖霜", "meteor": "流星",
    "midnight": "午夜", "mint": "薄荷", "mirror": "魔鏡", "misty": "霧色",
    "moon": "月光", "moonstone": "月光石", "morning": "清晨", "nautilus": "鸚鵡螺",
    "nebula": "星雲", "night": "夜曲", "opal": "蛋白石", "oracle": "神諭", "orbit": "軌道",
    "peach": "水蜜桃", "pearl": "珍珠", "picnic": "野餐", "pixel": "像素",
    "plasma": "電漿", "polar": "極地", "porcelain": "瓷器", "prince": "王子",
    "pudding": "布丁", "quantum": "量子", "rabbit": "兔", "rain": "細雨",
    "rainbow": "彩虹", "red": "紅", "roll": "捲", "rose": "玫瑰",
    "royal": "皇家", "ruby": "紅寶石", "sakura": "櫻花", "sapphire": "藍寶石", "seafoam": "海沫",
    "seahorse": "海馬", "shell": "貝殼", "silk": "絲緞", "silver": "銀色",
    "slipper": "舞鞋", "snow": "初雪", "solar": "日光", "sonata": "奏鳴曲",
    "song": "之歌", "sorbet": "冰沙", "spring": "春日", "star": "星星",
    "starlight": "星光", "sun": "驕陽", "summer": "夏日", "sunken": "沉沒",
    "sunset": "落日", "swan": "天鵝", "synthwave": "合成波", "tarot": "塔羅",
    "tart": "塔", "tea": "茶會", "thunder": "雷鳴", "tide": "潮汐",
    "tidepool": "潮池", "treasure": "寶藏", "truffle": "松露", "unicorn": "獨角獸",
    "veil": "薄紗", "voyage": "航程", "whale": "鯨魚", "winter": "冬日",
    "wish": "心願", "wisteria": "紫藤", "yukata": "浴衣", "zero": "無重",
}

KO_TOKENS = {
    "afterglow": "여운", "amethyst": "자수정", "anemone": "아네모네", "angel": "천사",
    "aquamarine": "아쿠아마린", "arcade": "아케이드", "autumn": "가을", "ballet": "발레",
    "bamboo": "대나무", "blue": "파란", "bluebell": "블루벨", "blueberry": "블루베리",
    "book": "마법책", "breeze": "산들바람", "candy": "사탕", "camellia": "동백",
    "caramel": "캐러멜", "celadon": "청자", "celeste": "창공", "choir": "합창단",
    "chrome": "크롬", "circuit": "회로", "citrine": "시트린", "clockwork": "태엽",
    "cloud": "구름", "cocoa": "코코아", "comet": "혜성", "coral": "산호",
    "cosmic": "우주", "cosmos": "코스모스", "cotton": "솜사탕", "crane": "학",
    "current": "물결", "dawn": "새벽", "dew": "이슬", "diamond": "다이아몬드", "digital": "디지털",
    "dragon": "드래곤", "dream": "꿈", "dynamic": "다이내믹", "eclipse": "식",
    "egg": "알", "emerald": "에메랄드", "enchanted": "마법", "fairy": "요정",
    "fan": "부채", "firefly": "반딧불", "fizz": "탄산", "frost": "서리",
    "galaxy": "은하", "genie": "지니", "glass": "유리", "glide": "활공",
    "glow": "빛", "golden": "금빛", "goose": "거위", "gravity": "중력",
    "grape": "포도", "grove": "숲", "halo": "후광", "heart": "하트",
    "hood": "후드", "hologram": "홀로그램", "hydrangea": "수국", "idol": "아이돌",
    "ink": "먹", "island": "별섬", "jade": "비취", "jelly": "젤리",
    "kintsugi": "긴츠기", "knot": "매듭", "lantern": "등불", "lavender": "라벤더",
    "lace": "레이스", "lemon": "레몬", "liquid": "리퀴드", "lotus": "연꽃",
    "macaron": "마카롱", "magic": "마법", "manta": "대왕가오리", "maple": "단풍",
    "matcha": "말차", "meringue": "머랭", "meteor": "유성", "midnight": "한밤",
    "mint": "민트", "mirror": "거울", "misty": "안개", "moon": "달빛",
    "moonstone": "문스톤", "morning": "아침", "nautilus": "앵무조개", "nebula": "성운",
    "night": "밤", "opal": "오팔", "oracle": "오라클", "orbit": "궤도", "peach": "복숭아",
    "pearl": "진주", "picnic": "피크닉", "pixel": "픽셀", "plasma": "플라즈마",
    "polar": "극지", "porcelain": "도자기", "prince": "왕자", "pudding": "푸딩",
    "quantum": "양자", "rabbit": "토끼", "rain": "비", "rainbow": "무지개",
    "red": "빨간", "roll": "롤", "rose": "장미", "royal": "로얄", "sakura": "벚꽃",
    "ruby": "루비", "sapphire": "사파이어", "seafoam": "바다거품", "seahorse": "해마",
    "shell": "조개", "silk": "비단", "silver": "은빛", "slipper": "구두",
    "snow": "눈", "solar": "태양", "sonata": "소나타", "song": "노래",
    "sorbet": "샤베트", "spring": "봄", "star": "별", "starlight": "별빛",
    "sun": "햇살", "summer": "여름", "sunken": "침몰", "sunset": "노을",
    "swan": "백조", "synthwave": "신스웨이브", "tarot": "타로", "tart": "타르트",
    "tea": "티", "thunder": "천둥", "tide": "조석", "tidepool": "조수웅덩이",
    "treasure": "보물", "truffle": "트러플", "unicorn": "유니콘", "veil": "베일",
    "voyage": "항해", "whale": "고래", "winter": "겨울", "wish": "소원",
    "wisteria": "등나무", "yukata": "유카타", "zero": "무중력",
}

EXACT_TITLES = {
    # Keep a familiar but non-product name for the source artwork whose file
    # name references an iPhone UI feature.
    "dynamic-island": ("靈動星島", "별빛 아일랜드", "Orbit Island"),
    "blue-porcelain": ("青花瓷夢", "푸른 도자기", "Blue Porcelain"),
    "cotton-candy": ("棉花糖雲", "솜사탕 구름", "Cotton Candy"),
    "glass-slipper": ("琉璃舞鞋", "유리 구두", "Glass Slipper"),
    "golden-goose": ("金鵝", "황금 거위", "Golden Goose"),
    "red-knot": ("紅繩結願", "빨간 소원 매듭", "Red Wish Knot"),
    "zero-gravity": ("無重力星", "무중력 별", "Zero Gravity"),
}


def pascal_case(slug: str) -> str:
    return "".join(part.capitalize() for part in slug.split("-"))


def localized_titles(slug: str) -> tuple[str | None, str | None, str]:
    if slug in EXACT_TITLES:
        return EXACT_TITLES[slug]
    words = slug.split("-")
    english = " ".join(word.capitalize() for word in words)
    zh = "".join(ZH_TOKENS[word] for word in words) if all(word in ZH_TOKENS for word in words) else None
    ko = " ".join(KO_TOKENS[word] for word in words) if all(word in KO_TOKENS for word in words) else None
    return zh, ko, english


def rarity_and_price(slug: str) -> tuple[str, int]:
    # SHA-256 makes the result deterministic across Python/Swift versions and
    # independent of manifest order.
    bucket = int(hashlib.sha256(slug.encode("utf-8")).hexdigest()[:8], 16) % 100
    if bucket < 42:
        return "common", 220
    if bucket < 72:
        return "rare", 300
    if bucket < 92:
        return "epic", 380
    return "legendary", 480


def swift_string(value: str | None) -> str:
    if value is None:
        return "nil"
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def generated_manifest(items: list[dict[str, object]]) -> str:
    lines = [
        "// Generated by scripts/sync_star_skin_collection.py. Do not edit by hand.",
        "import Foundation",
        "",
        "extension StarSkinCatalog {",
        "    static let generatedItems: [StarSkinCatalogItem] = [",
    ]
    for item in items:
        lines.extend([
            "        StarSkinCatalogItem(",
            f'            id: "collection.{item["slug"]}",',
            f'            sourceSlug: "{item["slug"]}",',
            f'            assetName: "{item["asset_name"]}",',
            f'            traditionalChineseName: {swift_string(item["zh"])},',
            f'            koreanName: {swift_string(item["ko"])},',
            f'            englishName: {swift_string(item["en"])},',
            f'            rarity: .{item["rarity"]},',
            f'            price: {item["price"]}',
            "        ),",
        ])
    lines.extend([
        "    ]",
        "",
        "    static let excludedSourceSlugs: Set<String> = [",
    ])
    for slug in sorted(EXCLUDED_SOURCE_SLUGS):
        lines.append(f'        "{slug}",')
    lines.extend(["    ]", "}", ""])
    return "\n".join(lines)


def sync_assets(items: list[dict[str, object]]) -> None:
    expected_sets = {f'{item["asset_name"]}.imageset' for item in items}
    for old_set in ASSET_CATALOG.glob("SkinCollection*.imageset"):
        if old_set.name not in expected_sets:
            shutil.rmtree(old_set)

    for item in items:
        slug = str(item["slug"])
        asset_name = str(item["asset_name"])
        image_set = ASSET_CATALOG / f"{asset_name}.imageset"
        image_set.mkdir(parents=True, exist_ok=True)
        output_name = f"skin-collection-{slug}.png"
        output_image = image_set / output_name
        shutil.copyfile(SOURCE_DIR / f"{slug}.png", output_image)
        subprocess.run(
            ["/usr/bin/sips", "-Z", "512", str(output_image)],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        contents = {
            "images": [{"filename": output_name, "idiom": "universal", "scale": "1x"}],
            "info": {"author": "xcode", "version": 1},
            "properties": {"preserves-vector-representation": False},
        }
        (image_set / "Contents.json").write_text(
            json.dumps(contents, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )


def build_items() -> list[dict[str, object]]:
    source_files = sorted(SOURCE_DIR.glob("*.png"))
    source_slugs = {path.stem for path in source_files}
    missing_exclusions = EXCLUDED_SOURCE_SLUGS - source_slugs
    if missing_exclusions:
        raise RuntimeError(f"Excluded source images are missing: {sorted(missing_exclusions)}")

    items = []
    for source in source_files:
        slug = source.stem
        if slug in EXCLUDED_SOURCE_SLUGS:
            continue
        if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", slug):
            raise RuntimeError(f"Unsupported source filename: {source.name}")
        zh, ko, en = localized_titles(slug)
        rarity, price = rarity_and_price(slug)
        items.append({
            "slug": slug,
            "asset_name": f"SkinCollection{pascal_case(slug)}",
            "zh": zh,
            "ko": ko,
            "en": en,
            "rarity": rarity,
            "price": price,
        })
    return items


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="verify generated output without changing files")
    args = parser.parse_args()
    items = build_items()
    manifest = generated_manifest(items)

    if args.check:
        if not GENERATED_SWIFT.exists() or GENERATED_SWIFT.read_text(encoding="utf-8") != manifest:
            print("Generated Swift catalog is stale; run scripts/sync_star_skin_collection.py", file=sys.stderr)
            return 1
        expected_sets = {f'{item["asset_name"]}.imageset' for item in items}
        actual_sets = {path.name for path in ASSET_CATALOG.glob("SkinCollection*.imageset")}
        if expected_sets != actual_sets:
            print("Generated asset catalog is stale; run scripts/sync_star_skin_collection.py", file=sys.stderr)
            return 1
        print(f"Star skin catalog is current: {len(items)} collection looks, {len(EXCLUDED_SOURCE_SLUGS)} legacy duplicates excluded")
        return 0

    sync_assets(items)
    GENERATED_SWIFT.write_text(manifest, encoding="utf-8")
    print(f"Synced {len(items)} collection looks; preserved {len(EXCLUDED_SOURCE_SLUGS)} legacy duplicates")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
