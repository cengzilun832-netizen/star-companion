#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
build_dir="$(mktemp -d /tmp/starcompanion-verifiers.XXXXXX)"
trap 'rm -rf "${build_dir}"' EXIT

cd "${repo_root}"

common_sources=(
  ios/StarCompanion/StarCompanion/AuthModels.swift
  ios/StarCompanion/StarCompanion/Models.swift
  ios/StarCompanion/StarCompanion/TarotDeck.swift
  ios/StarCompanion/StarCompanion/StarSkinCatalog.swift
  ios/StarCompanion/StarCompanion/StarSkinCatalog.generated.swift
  ios/StarCompanion/StarCompanion/StarLifeModels.swift
  ios/StarCompanion/StarCompanion/HomeVisitExchange.swift
  ios/StarCompanion/StarCompanion/AccountStorage.swift
)

model_verifiers=(
  verify_daily_access
  verify_star_life
  verify_home_visit_exchange
  verify_star_progress
  verify_star_skin_wardrobe
  verify_account_storage
  verify_account_cloud_storage
)

for verifier in "${model_verifiers[@]}"; do
  xcrun swiftc -parse-as-library \
    "${common_sources[@]}" \
    "scripts/${verifier}.swift" \
    -o "${build_dir}/${verifier}"
  "${build_dir}/${verifier}"
done

xcrun swiftc -parse-as-library \
  ios/StarCompanion/StarCompanion/AuthModels.swift \
  ios/StarCompanion/StarCompanion/AuthServices.swift \
  ios/StarCompanion/StarCompanion/SessionVault.swift \
  ios/StarCompanion/StarCompanion/Services.swift \
  ios/StarCompanion/StarCompanion/Models.swift \
  ios/StarCompanion/StarCompanion/TarotDeck.swift \
  ios/StarCompanion/StarCompanion/StarSkinCatalog.swift \
  ios/StarCompanion/StarCompanion/StarSkinCatalog.generated.swift \
  ios/StarCompanion/StarCompanion/StarLifeModels.swift \
  ios/StarCompanion/StarCompanion/HomeVisitExchange.swift \
  ios/StarCompanion/StarCompanion/AccountStorage.swift \
  ios/StarCompanion/StarCompanion/AccountCloudSyncService.swift \
  ios/StarCompanion/StarCompanion/AppStore.swift \
  scripts/verify_daily_access_app_store.swift \
  -o "${build_dir}/verify_daily_access_app_store"
"${build_dir}/verify_daily_access_app_store"

xcrun swiftc -parse-as-library \
  ios/StarCompanion/StarCompanion/AuthModels.swift \
  ios/StarCompanion/StarCompanion/AuthServices.swift \
  ios/StarCompanion/StarCompanion/SessionVault.swift \
  ios/StarCompanion/StarCompanion/Services.swift \
  ios/StarCompanion/StarCompanion/Models.swift \
  ios/StarCompanion/StarCompanion/TarotDeck.swift \
  ios/StarCompanion/StarCompanion/StarSkinCatalog.swift \
  ios/StarCompanion/StarCompanion/StarSkinCatalog.generated.swift \
  ios/StarCompanion/StarCompanion/StarLifeModels.swift \
  ios/StarCompanion/StarCompanion/HomeVisitExchange.swift \
  ios/StarCompanion/StarCompanion/AccountStorage.swift \
  ios/StarCompanion/StarCompanion/AccountCloudSyncService.swift \
  ios/StarCompanion/StarCompanion/AppStore.swift \
  scripts/verify_account_cloud_app_store.swift \
  -o "${build_dir}/verify_account_cloud_app_store"
"${build_dir}/verify_account_cloud_app_store"

xcrun swiftc -parse-as-library \
  ios/StarCompanion/StarCompanion/{AuthModels,AuthServices,SessionVault,Services,Models,TarotDeck,StarSkinCatalog,StarSkinCatalog.generated,StarLifeModels,HomeVisitExchange,AccountStorage,AccountCloudSyncService,AppStore}.swift \
  scripts/verify_account_actions.swift \
  -o "${build_dir}/verify_account_actions"
