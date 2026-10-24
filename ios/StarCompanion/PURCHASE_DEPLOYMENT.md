# 全部造型一次買斷上線清單

「解鎖全部造型」是 StoreKit 2 非消耗型商品，不是訂閱，也不是星幣包。買一次後，App 會依 App Store 驗證過的交易解鎖現有及日後新增的小星完整造型與配件。星幣、目前穿著與其他養成進度仍屬於 Star Companion 帳號資料。

## App Store Connect 設定

1. 先把 Xcode 的 `com.example.StarCompanion` 換成正式 Bundle ID。
2. 新建「非消耗型」In-App Purchase，建議 Reference Name 為 `All Star Looks`。
3. Product ID 要與 build setting `ALL_STAR_LOOKS_PRODUCT_ID` 完全一致；預設是 `$(PRODUCT_BUNDLE_IDENTIFIER).looks.all`。Product ID 建立後無法修改。
4. 新增繁中、韓文與英文商品名稱／說明，並上傳 App Review 需要的截圖。
5. 價格以 App Store Connect 為準；App 只顯示 StoreKit 回傳的當地幣別價格，不在程式裡寫死數字。
6. 將 In-App Purchase 連到要送審的 App 版本，並檢查 Paid Apps Agreement、稅務與銀行資料。

## 資料與復原規則

- App 啟動或回到前景時，會讀取 `Transaction.currentEntitlements`；只接受 StoreKit 驗證通過、未撤銷的指定商品。
- 權益不寫入 `UserDefaults` 或帳號 snapshot，避免過期、退款或被篡改的本機狀態繼續解鎖。
- 「恢復購買」只在使用者主動點擊後呼叫 `AppStore.sync()`，因為系統可能會要求驗證 App Store 帳號。
- 新手機使用同一個 App Store Apple Account 時，StoreKit 會提供原本的非消耗型權益。Star Companion 帳號則負責取回星幣、選中造型與養成進度。
- 購買時會附上由 canonical account ID 穩定產生的假名 UUID `appAccountToken`，不附帶姓名、電話或 Apple 電子郵件。它是日後後端對帳的關聯值，不取代 StoreKit 交易驗證。

## 測試

- Xcode Scheme 已連結 `StarlightMembership.storekit`，可在 Simulator 測試購買、取消、等待核准、恢復與撤銷。
- 送審前再用 App Store Connect Sandbox Apple Account 在真機測試一次。
- 必測：買斷後全造型可立即穿上、重開 App 仍有權益、刪除後重裝可取回、退款／撤銷後重新鎖上、星幣數量不會因買斷而被扣除。
