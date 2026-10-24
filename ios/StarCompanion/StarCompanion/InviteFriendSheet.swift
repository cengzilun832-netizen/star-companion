import SwiftUI

struct InviteFriendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var relationship = StarRelationship.friend
    @State private var invitation: PlanetInvitation?
    @State private var code = ""
    @State private var joined = false
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Image("StarPet").resizable().scaledToFit().frame(width: 72, height: 72).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(store.language.text("為朋友留一個位置", "친구를 위한 자리", "Save a place for a friend")).font(.headline)
                            Text(store.language.text("一顆星球，住下你們兩個。", "하나의 별, 함께하는 두 사람.", "One little planet for the two of you."))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if !store.canUseAccountActions {
                        Label(store.language.text("登入正式帳號後，就能建立或接受邀請。", "정식 계정으로 로그인하면 초대를 만들거나 받을 수 있어요.", "Sign in with a verified account to create or accept invitations."), systemImage: "lock.shield")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if joined {
                    Section {
                        Label(store.language.text("你們住進同一顆星球了", "같은 별에 살게 되었어요", "You're on the same planet now"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button(store.language.text("回到星球", "별로 돌아가기", "Back to the planet")) { dismiss() }
                    }
                } else {
                    Section(store.language.text("我有邀請碼", "초대 코드가 있어요", "I have an invitation")) {
                        TextField(store.language.text("貼上邀請碼或連結", "초대 코드 또는 링크 붙여넣기", "Paste an invitation code or link"), text: $code, axis: .vertical)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($codeFocused)
                            .lineLimit(2...3)
                            .onChange(of: code) { _, value in if value.count > 512 { code = String(value.prefix(512)) } }
                        Text(store.language.text("加入後，對方會看到你的帳號暱稱和星星造型。出生資料、抽牌紀錄與私人留言不會分享。", "참여하면 상대에게 계정 이름과 별 모습이 보여요. 출생 정보, 카드 기록과 개인 메모는 공유하지 않아요.", "Your account name and star look will be visible to your companion. Birth details, readings, and private notes stay private."))
                            .font(.caption).foregroundStyle(.secondary)
                        Button {
                            codeFocused = false
                            Task { joined = await store.acceptPlanetInvite(code) }
                        } label: {
                            Label(store.language.text("加入朋友的星球", "친구의 별에 참여", "Join your friend's planet"), systemImage: "person.2.fill")
                        }
                        .disabled(!store.canUseAccountActions || store.isUpdatingPlanet || PlanetInviteCode.parse(code, allowedHost: store.invitationHost) == nil)
                    }
                    Section {
                        Picker(store.language.text("你們的關係", "우리의 관계", "Your relationship"), selection: $relationship) {
                            ForEach(StarRelationship.allCases) { item in Text(item.title(in: store.language)).tag(item) }
                        }
                        .disabled(store.sharedMembership != nil || store.isUpdatingPlanet)
                        if let invitation {
                            TimelineView(.periodic(from: .now, by: 30)) { context in
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(invitation.code).font(.body.monospaced()).textSelection(.enabled)
                                    if context.date < invitation.expiresAt {
                                        Text(invitation.expiresAt, format: .dateTime.month().day().hour().minute())
                                            .font(.caption).foregroundStyle(.secondary)
                                        ShareLink(item: invitation.url, subject: Text(store.language.text("一起住進星球", "같은 별에서 만나요", "Join my planet"))) {
                                            Label(store.language.text("分享邀請", "초대 공유", "Share invitation"), systemImage: "square.and.arrow.up")
                                        }
                                    } else {
                                        Text(store.language.text("邀請已過期，請建立新的邀請。", "초대가 만료되었어요. 새 초대를 만들어 주세요.", "This invitation expired. Create a new one."))
                                            .foregroundStyle(.secondary)
                                    }
                                    Button(store.language.text("撤銷這份邀請", "초대 취소", "Revoke invitation"), role: .destructive) {
                                        Task { if await store.revokePlanetInvite(invitation.code) { self.invitation = nil } }
                                    }.disabled(store.isUpdatingPlanet)
                                }
                            }
                        }
                        Button {
                            Task { invitation = await store.createPlanetInvite(relationship: relationship) }
                        } label: {
                            Label(store.language.text("建立新邀請", "새 초대 만들기", "Create new invitation"), systemImage: "plus.circle.fill")
                        }
                        .disabled(!store.canUseAccountActions || store.isUpdatingPlanet || (store.sharedMembership?.members.count ?? 0) >= 2)
                    } header: {
                        Text(store.language.text("邀請朋友", "친구 초대", "Invite a friend"))
                    } footer: {
                        Text(store.language.text("邀請七天內有效，只能由一位朋友使用。建立新邀請會讓你之前未使用的邀請失效；也可以直接撤銷這一份。", "초대는 7일 동안 한 사람만 사용할 수 있어요. 새 초대를 만들면 이전의 사용하지 않은 초대는 무효가 됩니다. 현재 초대를 직접 취소할 수도 있어요.", "Invitations last seven days and can be used by one friend. Creating a new one replaces your previous unused invitation. You can also revoke this one."))
                    }
                }
                if store.isUpdatingPlanet { Section { ProgressView(store.language.text("處理中…", "처리 중…", "Working…")) } }
                if let error = store.planetServiceError { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle(store.language.text("邀請朋友", "친구 초대", "Invite a Friend"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.language.text("關閉", "닫기", "Close")) {
                        store.pendingPlanetInviteCode = nil
                        dismiss()
                    }.disabled(store.isUpdatingPlanet)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(store.language.text("完成", "완료", "Done")) { codeFocused = false }
                }
            }
            .interactiveDismissDisabled(store.isUpdatingPlanet)
            .task {
                code = store.pendingPlanetInviteCode ?? ""
                await store.refreshSharedPlanet()
                relationship = store.visiblePlanetRelationship
            }
            .onChange(of: store.sharedMembership?.relationship) { _, value in if let value { relationship = value } }
        }
    }
}