"${build_dir}/verify_account_actions"

xcrun swiftc -parse-as-library \
  ios/StarCompanion/StarCompanion/AuthModels.swift \
  ios/StarCompanion/StarCompanion/AuthServices.swift \
  ios/StarCompanion/StarCompanion/SessionVault.swift \
  ios/StarCompanion/StarCompanion/Services.swift \
  ios/StarCompanion/StarCompanion/Models.swift \
  ios/StarCompanion/StarCompanion/TarotDeck.swift \
  ios/StarCompanion/StarCompanion/StarSkinCatalog.swift \
  ios/StarCompanion/StarCompanion/StarSkinCatalog.generated.swift \
  ios/StarCompanion/StarCompanion/StarLifeModels.swift \
  ios/StarCompanion/StarCompanion/HomeVisitExchange.swift \
  ios/StarCompanion/StarCompanion/AccountStorage.swift \
  ios/StarCompanion/StarCompanion/AccountCloudSyncService.swift \
  ios/StarCompanion/StarCompanion/AppStore.swift \
  scripts/verify_localized_archives.swift \
  -o "${build_dir}/verify_localized_archives"
"${build_dir}/verify_localized_archives"

xcrun swiftc -D DEBUG -parse-as-library \
  scripts/verify_auth_foundation.swift \
  ios/StarCompanion/StarCompanion/AuthModels.swift \
  ios/StarCompanion/StarCompanion/AuthServices.swift \
  ios/StarCompanion/StarCompanion/SessionVault.swift \
  -o "${build_dir}/verify_auth_foundation"
"${build_dir}/verify_auth_foundation"

xcrun swiftc -parse-as-library \
  scripts/verify_production_auth_api.swift \
  ios/StarCompanion/StarCompanion/AuthModels.swift \
  ios/StarCompanion/StarCompanion/AuthServices.swift \
  ios/StarCompanion/StarCompanion/SessionVault.swift \
  -o "${build_dir}/verify_production_auth_api"
"${build_dir}/verify_production_auth_api"

auth_info_plist="ios/StarCompanion/StarCompanion/Info.plist"
auth_entitlements="ios/StarCompanion/StarCompanion/StarCompanion.entitlements"
auth_project="ios/StarCompanion/StarCompanion.xcodeproj/project.pbxproj"
auth_deployment_notes="ios/StarCompanion/AUTH_DEPLOYMENT.md"
plutil -lint "${auth_info_plist}" "${auth_entitlements}" >/dev/null
test "$(plutil -extract StarCompanionAPIBaseURL raw -o - "${auth_info_plist}")" = \
  '$(STAR_COMPANION_API_BASE_URL)'
test "$(plutil -extract StarCompanionAccountAPIBaseURL raw -o - "${auth_info_plist}")" = \
  '$(STAR_COMPANION_API_BASE_URL)'
test "$(plutil -extract StarCompanionPhoneOTPEnabled raw -o - "${auth_info_plist}")" = \
  '$(STAR_COMPANION_PHONE_OTP_ENABLED)'
test "$(rg -c 'STAR_COMPANION_API_BASE_URL = "https://' "${auth_project}")" -eq 2
test "$(rg -c 'STAR_COMPANION_PHONE_OTP_ENABLED = NO;' "${auth_project}")" -eq 2
test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.applesignin:0' "${auth_entitlements}")" = "Default"
rg -q 'com\.example\.StarCompanion' "${auth_project}"
rg -q 'com\.example\.StarCompanion' "${auth_deployment_notes}"
echo "Apple auth endpoint injection, disabled phone OTP, entitlement, and release blocker notes verified"

all_looks_info_plist="ios/StarCompanion/StarCompanion/Info.plist"
all_looks_storekit="ios/StarCompanion/StarCompanion/StarlightMembership.storekit"
all_looks_project="ios/StarCompanion/StarCompanion.xcodeproj/project.pbxproj"
plutil -lint "${all_looks_info_plist}" >/dev/null
test "$(plutil -extract AllStarLooksProductID raw -o - "${all_looks_info_plist}")" = \
  '$(ALL_STAR_LOOKS_PRODUCT_ID)'
