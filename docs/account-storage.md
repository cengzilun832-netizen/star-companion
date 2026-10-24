# 帳號資料放在哪裡

星伴不把 iCloud 當成帳號資料的主版本。CloudKit 私有資料庫會跟著裝置上登入的 Apple Account，無法代表 App 裡的 Apple、手機或日後的微信帳號；兩者可能不是同一個人。

正式帳號採用下面的分工：

| 資料 | 儲存位置 | 用途 |
| --- | --- | --- |
| 出生資料、收藏、抽牌紀錄、星球進度、星星造型與養成內容 | Cloudflare D1 `star-companion-production` | 帳號資料的主版本，換裝置後用同一帳號取回 |
| 同一份帳號內容的離線副本與待上傳變更 | iPhone `UserDefaults`，按 canonical account ID 分區 | 沒網路時照常使用，恢復連線後再同步 |
| App access token／refresh token | iOS Keychain，`WhenUnlockedThisDeviceOnly` | 只讓目前這台裝置使用；換機時重新登入，不搬移憑證 |
| App access token 的 SHA-256 雜湊、到期與撤銷狀態 | D1 `auth_sessions` | 後端用 bearer token 找到 canonical account；D1 不存明文 App token |
| 「解鎖全部造型」一次買斷權益 | App Store 已驗證交易 | 跟著購買用的 App Store Apple Account 恢復；不寫成可被修改的本機開關 |
| Watch 畫面狀態 | 配對 iPhone 經 WatchConnectivity 傳送 | Watch 不直接登入，也不直接連帳號服務 |
| 未驗證的 Debug／本機預覽帳號 | 只在目前裝置 | 永遠不上傳，也不會冒充正式帳號 |
| 真實星球成員關係與邀請狀態 | D1 `planets`、`planet_memberships`、`planet_invites` | 每顆星球最多兩人；邀請碼只保存雜湊，成員關係不由本機備份授權 |

## 同步規則

- Client 只送 bearer token，不送 account ID。Worker 在伺服器端由 token 雜湊找出帳號，避免把 A 帳號的內容寫進 B 帳號。
- 每份雲端資料都有 revision。更新時必須帶上自己讀到的 revision，過期版本會收到衝突，不會直接蓋掉較新的資料。
- App 先把修改寫進本機待上傳佇列，再嘗試連線。就算中途關閉 App 或斷網，變更仍會保留。
- 第一次在新裝置登入時以雲端為準；若這台裝置在同步前已經有內容，App 會保留本機與雲端兩份，讓使用者選擇，不會靜默覆寫。
- 付款權益與遊戲進度分開：StoreKit 判定是否已買斷全部造型，星伴帳號服務負責保存你選了哪顆星、星幣與養成進度。

## 正式環境

- Snapshot Worker：`https://star-companion-account-api.cloudocrworker.workers.dev`
- D1：`star-companion-production`，APAC location hint
- iOS 設定鍵：`StarCompanionAccountAPIBaseURL`

目前 Worker 與 D1 已部署。`workers.dev` 在部分網路可能無法直接連線；上架前應換成實際可達的自訂 HTTPS 網域，再把 iOS build setting 指向該網域。

## 登入上線前仍需提供的外部設定

Apple 正式登入不能使用專案裡的 `com.example.StarCompanion` 佔位值。需要在 Apple Developer 完成 App ID 與 Sign in with Apple 設定，然後以 Cloudflare Secret 提供 Team ID、Key ID、`.p8` 私鑰與正式 client ID。私鑰不可提交到 Git、`wrangler.jsonc` 或 App bundle。

手機 OTP 還需要正式簡訊供應商與金鑰；微信入口目前保持關閉。沒有通過後端驗證的登入不會取得 `backendVerified` session，因此也不會上傳帳號資料。

## 刪除帳號

「我的 → 刪除帳號」會先說明刪除範圍，再要求確認。App 呼叫 `DELETE /v1/account`，不再把刪除本機資料當成刪除帳號。

- 服務先鎖住待刪帳號，禁止同步與建立新 session，再撤銷 Apple 登入憑證。
- 撤銷失敗時不會假裝成功，也不先丟掉重試憑證。App 暫停同步，重新開啟後可用同一筆刪除要求繼續。
- 成功後移除帳號、登入 session、Apple identity／加密憑證、私人 snapshot、同步變更紀錄、星球成員關係與該帳號的邀請。另一位成員的帳號與私人資料保留。
- App 再清除目前帳號的 Keychain、本機分區、提醒及 Watch 互動識別。其他帳號的本機分區不受影響；其他離線裝置的副本仍需在該裝置清除。
- 刪除成功的重試收據只保留隨機憑證與要求 ID 的雜湊及成功結果，不保留帳號 ID、Apple identity 或明文 token。保留這份收據是為了處理「伺服器已刪除，但手機未收到回應」的情況。
- 刪除不會取消 Apple 訂閱、退款或刪除 App Store 交易。購買權益仍由 App Store 管理。

## 真實邀請的範圍

邀請頁可以建立分享連結、貼上邀請碼加入、撤銷尚未使用的邀請；星球設定可以退出。邀請七天內有效，只能由一位朋友使用，不能用修改本機 JSON 的方式加入。建立新邀請會讓自己先前未使用的邀請失效。退出後再加入其他星球，不會把自己的私人紀錄交給新朋友。

HTTPS 連結使用 `/invite#code=…`，邀請碼留在 URL fragment，不放在請求路徑或 query。網頁提供開啟 App 與複製邀請碼；App 只在使用者主動開啟連結或貼上內容時讀取，不輪詢剪貼簿。Universal Links 的正式 App ID 仍需 Apple Developer 設定。

目前實作的是「共享成員關係」：顯示彼此暱稱與造型。餵食、心情、留言及遊戲進度仍屬個人帳號，**不是兩人即時共同養成**。這部分不能用邀請成功來代替完成驗收。
