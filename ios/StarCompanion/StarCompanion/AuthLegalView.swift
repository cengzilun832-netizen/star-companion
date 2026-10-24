import SwiftUI

enum AuthLegalDocument: String, Identifiable {
    case terms
    case privacy

    var id: String { rawValue }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .terms: language.text("使用者協議", "이용약관", "Terms of Use")
        case .privacy: language.text("隱私權政策", "개인정보 처리방침", "Privacy Policy")
        }
    }
}

struct AuthLegalView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let document: AuthLegalDocument

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Label(document.title(in: store.language), systemImage: document == .terms ? "doc.text.fill" : "lock.shield.fill")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Color.celestialPlum)

                    Text(store.language.text(
                        "最後更新：2026 年 9 月 7 日",
                        "최종 업데이트: 2026년 9월 7일",
                        "Last updated: September 7, 2026"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    ForEach(sections.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(sections[index].title)
                                .font(.headline)
                            Text(sections[index].body)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial, in: .rect(cornerRadius: 20))
                    }
                }
                .frame(maxWidth: 760)
                .padding(22)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(document.title(in: store.language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.language.text("完成", "완료", "Done"), action: dismiss.callAsFunction)
                }
            }
        }
    }

    private var sections: [(title: String, body: String)] {
        switch document {
        case .terms:
            [
                (
                    store.language.text("這是什麼", "서비스 안내", "What this app is"),
                    store.language.text(
                        "星伴提供運勢、塔羅與可愛星星互動。內容是生活靈感與娛樂，不是醫療、法律或理財建議。",
                        "별동무는 운세, 타로, 귀여운 별과의 상호작용을 제공합니다. 콘텐츠는 일상의 영감과 즐거움을 위한 것으로, 의료·법률·재정 조언이 아닙니다.",
                        "Star Companion offers fortunes, tarot, and a playful star companion. Its content is for reflection and entertainment, not medical, legal, or financial advice."
                    )
                ),
                (
                    store.language.text("登入與預覽", "로그인과 미리보기", "Sign-in and previews"),
                    store.language.text(
                        "預覽版可以建立未經伺服器驗證的本機測試帳號，畫面會清楚標示。正式帳號必須等後端完成 Apple、手機或微信憑證驗證。",
                        "미리보기 버전에서는 서버 검증을 거치지 않은 기기 내 테스트 계정을 만들 수 있으며 화면에 명확히 표시됩니다. 정식 계정은 서버에서 Apple·휴대폰·WeChat 인증을 확인한 후에만 생성됩니다.",
                        "Preview builds may create clearly labelled on-device test accounts that aren't server-verified. Production accounts require backend verification of Apple, phone, or WeChat credentials."
                    )
                ),
                (
                    store.language.text("分享與星塵", "공유와 별가루", "Sharing and Stardust"),
                    store.language.text(
                        "你只會在主動點選分享後將所選內容交給 iOS 分享服務。目前的離線訪客回條沒有伺服器簽章；星塵沒有現金價值，不能交易。",
                        "직접 공유를 선택한 경우에만 선택한 내용이 iOS 공유 서비스로 전달됩니다. 현재의 오프라인 방문 답장은 서버 서명이 없으며, 별가루는 현금 가치가 없고 거래할 수 없습니다.",
                        "Selected content reaches iOS sharing services only after you choose to share it. Offline visit receipts aren't server-signed; Stardust has no cash value and can't be traded."
                    )
                ),
            ]
        case .privacy:
            [
                (
                    store.language.text("登入資料", "로그인 정보", "Sign-in data"),
                    store.language.text(
                        "使用正式帳號登入時，星伴會把登入提供者識別碼、帳號識別碼與驗證所需的資料傳給星伴帳號服務。登入憑證保存在 iOS 鑰匙圈；手機號碼與一次性驗證碼不會以明文寫入 UserDefaults 或日誌。",
                        "정식 계정으로 로그인하면 로그인 제공자 식별자, 계정 식별자와 인증에 필요한 정보가 별동무 계정 서비스로 전송됩니다. 로그인 인증 정보는 iOS 키체인에 보관하며, 휴대폰 번호와 일회용 코드는 UserDefaults나 로그에 평문으로 기록하지 않습니다.",
                        "When you use a verified account, Star Companion sends the sign-in provider identifier, account identifier, and verification data needed to the Star Companion account service. Sign-in credentials are kept in iOS Keychain. Phone numbers and one-time codes aren't written in plaintext to UserDefaults or logs."
                    )
                ),
                (
                    store.language.text("帳號資料存在哪裡", "계정 데이터 저장 위치", "Where account data is stored"),
                    store.language.text(
                        "這不是 iCloud 同步。正式帳號通過後端驗證後，出生資料、運勢收藏、塔羅紀錄、星星造型、星球與遊戲進度會連同帳號識別碼保存在星伴帳號服務；這部裝置也會保留一份離線資料。換機後登入同一帳號，就可以取回。",
                        "iCloud 동기화가 아닙니다. 정식 계정이 서버 검증을 마치면 출생 정보, 저장한 운세, 타로 기록, 별 외형, 별과 게임 진행 정보가 계정 식별자와 함께 별동무 계정 서비스에 보관됩니다. 이 기기에도 오프라인 사용을 위한 복사본이 남으며, 다른 기기에서 같은 계정으로 로그인하면 다시 받을 수 있습니다.",
                        "This isn't iCloud sync. After a verified sign-in, birth details, saved fortunes, tarot history, star looks, planet data, and game progress are stored with the account identifier in the Star Companion account service. This device also keeps an offline copy. Sign in to the same account on another device to retrieve it."
                    )
                ),
                (
                    store.language.text("留在裝置上的內容", "기기에 남는 데이터", "What stays on the device"),
                    store.language.text(
                        "未通過後端驗證的預覽帳號不會上傳帳號內容。介面語言、每日魔法門、提醒設定與回饋草稿留在本機。Apple Watch 不會直接連線帳號服務；操作會先傳到配對的 iPhone，再由 iPhone 依同一帳號同步。",
                        "서버 검증을 거치지 않은 미리보기 계정은 계정 내용을 업로드하지 않습니다. 앱 언어, 매일의 마법 문, 알림 설정과 피드백 초안은 기기에 남습니다. Apple Watch는 계정 서비스에 직접 연결하지 않고, 작업을 페어링된 iPhone으로 먼저 보낸 뒤 iPhone이 같은 계정으로 동기화합니다.",
                        "Preview accounts that haven't been verified by the backend don't upload account content. App language, the daily magic gate, reminder settings, and feedback drafts stay on the device. Apple Watch doesn't connect to the account service directly; actions go to the paired iPhone first, and the iPhone syncs them under the same account."
                    )
                ),
                (
                    store.language.text("星球邀請", "별 초대", "Planet invitations"),
                    store.language.text(
                        "建立或接受邀請後，服務會保存星球成員關係、邀請狀態與到期時間。同一顆星球的成員可以看到彼此的暱稱與星星造型，但不會因此取得對方的出生資料、抽牌紀錄或私人留言。你可以在星球設定退出；尚未使用的邀請可以在邀請頁撤銷。",
                        "초대를 만들거나 수락하면 서비스에 별 멤버 관계, 초대 상태와 만료 시간이 저장됩니다. 같은 별의 멤버는 서로의 별명과 별 외형을 볼 수 있지만 출생 정보, 타로 기록이나 비공개 메모에는 접근할 수 없습니다. 별 설정에서 나갈 수 있으며, 사용하지 않은 초대는 초대 화면에서 취소할 수 있습니다.",
                        "Creating or accepting an invitation stores the planet membership, invitation status, and expiry on the service. Members of the same planet can see each other's nickname and star look, but this doesn't grant access to birth details, tarot history, or private notes. You can leave in Planet Settings or revoke an unused invitation on the invitation screen."
                    )
                ),
                (
                    store.language.text("用途與分享", "이용 목적과 공유", "Use and sharing"),
                    store.language.text(
                        "帳號資料只用來登入、同步與提供個人化內容。星伴不出售資料，也不拿來跨 App 或網站追蹤你。你主動分享時，所選內容才會交給 iOS 分享服務。",
                        "계정 데이터는 로그인, 동기화와 개인화된 콘텐츠 제공에만 사용합니다. 별동무는 데이터를 판매하지 않고, 다른 앱이나 웹사이트에서 사용자를 추적하는 데 사용하지 않습니다. 직접 공유할 때만 선택한 내용이 iOS 공유 서비스로 전달됩니다.",
                        "Account data is used only for sign-in, syncing, and personalized app content. Star Companion doesn't sell it or use it to track you across apps or websites. Content reaches iOS sharing services only when you choose to share it."
                    )
                ),
                (
                    store.language.text("刪除重試紀錄", "삭제 재시도 기록", "Deletion retry record"),
                    store.language.text(
                        "刪除成功後，服務會保留安全憑證與刪除要求的雜湊及成功結果，不包含帳號識別碼、Apple 身份或明文憑證。即使手機沒有收到第一次的回應，也能確認刪除已完成。",
                        "삭제 후에는 보안 인증 정보와 삭제 요청의 해시 및 성공 결과를 보관합니다. 계정 식별자, Apple 신원이나 평문 인증 정보는 포함하지 않습니다. 기기가 첫 응답을 받지 못했어도 삭제 완료를 확인할 수 있도록 하기 위함입니다.",
                        "After deletion, the service keeps hashes of the secure credential and deletion request, plus the success result. This record contains no account identifier, Apple identity, or plaintext credential. It lets your device confirm completion even if it missed the first response."
                    )
                ),
                (
                    store.language.text("登出與刪除", "로그아웃과 삭제", "Sign-out and deletion"),
                    store.language.text(
                        "在「我的」中選擇「刪除帳號」，可撤銷 Apple 登入憑證並刪除服務上的帳號、私人資料、成員關係與邀請，同時清除這部裝置上該帳號的資料。刪除中斷時會暫停同步，保留必要的重試紀錄。其他離線裝置的副本須在該裝置清除。刪除帳號不會取消 Apple 訂閱或自動退款。「登出」及「刪除所有本機個人資料」不會刪除服務上的帳號。",
                        "내 프로필의 '계정 삭제'에서 Apple 로그인 인증을 취소하고 서버의 계정, 개인 데이터, 멤버 관계와 초대를 삭제하며 이 기기의 해당 계정 데이터도 지울 수 있어요. 중단되면 동기화를 멈추고 재시도 기록을 보관합니다. 다른 오프라인 기기의 복사본은 해당 기기에서 지워 주세요. 계정 삭제는 Apple 구독을 취소하거나 자동 환불하지 않습니다. 로그아웃과 기기 데이터 삭제는 서버 계정을 삭제하지 않습니다.",
                        "Choose Delete account in Profile to revoke Apple sign-in and remove your account, private data, memberships, and invitations from the service, and clear this account's data from this device. Interrupted deletion pauses sync and retains the information needed to retry. Clear copies on other offline devices on those devices. Deleting an account doesn't cancel Apple subscriptions or issue refunds. Signing out or clearing local data doesn't delete your account from the service."
                    )
                ),
            ]
        }
    }
}