test "$(rg -c 'ALL_STAR_LOOKS_PRODUCT_ID = "\$\(PRODUCT_BUNDLE_IDENTIFIER\)\.looks\.all";' "${all_looks_project}")" -eq 2
python3 - "${all_looks_storekit}" <<'PY'
import json
import sys

storekit_path = sys.argv[1]
with open(storekit_path, encoding="utf-8") as handle:
    configuration = json.load(handle)

expected_id = "com.example.StarCompanion.looks.all"
matches = [
    product
    for product in configuration.get("products", [])
    if product.get("productID") == expected_id
]
assert len(matches) == 1, f"expected one {expected_id} product, got {len(matches)}"
product = matches[0]
assert product.get("type") == "NonConsumable", product
assert product.get("familyShareable") is False, product
assert float(product.get("displayPrice", 0)) > 0, product
locales = {entry.get("locale") for entry in product.get("localizations", [])}
locale_aliases = {"en": "en_US", "ko": "ko_KR", "zh_Hant": "zh_TW"}
assert {locale_aliases.get(locale, locale) for locale in locales} == {"en_US", "ko_KR", "zh_TW"}, locales
for localization in product["localizations"]:
    assert localization.get("displayName", "").strip(), localization
    assert localization.get("description", "").strip(), localization
PY
echo "All-looks non-consumable Info.plist, build setting, and StoreKit fixture verified"

xcrun swiftc -parse-as-library \
  ios/StarCompanion/StarCompanion/AuthModels.swift \
  ios/StarCompanion/StarCompanion/AuthServices.swift \
  ios/StarCompanion/StarCompanion/Models.swift \
  ios/StarCompanion/StarCompanion/TarotDeck.swift \
  ios/StarCompanion/StarCompanion/StarSkinCatalog.swift \
  ios/StarCompanion/StarCompanion/StarSkinCatalog.generated.swift \
  ios/StarCompanion/StarCompanion/StarLifeModels.swift \
  ios/StarCompanion/StarCompanion/HomeVisitExchange.swift \
  ios/StarCompanion/StarCompanion/AccountStorage.swift \
  ios/StarCompanion/StarCompanion/AccountCloudSyncService.swift \
  scripts/verify_account_cloud_api.swift \
  -o "${build_dir}/verify_account_cloud_api"
"${build_dir}/verify_account_cloud_api"

xcrun swiftc -parse-as-library \
  ios/StarCompanion/Shared/StarPetWatchShared.swift \
  scripts/verify_watch_companion.swift \
  -o "${build_dir}/verify_watch_companion"
"${build_dir}/verify_watch_companion"

watch_privacy_manifest="ios/StarCompanion/StarPetWatch/PrivacyInfo.xcprivacy"
watch_project_file="ios/StarCompanion/StarCompanion.xcodeproj/project.pbxproj"
plutil -lint "${watch_privacy_manifest}" >/dev/null
test "$(plutil -extract NSPrivacyAccessedAPITypes.0.NSPrivacyAccessedAPIType raw -o - "${watch_privacy_manifest}")" = \
  "NSPrivacyAccessedAPICategoryUserDefaults"
test "$(plutil -extract NSPrivacyAccessedAPITypes.0.NSPrivacyAccessedAPITypeReasons.0 raw -o - "${watch_privacy_manifest}")" = \
  "CA92.1"
rg -q "A3000000000000000000000A /\\* PrivacyInfo.xcprivacy in Resources \\*/" "${watch_project_file}"
rg -q "B3000000000000000000000D /\\* PrivacyInfo.xcprivacy \\*/" "${watch_project_file}"
echo "Watch privacy manifest and UserDefaults reason verified"

python3 scripts/verify_privacy_manifests.py

python3 scripts/verify_star_skin_collection.py

echo "All Star Companion foundation verifiers passed"
