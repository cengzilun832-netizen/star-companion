#!/usr/bin/env python3

from __future__ import annotations

import plistlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAIN_MANIFEST = ROOT / "ios/StarCompanion/StarCompanion/PrivacyInfo.xcprivacy"
WATCH_MANIFEST = ROOT / "ios/StarCompanion/StarPetWatch/PrivacyInfo.xcprivacy"
APP_SOURCE = ROOT / "ios/StarCompanion/StarCompanion"

APP_FUNCTIONALITY = "NSPrivacyCollectedDataTypePurposeAppFunctionality"
PERSONALIZATION = "NSPrivacyCollectedDataTypePurposeProductPersonalization"

EXPECTED_MAIN_DATA_TYPES = {
    "NSPrivacyCollectedDataTypeUserID": {APP_FUNCTIONALITY},
    "NSPrivacyCollectedDataTypePhoneNumber": {APP_FUNCTIONALITY},
    "NSPrivacyCollectedDataTypeName": {APP_FUNCTIONALITY, PERSONALIZATION},
    "NSPrivacyCollectedDataTypeOtherUserContent": {
        APP_FUNCTIONALITY,
        PERSONALIZATION,
    },
    "NSPrivacyCollectedDataTypeGameplayContent": {APP_FUNCTIONALITY},
    "NSPrivacyCollectedDataTypeProductInteraction": {APP_FUNCTIONALITY},
    "NSPrivacyCollectedDataTypeOtherDataTypes": {
        APP_FUNCTIONALITY,
        PERSONALIZATION,
    },
}


def load(path: Path) -> dict[str, object]:
    with path.open("rb") as stream:
        value = plistlib.load(stream)
    if not isinstance(value, dict):
        raise AssertionError(f"{path} must contain a property-list dictionary")
    return value


def verify_common(manifest: dict[str, object], name: str) -> None:
    assert manifest.get("NSPrivacyTracking") is False, f"{name} must not track"
    assert manifest.get("NSPrivacyTrackingDomains") == [], (
        f"{name} must not declare tracking domains"
    )

    accessed = manifest.get("NSPrivacyAccessedAPITypes")
    assert isinstance(accessed, list) and len(accessed) == 1, (
        f"{name} must declare one required-reason API category"
    )
    assert accessed[0] == {
        "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
        "NSPrivacyAccessedAPITypeReasons": ["CA92.1"],
    }, f"{name} UserDefaults declaration changed unexpectedly"


def verify_main() -> None:
    manifest = load(MAIN_MANIFEST)
    verify_common(manifest, "main app")

    entries = manifest.get("NSPrivacyCollectedDataTypes")
    assert isinstance(entries, list), "main app collected-data declaration is missing"
    by_type: dict[str, dict[str, object]] = {}
    for entry in entries:
        assert isinstance(entry, dict), "each collected-data entry must be a dictionary"
        assert set(entry) == {
            "NSPrivacyCollectedDataType",
            "NSPrivacyCollectedDataTypeLinked",
            "NSPrivacyCollectedDataTypeTracking",
            "NSPrivacyCollectedDataTypePurposes",
        }, "collected-data entries must use Apple's exact four-key schema"
        data_type = entry.get("NSPrivacyCollectedDataType")
        assert isinstance(data_type, str), "collected-data type must be a string"
        assert data_type not in by_type, f"duplicate collected-data type: {data_type}"
        by_type[data_type] = entry

    assert set(by_type) == set(EXPECTED_MAIN_DATA_TYPES), (
        "main app privacy categories no longer match account sync"
    )
    for data_type, expected_purposes in EXPECTED_MAIN_DATA_TYPES.items():
        entry = by_type[data_type]
        assert entry["NSPrivacyCollectedDataTypeLinked"] is True, (
            f"{data_type} must remain linked to the signed-in account"
        )
        assert entry["NSPrivacyCollectedDataTypeTracking"] is False, (
            f"{data_type} must not be used for tracking"
        )
        purposes = entry["NSPrivacyCollectedDataTypePurposes"]
        assert isinstance(purposes, list) and set(purposes) == expected_purposes, (
            f"unexpected purposes for {data_type}"
        )


def verify_watch() -> None:
    manifest = load(WATCH_MANIFEST)
    verify_common(manifest, "Watch app")
    assert manifest.get("NSPrivacyCollectedDataTypes") == [], (
        "Watch must stay collection-free; it relays pet state through the paired iPhone"
    )


def verify_user_facing_copy() -> None:
    source = "\n".join(
        path.read_text(encoding="utf-8")
        for path in sorted(APP_SOURCE.glob("*.swift"))
    )
    stale_claims = [
        "目前 Release 版尚未連接後端",
        "This version doesn't collect your personal data on a developer server",
        "運勢、抽牌與出生資料預設留在本機",
        "Fortunes, tarot history, birth details, star looks, and planet progress stay on-device",
        "Star Companion doesn't send visit cards to its own server",
        "Nothing was uploaded.",
    ]
    for stale_claim in stale_claims:
        assert stale_claim not in source, f"stale privacy claim remains: {stale_claim}"

    required_claims = [
        "這不是 iCloud 同步。",
        "This isn't iCloud sync.",
        "星伴不出售資料",
        "Star Companion doesn't sell it or use it to track you across apps or websites.",
        "Apple Watch doesn't connect to the account service directly",
        "正式帳號保存在服務上的副本不會刪除",
        "It doesn't delete the service copy for a verified account",
    ]
    for required_claim in required_claims:
        assert required_claim in source, f"required privacy claim is missing: {required_claim}"


if __name__ == "__main__":
    verify_main()
    verify_watch()
    verify_user_facing_copy()
    print("Main app and Watch privacy manifests verified")
