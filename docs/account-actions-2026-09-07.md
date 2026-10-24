# 第 2、5 項交付紀錄

2026-09-07：程式已實作，Worker 與 D1 migration 0003 已部署。正式 Apple 帳號端到端驗收仍受外部設定與網路可達性阻擋。

## 第 2 項：完整刪除帳號

「我的 → 刪除帳號」有範圍說明與二次確認。服務先暫停該帳號的同步，撤銷 Apple 憑證，再以交易刪除帳號、私人資料、session、成員關係與邀請。其他成員的私人帳號保留。

App 保留必要的重試狀態，支援斷網、token 過期、重開 App、Keychain 清理失敗及伺服器回應遺失。伺服器成功後才清除目前帳號的本機資料，不會清到其他帳號。重新註冊取得新的帳號 ID，不會接回已刪除的快取。

永久刪除回執只保留隨機憑證與要求的雜湊、成功結果和建立時間，不含帳號／Apple 身份／明文 token。短期身份防競態紀錄與過期邀請由定期工作清理。其他離線裝置的副本需在該裝置清除；Apple 訂閱與退款不屬刪帳功能。

## 第 5 項：真實朋友邀請

原生邀請頁可建立、分享、貼码加入與撤銷邀請，星球設定可退出。伺服器限制每顆星球兩人，每個帳號只加入一顆；七日單次高熵邀請碼只存雜湊，有操作限流。新碼會撤銷自己之前未使用的舊碼。

成員列表改由服務讀取，顯示真正的暱稱與造型，不再用本機示範成員表示已配對。只分享成員公開資料，不分享出生資料、抽牌和私人留言。餵食、心情與遊戲進度仍屬個人帳號，這次不包含兩人即時共同養成。

分享網址使用 fragment 帶碼，支援 custom scheme／手動貼碼；Universal Links 接線已加上，但須完成正式 Apple App ID 與 Associated Domains 設定。App 與邀請落地頁有繁中、英文、韓文。

## 驗證

- `bash scripts/verify_ios_foundation.sh`：全部通過，包含新增刪帳／邀請／wire contract 測試。
- iOS simulator Debug 與 Release build：通過，包含 iPad／Watch 相關編譯。
- Worker `npm test`：32／32 通過；包含兩個接受者搶最後席、接受與撤銷競態、並行替換邀請、DB 雙人限制、Apple 撤銷失敗／重試與資料隔離。
- Worker TypeScript 與 Wrangler dry-run：通過。
- iPhone 繁中／iPad 英文：檢查邀請頁與連結帶碼；iPhone 輸入欄位能叫出鍵盤。使用的是明確標示的本機預覽帳號，沒有冒充正式 Apple 驗證。
- 生產 D1 migration 0003 已套用；Worker version `c4340f61-7ea2-4315-843d-48c644e8e830` 已部署，包含每 15 分鐘的過期資料清理。
- 沒有刪除任何正式帳號來測試；破壞性案例僅使用隔離的測試資料庫。

## 尚待提供／確認

1. 正式 Apple Bundle ID、Team，以及伺服器所需的六項 Secret。私鑰應透過本機安全檔案／Cloudflare Secret 設定，不要貼在聊天或提交到 repository。
2. 可在目標市場連線的 API 網域。目前開發網路連 `workers.dev` 時在 TLS 建連階段失敗；Cloudflare 部署成功不等於公開路徑已驗證。
3. 完成前兩項後，用兩個正式 Apple 帳號做真機加入、退出、換機與刪帳驗收。

設定細節見 [Apple 登入上線檢查](../ios/StarCompanion/AUTH_DEPLOYMENT.md) 與 [帳號資料儲存](account-storage.md)。
