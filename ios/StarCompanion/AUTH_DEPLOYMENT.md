# Apple 登入上線檢查

iOS 會把 Apple credential 送到 `POST /v1/auth/apple/exchange`，把伺服器簽發的 session 放在 iOS Keychain，再用同一個 access token 同步帳號資料。Access token 快過期或已過期時，App 會先呼叫 `POST /v1/auth/session/refresh`旋轉 access token 與 refresh token，成功後才繼續同步。

上線前還必須完成：

- 把 Xcode 裡的 `com.example.StarCompanion` 換成 Apple Developer 帳號下的正式 Bundle ID，選擇正確 Team，並在該 App ID 開啟 Sign in with Apple。
- Worker 與 D1 migrations `0001`–`0003` 已部署，但 Apple secret 尚未安裝。依 [`backend/README.md`](../../backend/README.md) 設好 `APPLE_CLIENT_ID`、`APPLE_TEAM_ID`、`APPLE_KEY_ID`、`APPLE_PRIVATE_KEY`、`APPLE_REFRESH_TOKEN_ENCRYPTION_KEY` 與 `AUTH_RATE_LIMIT_SALT`。六項未全部有效時，後端會回 `auth_not_configured`，App 會清楚顯示「伺服器驗證尚未配置」，不會建立假帳號。
- `STAR_COMPANION_API_BASE_URL` 目前指向已部署的 Worker，同時供 auth 與 snapshot 使用。送審前要從真機確認 DNS/TLS 可達；如果改用自訂網域，直接覆寫這個 build setting，不需要改 Swift 程式。
- 手機 OTP 目前由 `STAR_COMPANION_PHONE_OTP_ENABLED = NO` 明確關閉；在簡訊供應商與後端端點真正完成前不要開啟。

Keychain 使用 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`，token 不會被備份搬到新手機。換機後使用同一 Apple 帳號重新登入，App 會從帳號服務取回資料；資料跟帳號走，不是跟手機或 iCloud Keychain 走。

## 帳號刪除與邀請（2026-09-07）

- 原生刪除入口、刪除中斷續試、目前帳號的本機清理已接到 `DELETE /v1/account`。正式 Apple 撤銷流程共用上述六項 Secret，不能用預覽帳號驗收正式撤銷。
- 星球邀請已接到 `/v1/planet`、`/v1/planet/invites`、`/v1/planet/invites/accept`、`/v1/planet/membership`；後端 migration `0003_account_deletion_and_planets.sql` 已套用。
- Associated Domains entitlement 使用 `applinks:$(STAR_COMPANION_INVITE_HOST)`。目前 host 為既有 Worker；改網域時必須同時更新 API URL、邀請 host 與網域上的 AASA。
- 在正式 App ID 開啟 Associated Domains。AASA 只在後端有有效 `APPLE_TEAM_ID` 與正式 `APPLE_CLIENT_ID` 時回傳 appID，未配置不會冒用 `com.example`。Custom scheme 與手動貼碼仍可作為回到 App 的入口。
- 真機驗收需兩個正式 Apple 測試帳號：建立邀請 → 第二人加入 → 雙方重開顯示相同成員 → 撤銷／過期不能再加入 → 退出；刪除其中一人後確認對方私人 snapshot 仍在。
- 刪除後重新註冊會取得新的 account instance ID，不會沿用已刪除帳號的進度分區。
- 2026-09-07：開發網路直接連現有 `workers.dev` host 遇到 TLS 連線失敗，系統 HTTP／HTTPS proxy 均未啟用。部署本身由 Cloudflare 控制台 API 確認成功；這不代表正式使用者所在網路已可達。需要在目標網路驗證，或提供正式自訂網域。
