# 星伴 · Star Companion

以「和重要的人一起養一顆星」為核心的星空陪伴產品。這個倉庫同時保存 SwiftUI 的 iOS／iPadOS／watchOS 原始碼、Cloudflare Worker 帳號服務，以及可以直接在瀏覽器使用的 React 網頁版。視覺延續安靜、夢幻、有收藏感的像素星空世界。

## 網頁版

- 公開網址：[Star Companion Web](https://cengzilun832-netizen.github.io/star-companion/)
- 本機執行：`npm ci` 後執行 `npm run dev`；正式建置：`npm run build`。
- 包含每日第一次開啟的魔法門、今日運勢與翻牌指引、每日一次塔羅、星寵餵養／換造型、繁體中文／英文／韓文，以及回饋入口。支援手機、平板與桌面瀏覽器，也尊重系統的「減少動態效果」。
- 網頁版目前**不提供正式登入或付款**。暱稱、星座、抽牌與星寵進度只存於當前瀏覽器的 `localStorage`，不會自動跟 iOS 帳號同步；清除瀏覽器資料後無法還原。iOS 正式帳號資料的同步機制與網頁版不同，不應混為一談。
- 回饋會開啟此公開倉庫的 [GitHub Issues](https://github.com/cengzilun832-netizen/star-companion/issues)。送出前請勿填入私人資料。
- 網頁版畫面設計稿在 `concepts/web-*-concept.png`，可重用的觀星場景在 `assets/web/stargazing-garden.png`。

本公開備份包含原始碼、設計素材、專案文件與測試腳本；不包含 `node_modules`、編譯產物、本機憑證、暫存設定與 `artifacts/` 的測試截圖／錄影。這些生成檔仍保留在本機，不會被 Git 清除。

## 平台说明

- 正式客户端位于 [`ios/StarCompanion`](ios/StarCompanion)，使用 SwiftUI、原生 `TabView`、`NavigationStack`、`sheet`、Dynamic Type 与 iOS Safe Area。
- 根目錄的 React/Vite 頁面是獨立網頁版，不使用 WebView，也不是微信小程序；其資料目前只保存在瀏覽器。
- 主要设计与最低系统版本均为 iOS 26；使用 Xcode 26 SDK、SwiftUI 原生 `TabView`／`NavigationStack`、Liquid Glass 与 iOS Safe Area。Debug 與 Release 均已在 iOS 26 Simulator SDK 完成編譯驗證。

## 这一版新增的核心链路

1. **三種登入入口**：保留微信，加入 Apple 原生登入與手機 OTP。Debug 版只建立有明確標示的本機測試帳號（OTP 測試碼為 `123456`）；Release 版在後端尚未配置時會直接說明無法建立正式帳號，不會偽造已驗證的 token。
2. **好友共同养宠**：共享星球顶部展示共同居住成员，喂星粮、摸摸和每日任务都会更新宠物状态与动态。
3. **微信好友邀请**：在 App 内选择关系空间，再通过 iOS 分享 / 微信 OpenSDK 跳到微信选择好友；接受邀请后由 Universal Link 回到 App。
4. **关系空间**：“星星好友”“星星闺蜜”和“星星情侣”均可选择；邀请链接会携带关系类型，接受后同步到共享星球。
5. **帳號隔離與跨裝置同步**：正式帳號的運勢設定、出生資料、收藏、抽牌紀錄、星球、星糧、任務與星星造型會存進星伴帳號服務，並按 canonical account ID 隔離。iPhone 留一份按帳號分開的離線副本；登入 session 與憑證只放在 iOS Keychain。手機號、OTP 與明文 access token 不會寫進 `UserDefaults`、D1 或 log。
6. **灵动岛陪伴**：原生 App 已加入 ActivityKit + WidgetKit Live Activity，在灵动岛的紧凑状态显示小星与实时星粮，展开状态显示陪伴文字和进度。系统不会循环播放 GIF，因此灵动岛使用同一动画素材提取的静态庆祝帧，并在喂养、摸摸和任务完成时更新内容。
7. **每日旅程**：每日指引可收藏到装置，最多保留 30 张；「我的」显示连续开启天数，并可由使用者主动开启 iOS 本机每日提醒。
8. **每日双星时刻**：好友、闺蜜、情侣空间各有不同的每日问题；使用者可记录心情与一句话，保存时提供原生触觉反馈，隔日自动重置。
9. **抽牌紀錄**：每次抽牌保存主題、問題、牌名、正／逆位與解讀，最多保留 50 筆；支援原生搜尋、系統分享與單筆刪除。
10. **塔羅抽牌儀式**：三張星空牌以原生 SwiftUI 完成洗牌、選牌、發光與 3D 翻面；中途取消不保存問題，完成後才寫入抽牌紀錄，並針對「減少動態效果」縮短動畫。
11. **完整本機牌庫**：22 張大阿爾克那均有正／逆位、關鍵字與中韓雙語原創牌義；同一天以主題和問題穩定抽牌，牌義運算不依賴網路。正式登入後，問題與抽牌紀錄會跟帳號同步；本機預覽帳號不會上傳。
12. **雙星星圖**：好友、閨蜜和情侶空間各自保存每日心情；最近七天會亮成星座連線，並顯示連續天數。點開可回看最多 90 天的留言。正式登入後資料會跟帳號同步，但目前不是兩位使用者之間的即時共同編輯。
13. **雙星紀念卡**：使用 `ImageRenderer` 產生 1080 × 1350 PNG，透過 iOS 系統分享面板輸出。卡片只包含兩隻 IP、關係類型、七日星圖與連續天數，不帶使用者名字或私人留言。
14. **一次買斷全部造型**：衣櫤另有 StoreKit 2 非消耗型商品，購買後解鎖現有與日後新增的小星造型和配件。價格來自 App Store 當地商店；權益由已驗證交易決定，而星幣、穿著與養成進度仍跟著 Star Companion 帳號同步。

> 微信不会向第三方 iOS App 开放完整好友通讯录，因此正式版不会在 App 内直接读取微信好友列表。上线需要微信开放平台 AppID、iOS OpenSDK 回调、Associated Domains / Universal Link、服务端账号绑定与邀请关系接口，以及相应的用户协议与隐私合规流程。

> 帳號快照服務已部署到 Cloudflare Worker + D1；D1 是正式帳號資料的主版本，手機只保留離線副本。Privacy Manifest 與 App 內說明已按這個行為更新。Apple、手機與微信只有通過後端驗證後才會取得正式 session；本機預覽帳號永遠不會上傳。

## 原有内容模块

星宠之外保留两个原生内容模块：

1. **今日運勢**：先給一句能記住的總結，再提供愛情、工作、財運、心情四個分類與一張「今日指引」。
2. **塔羅**：使用者選擇主題，也可以寫下一個問題，再抽一張本機牌卡。

兩個模組已接入 SwiftUI 主分頁，包含四項運勢切換、今日指引 Sheet、三種抽牌主題、問題輸入和牌義結果頁。

「我的」分頁已接入两步出生资料设置、太阳星座推算、关注主题以及本机资料删除；默认首页为「星宠」。

提醒偏好與通知排程留在裝置；收藏、連續天數及其他帳號內容在正式登入後會同步到星伴帳號服務。通知仍由 `UNUserNotificationCenter` 本機排程，只有使用者打開開關時才請求權限，不經過遠端推送服務。

每日雙星的心情與留言會隨自己的正式帳號備份，但不會自動傳給另一位使用者；真正的雙人共享仍要等雙方明確同意與關係服務完成後才開放。

抽牌問題可能包含私人內容。正式帳號會把它與抽牌紀錄一起加密傳輸到帳號服務；本機預覽不會上傳。只有使用者主動點擊分享時，所選內容才會交給 iOS 分享面板。

## 核心保留项目

以下体验已经确定为产品核心，后续迭代不可移除：

- 每天第一次打开 App 时出现的魔法大门仪式。
- 星星锁发光、魔法粒子扩散、左右门扇打开的动画。
- 镜头沿门后小路前进、穿过门洞并以柔光衔接首页的完整过场。
- 用户开启「减少动态效果」时，保留仪式含义并缩短动画。
- 隱私說明：正式登入後，運勢設定、抽牌、出生資料與星球進度會保存到星伴帳號服務，並在裝置留一份離線副本；本機預覽不會上傳。登入只處理帳號保護與同步所需的提供者識別資料及憑證；使用者主動分享時，所選內容才會交給 iOS 分享服務。

以上项目可以继续优化画质、节奏和性能，但不能被普通登录页、静态启动图或直接切页替代。React 视觉原型与原生 iOS 客户端都必须保留同一套体验语义。

> 離線訪客卡與回條目前沒有伺服器簽章，只是可愛的本機互動；星塵沒有現金價值，不能交易。已加入重播記錄與每日總接收上限，但不把它當成可交易經濟。

## iOS 26 设计原则

- Liquid Glass 只用于 Tab Bar、Toolbar、主操作按钮与短暂互动控制，内容卡片继续使用标准材质，避免玻璃层级混乱。
- iPhone 的 Tab Bar 随内容向下滚动时缩小，让像素世界获得更多可视空间。
- 系统导航、Sheet、Menu、Toggle 与分享流程优先使用 SwiftUI 原生组件，让 iOS 26 自动提供正确的玻璃形态与转场。
- 品牌色通过玻璃的 `tint` 表达；像素角色、魔法门与场景图仍属于内容层，不套玻璃滤镜。
- 必须支持 Dynamic Type、VoiceOver、Safe Area、深色模式与「减少动态效果」。

## 原型包含

- 響應式網頁版（另保留舊的 430 × 930 iPhone 視覺原型原始碼）
- 固定 iOS Safe Area 底部分頁列
- 四項運勢切換與文字提示
- 今日塔羅指引 Bottom Sheet
- 問題輸入、類型切換、正／逆位與抽牌結果
- 兩步首次個人化設定：稱呼、生日、選填出生時間／地點與關注主題
- 依生日計算太陽星座，並同步到首頁與「我的宇宙」
- 個人頁、每日提醒開關與設定 Bottom Sheet
- React 視覺原型不連接帳號服務並使用 `localStorage`；原生 iOS App 的正式帳號資料使用 Worker + D1，本機離線副本按帳號分區存放，session 放在 iOS Keychain
- `prefers-reduced-motion` 動畫降級

## 建議的正式資料策略

- 星體位置：採用可靠的星曆資料或天文計算套件，不從一般運勢網站複製文章。
- 塔羅牌義：目前使用 App 內建的 22 張大阿爾克那原創牌義，包含正／逆位、關鍵字與具體提醒。
- 每日解讀：由本機日期、星座與編輯規則產生；文字不從一般運勢網站複製。
- 個人化：使用出生日期、時間、地點計算太陽、月亮與上升星座；所有敏感資料需清楚說明用途。
- 產品定位：內容僅供娛樂與自我探索，不提供醫療、法律或投資結論。

## 本機執行

### 星星造型素材庫

`assets/pet/skins/collection` 是原始 PNG 的單一來源。新增或替換素材後，不需要手寫 Swift enum 或逐個建立 imageset，執行：

```bash
python3 scripts/sync_star_skin_collection.py
python3 scripts/verify_star_skin_collection.py
```

同步程式會將商店用圖縮到 512 px，產生 `SkinCollection*.imageset` 與 `StarSkinCatalog.generated.swift`，並以穩定 ID 產生稀有度及價格。這些產物不要手動編輯。現有 20 個舊形象繼續沿用原本的 ID；素材庫中和它們重複的 13 張會自動排除，避免已購記錄失效或商店出現重複卡片。

核心資料遷移、帳號雲端同步、每日限制、星星生活、家園交換、登入安全、造型庫與 Watch 同步可一次驗證：

```bash
./scripts/verify_ios_foundation.sh
```

原生 iOS：

```bash
open ios/StarCompanion/StarCompanion.xcodeproj
```

在 Xcode 选择 `StarCompanion` Scheme 和任意 iPhone Simulator 后运行。当前 Bundle Identifier `com.example.StarCompanion`、邀请域名 `example.com` 以及微信配置名都是开发占位，接入正式账号时需要替换。订阅商品通过 Xcode Build Settings 中的 `STARLIGHT_MONTHLY_PRODUCT_ID` 和 `STARLIGHT_YEARLY_PRODUCT_ID` 注入；一次買斷全部造型使用 `ALL_STAR_LOOKS_PRODUCT_ID`。預設都會跟著 Bundle Identifier 產生，不需要修改 Swift 源碼；正式送審前仍要在 App Store Connect 建立完全相同的 Product ID。設定與測試清單見 [`ios/StarCompanion/PURCHASE_DEPLOYMENT.md`](ios/StarCompanion/PURCHASE_DEPLOYMENT.md)。

视觉评审原型：

```bash
npm install
npm run dev
```

正式建置：

```bash
npm run build
```
