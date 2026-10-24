import AuthenticationServices
import SwiftUI

struct WeChatLoginView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var agreed = false
    @State private var mode = LoginMode.options
    @State private var selectedPhoneRegion = PhoneRegion.suggested
    @State private var phoneNumber = ""
    @State private var verificationCode = ""
    @State private var legalDocument: AuthLegalDocument?
    @FocusState private var focusedField: LoginField?

    private enum LoginMode { case options, phone }
    private enum LoginField { case phone, code }

    var body: some View {
        GeometryReader { proxy in
            let isWide = horizontalSizeClass == .regular && proxy.size.width >= 960
            let horizontalPadding: CGFloat = isWide ? 32 : 18
            let contentWidth = min(1_180, max(1, proxy.size.width - horizontalPadding * 2))
            let contentHeight = max(
                1,
                proxy.size.height
                    - proxy.safeAreaInsets.top
                    - proxy.safeAreaInsets.bottom
                    - (isWide ? 56 : 32)
            )

            ZStack {
                ScrollView(.vertical) {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)

                        if isWide {
                            let authenticationWidth = min(500, max(420, contentWidth * 0.43))
                            let heroWidth = max(1, contentWidth - authenticationWidth - 26)

                            HStack(alignment: .center, spacing: 26) {
                                heroCard(isWide: true)
                                    .frame(width: heroWidth)
                                authenticationCard(isWide: true)
                                    .frame(width: authenticationWidth)
                            }
                            .frame(width: contentWidth)
                            .frame(minHeight: contentHeight)
                        } else {
                            VStack(spacing: 18) {
                                heroCard(isWide: false)
                                authenticationCard(isWide: false)
                            }
                            .frame(width: contentWidth)
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(width: proxy.size.width)
                    .padding(.vertical, isWide ? 28 : 16)
                }
                .scrollIndicators(.hidden)
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height,
                    alignment: .top
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background { loginBackdrop }
        }
        .environment(\.locale, store.language.locale)
        .preferredColorScheme(.dark)
        .alert(
            store.language.text("登入未完成", "로그인 미완료", "Sign-in incomplete"),
            isPresented: Binding(
                get: { store.loginError != nil },
                set: { if !$0 { store.loginError = nil } }
            )
        ) {
            Button(store.language.text("知道了", "확인", "OK"), role: .cancel) {
                store.loginError = nil
            }
        } message: {
            Text(store.loginError ?? "")
        }
        .onChange(of: store.phoneOTPChallenge) { _, challenge in
            if challenge != nil {
                verificationCode = ""
                requestFocus(.code)
            }
        }
        .sheet(item: $legalDocument) { document in
            AuthLegalView(document: document)
                .environmentObject(store)
        }
    }

    private var loginBackdrop: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.035, blue: 0.16),
                    Color(red: 0.12, green: 0.075, blue: 0.28),
                    Color(red: 0.24, green: 0.10, blue: 0.26),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image("StarHabitat")
                .resizable()
                .scaledToFill()
                .opacity(0.25)
                .blendMode(.screen)
            RadialGradient(
                colors: [Color.celestialPink.opacity(0.28), .clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 760
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func heroCard(isWide: Bool) -> some View {
        VStack(spacing: isWide ? 22 : 12) {
            HStack {
                Label {
                    Text(store.language.text("今晚，小星在等你", "오늘도 작은 별이 기다려요", "Little Star is waiting tonight"))
                } icon: {
                    Image(systemName: "sparkles")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.celestialGold)

                Spacer()
                languageMenu
            }

            if isWide {
                Spacer(minLength: 12)
            }

            Image("StarPet")
                .resizable()
                .scaledToFit()
                .frame(
                    width: isWide ? 250 : 124,
                    height: isWide ? 250 : 124
                )
                .shadow(color: Color.celestialGold.opacity(0.34), radius: 28)
                .accessibilityLabel(store.language.text(
                    "發光的小星向你招手",
                    "빛나는 작은 별이 손을 흔들어요",
                    "A glowing Little Star waves hello"
                ))

            VStack(spacing: 9) {
                Text(store.language.text("星伴", "별동무", "Star Companion"))
                    .font(isWide ? .largeTitle.bold() : .title.bold())
                    .fontWidth(.expanded)
                    .foregroundStyle(Color.celestialGold)
                Text(store.language.text(
                    "把每天的小運氣，\n養成你們共有的星光。",
                    "매일의 작은 운을\n우리만의 별빛으로 키워요.",
                    "Turn each day's little luck\ninto starlight you can share."
                ))
                .font(isWide ? .title2.weight(.medium) : .headline.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.94))
            }
            .fixedSize(horizontal: false, vertical: true)

            if isWide {
                Spacer(minLength: 16)
            }

            Label {
                Text(store.language.text(
                    "正式帳號會同步運勢、抽牌與出生資料；本機預覽不會上傳。",
                    "정식 계정은 운세, 카드 기록과 출생 정보를 동기화하며, 기기 미리보기는 업로드하지 않아요.",
                    "Verified accounts sync fortunes, readings, and birth details. Local previews don't upload them."
                ))
            } icon: {
                Image(systemName: "lock.shield.fill")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.68))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(isWide ? 30 : 20)
        .frame(maxWidth: .infinity, minHeight: isWide ? 620 : nil)
        .celestialSurface(
            Material.ultraThin,
            in: RoundedRectangle(cornerRadius: 32),
            reducedColor: .celestialSurfaceOpaque
        )
        .overlay {
            RoundedRectangle(cornerRadius: 32).stroke(.white.opacity(0.20), lineWidth: 1)
        }
    }

    private func authenticationCard(isWide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(mode == .phone
                         ? store.language.text("手機驗證", "휴대폰 인증", "Phone verification")
                         : store.language.text("回到你的星球", "나의 별로 돌아가기", "Return to your little planet"))
                        .font(.title2.bold())
                    Text(mode == .phone
                         ? store.language.text("我們只會用這次驗證來保護帳號。", "이번 인증은 계정을 보호하는 데만 사용해요.", "This verification is used only to protect your account.")
                         : store.language.text("選一個你習慣的方式。", "편한 방법을 하나 골라 주세요.", "Choose whichever way feels familiar."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if mode == .phone {
                    Button {
                        mode = .options
                        verificationCode = ""
                        store.resetPhoneOTP()
                    } label: {
                        Image(systemName: "xmark").frame(width: 36, height: 36)
                    }
                    .celestialGlassButtonStyle()
                    .accessibilityLabel(store.language.text("返回登入方式", "로그인 방법으로 돌아가기", "Back to sign-in options"))
                }
            }

            if mode == .options { signInOptions } else { phoneSignIn }

            Divider().overlay(.white.opacity(0.16))
            agreementControl
            legalLinks
            privacyNote
            environmentNote
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: isWide ? 620 : nil, alignment: .top)
        .foregroundStyle(.white)
        .celestialSurface(
            Material.regular,
            in: RoundedRectangle(cornerRadius: 32),
            reducedColor: .celestialSurfaceElevated
        )
        .overlay {
            RoundedRectangle(cornerRadius: 32).stroke(.white.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 32, y: 18)
    }

    private var signInOptions: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.continue) { request in
                store.prepareAppleSignIn(request)
            } onCompletion: { result in
                Task { await store.completeAppleSignIn(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .clipShape(.rect(cornerRadius: 14))
            .opacity(signInEnabled ? 1 : 0.48)
            .allowsHitTesting(signInEnabled)
            .accessibilityHint(agreementHint)

            Button {
                guard store.isPhoneOTPAvailable else { return }
                mode = .phone
                requestFocus(.phone)
            } label: {
                Label {
                    Text(store.isPhoneOTPAvailable
                         ? store.language.text("使用手機號碼", "휴대폰 번호로 계속", "Continue with phone")
                         : store.language.text("手機登入・即將開放", "휴대폰 로그인 · 곳 제공", "Phone sign-in · Coming soon"))
                } icon: {
                    Image(systemName: "iphone")
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 54)
            }
            .celestialGlassButtonStyle(prominent: true)
            .tint(Color.celestialPlum)
            .disabled(!signInEnabled || !store.isPhoneOTPAvailable)
            .opacity(store.isPhoneOTPAvailable ? 1 : 0.72)
            .accessibilityHint(store.isPhoneOTPAvailable
                               ? agreementHint
                               : store.language.text(
                                   "手機登入還在準備中。",
                                   "휴대폰 로그인은 아직 준비 중입니다.",
                                   "Phone sign-in isn't available yet."
                               ))

            Button {} label: {
                HStack(spacing: 10) {
                    WeChatOfficialMark()
                        .frame(width: 30, height: 25)
                        .accessibilityHidden(true)
                    Text(store.language.text("微信登入・即將開放", "WeChat 로그인 · 곧 제공", "WeChat · Coming soon"))
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 54)
            }
            .celestialGlassButtonStyle(prominent: true)
            .tint(Color(red: 0.10, green: 0.67, blue: 0.30))
            .disabled(true)
            .opacity(0.72)
            .accessibilityHint(store.language.text(
                "微信登入目前暫停開放。",
                "WeChat 로그인은 현재 준비 중입니다.",
                "WeChat sign-in is temporarily unavailable."
            ))
        }
    }

    @ViewBuilder
    private var phoneSignIn: some View {
        if let challenge = store.phoneOTPChallenge {
            phoneCodeForm(challenge: challenge)
        } else {
            VStack(alignment: .leading, spacing: 13) {
                Text(store.language.text("地區", "지역", "Region"))
                    .font(.subheadline.weight(.semibold))

                Menu {
                    ForEach(PhoneRegion.all) { region in
                        Button {
                            selectedPhoneRegion = region
                            phoneNumber = ""
                            requestFocus(.phone)
                        } label: {
                            if selectedPhoneRegion == region {
                                Label(region.menuTitle(in: store.language), systemImage: "checkmark")
                            } else {
                                Text(region.menuTitle(in: store.language))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 11) {
                        Text(selectedPhoneRegion.flag)
                            .font(.title3)
                        Text(selectedPhoneRegion.name(in: store.language))
                            .font(.body.weight(.semibold))
                        Spacer(minLength: 8)
                        Text(selectedPhoneRegion.callingCode)
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.70))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.bold())
                            .foregroundStyle(.white.opacity(0.52))
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .celestialSurface(
                        Color.white.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 14),
                        reducedColor: .celestialSurfaceElevated
                    )
                    .overlay { RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.16)) }
                }

                Text(store.language.text("手機號碼", "휴대폰 번호", "Phone number"))
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 11) {
                    Text(selectedPhoneRegion.callingCode)
                        .font(.body.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    Rectangle()
                        .fill(.white.opacity(0.16))
                        .frame(width: 1, height: 26)
                    TextField(selectedPhoneRegion.example, text: $phoneNumber)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .focused($focusedField, equals: .phone)
                        .submitLabel(.next)
                        .onSubmit { requestPhoneCode() }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .celestialSurface(
                    Color.white.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 14),
                    reducedColor: .celestialSurfaceElevated
                )
                .overlay { RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.16)) }

                Text(store.language.text(
                    "選好地區後，只要填本地手機號碼。開頭的 0 會在送出時自動處理。",
                    "지역을 고른 뒤 현지 휴대폰 번호만 입력하세요. 앞의 0은 전송할 때 자동으로 처리됩니다.",
                    "Choose your region, then enter the local mobile number. A leading zero is handled automatically."
                ))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))

                Button {
                    requestPhoneCode()
                } label: {
                    HStack {
                        if store.isRequestingPhoneOTP { ProgressView().tint(.white) }
                        Text(store.language.text("取得驗證碼", "인증 코드 받기", "Send verification code"))
                            .frame(maxWidth: .infinity)
                    }
                    .font(.headline)
                    .frame(minHeight: 52)
                }
                .celestialGlassButtonStyle(prominent: true)
                .tint(Color.celestialPlum)
                .disabled(!agreed || !isPhoneNumberValid || store.isRequestingPhoneOTP)
            }
        }

        if let error = store.phoneOTPError {
            Label(error, systemImage: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Color(red: 1, green: 0.72, blue: 0.76))
        }

        #if DEBUG
        Label {
            Text(store.language.text(
                "測試模式驗證碼：123456",
                "테스트 모드 인증 코드: 123456",
                "Test-mode verification code: 123456"
            ))
        } icon: {
            Image(systemName: "hammer.fill")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color.celestialGold)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .celestialSurface(
            Color.celestialGold.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 12),
            reducedColor: .celestialSurfaceElevated,
            reducedBoundaryColor: Color.celestialGold.opacity(0.72)
        )
        #endif
    }

    private func phoneCodeForm(challenge: PhoneOTPChallenge) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(store.language.text(
                "已發送至 \(challenge.maskedDestination)",
                "\(challenge.maskedDestination)(으)로 보냈어요",
                "Sent to \(challenge.maskedDestination)"
            ))
            .font(.subheadline.weight(.semibold))

            // Keep the responder outside the one-second TimelineView below.
            // Rebuilding the TextField every tick made iOS drop first responder,
            // so the OTP keyboard disappeared immediately after it opened.
            TextField("123456", text: $verificationCode)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .code)
                .multilineTextAlignment(.center)
                .font(.title2.monospacedDigit().weight(.semibold))
                .tracking(6)
                .padding(.horizontal, 16)
                .frame(minHeight: 54)
                .celestialSurface(
                    Color.white.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 14),
                    reducedColor: .celestialSurfaceElevated
                )
                .overlay { RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.16)) }
                .onAppear { requestFocus(.code) }
                .onChange(of: verificationCode) { _, value in
                    verificationCode = String(value.filter(\.isNumber).prefix(6))
                }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let expirySeconds = challenge.secondsUntilExpiry(at: context.date)
                let resendSeconds = challenge.secondsUntilResend(at: context.date)
                let canVerify = verificationCode.count == 6
                    && expirySeconds > 0
                    && challenge.remainingAttempts > 0

                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Label(expiryText(seconds: expirySeconds), systemImage: "clock.fill")
                        Spacer()
                        Text(store.language.text(
                            "剩 \(challenge.remainingAttempts) 次",
                            "\(challenge.remainingAttempts)회 남음",
                            "\(challenge.remainingAttempts) attempts left"
                        ))
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.64))

                    Button {
                        Task { await store.verifyPhoneOTP(code: verificationCode) }
                    } label: {
                        HStack {
                            if store.isVerifyingPhoneOTP { ProgressView().tint(.white) }
                            Text(store.language.text("驗證並登入", "확인하고 로그인", "Verify and sign in"))
                                .frame(maxWidth: .infinity)
                        }
                        .font(.headline)
                        .frame(minHeight: 52)
                    }
                    .celestialGlassButtonStyle(prominent: true)
                    .tint(Color.celestialPlum)
                    .disabled(!canVerify || store.isVerifyingPhoneOTP)

                    HStack(spacing: 16) {
                        Button {
                            requestPhoneCode()
                        } label: {
                            Text(resendSeconds > 0
                                 ? store.language.text("\(resendSeconds) 秒後重發", "\(resendSeconds)초 후 재전송", "Resend in \(resendSeconds)s")
                                 : store.language.text("重新發送", "다시 보내기", "Resend code"))
                        }
                        .disabled(resendSeconds > 0 || store.isRequestingPhoneOTP)
                        Spacer()
                        Button(store.language.text("修改手機號碼", "번호 변경", "Change number")) {
                            store.resetPhoneOTP()
                            verificationCode = ""
                            requestFocus(.phone)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private var agreementControl: some View {
        Button { agreed.toggle() } label: {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: agreed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(agreed ? Color.celestialGold : .white.opacity(0.68))
                    .accessibilityHidden(true)
                Text(store.language.text(
                    "我已閱讀下方兩份文件，並同意繼續。",
                    "아래 두 문서를 읽고 계속하는 데 동의합니다.",
                    "I've reviewed both documents below and agree to continue."
                ))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.language.text(
            "同意使用者協議與隱私權政策",
            "이용약관과 개인정보 처리방침에 동의",
            "Agree to the Terms of Use and Privacy Policy"
        ))
        .accessibilityValue(agreed
                            ? store.language.text("已同意", "동의함", "Agreed")
                            : store.language.text("未同意", "동의하지 않음", "Not agreed"))
        .accessibilityAddTraits(agreed ? .isSelected : [])
    }

    private var legalLinks: some View {
        HStack(spacing: 12) {
            Button {
                legalDocument = .terms
            } label: {
                Label(AuthLegalDocument.terms.title(in: store.language), systemImage: "doc.text")
                    .frame(maxWidth: .infinity)
            }
            .celestialGlassButtonStyle()

            Button {
                legalDocument = .privacy
            } label: {
                Label(AuthLegalDocument.privacy.title(in: store.language), systemImage: "lock.shield")
                    .frame(maxWidth: .infinity)
            }
            .celestialGlassButtonStyle()
        }
        .font(.caption.weight(.semibold))
    }

    private var privacyNote: some View {
        Label {
            Text(store.language.text(
                "正式帳號登入後，帳號識別資料與運勢、抽牌、出生資料、星星造型及進度會保存在星伴帳號服務，讓你換機後跟著帳號取回。本機預覽不會上傳。星伴不出售資料，也不用於跨 App 或網站追蹤；只有你主動分享時，所選內容才會交給 iOS 分享服務。",
                "정식 계정으로 로그인하면 계정 식별 정보와 운세, 카드 기록, 출생 정보, 별 외형과 진행 정보가 별동무 계정 서비스에 보관되어 다른 기기에서도 같은 계정으로 받을 수 있어요. 기기 미리보기는 업로드하지 않아요. 별동무는 데이터를 판매하거나 다른 앱·웹사이트에서 추적하는 데 쓰지 않으며, 직접 공유할 때만 선택한 내용이 iOS 공유 서비스로 전달돼요.",
                "After a verified sign-in, the account identifier, fortunes, readings, birth details, star looks, and progress are stored in the Star Companion account service so they follow the account to another device. Local previews don't upload them. Star Companion doesn't sell this data or use it to track you across apps or websites. Content reaches iOS sharing services only when you choose to share it."
            ))
        } icon: {
            Image(systemName: "hand.raised.fill")
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.64))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var environmentNote: some View {
        Group {
            #if DEBUG
            Text(store.language.text(
                "本機預覽：Apple 與手機登入只建立未經伺服器驗證的測試帳號；微信暫停開放。",
                "기기 미리보기: Apple과 휴대폰 로그인은 서버 검증을 거치지 않은 테스트 계정만 만들며, WeChat은 현재 준비 중입니다.",
                "Local preview: Apple and phone sign-in create test accounts that aren't server-verified; WeChat is currently unavailable."
            ))
            #else
            Text(store.language.text(
                "目前正式帳號先用 Apple 登入；手機與微信還在準備中。",
                "현재 정식 계정은 Apple로 먼저 로그인할 수 있고, 휴대폰과 WeChat은 준비 중입니다.",
                "Verified accounts currently use Apple sign-in. Phone and WeChat sign-in are still in preparation."
            ))
            #endif
        }
        .font(.caption2)
        .multilineTextAlignment(.center)
        .foregroundStyle(Color.celestialGold.opacity(0.78))
        .frame(maxWidth: .infinity)
    }

    private var languageMenu: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    store.setLanguage(language)
                } label: {
                    if store.language == language {
                        Label(language.displayName, systemImage: "checkmark")
                    } else {
                        Text(language.displayName)
                    }
                }
            }
        } label: {
            Label(store.language.displayName, systemImage: "globe")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 11)
                .frame(minHeight: 38)
        }
        .celestialGlassButtonStyle()
    }

    private var signInEnabled: Bool { agreed && !store.isLoggingIn }

    private var agreementHint: String {
        agreed ? "" : store.language.text(
            "請先閱讀並同意使用者協議與隱私權政策。",
            "먼저 이용약관과 개인정보 처리방침에 동의해 주세요.",
            "Read and agree to the Terms of Use and Privacy Policy first."
        )
    }

    private var e164PhoneNumber: String {
        selectedPhoneRegion.e164Number(from: phoneNumber)
    }

    private var isPhoneNumberValid: Bool {
        E164PhoneNumber(e164PhoneNumber) != nil
    }

    private func requestPhoneCode() {
        guard agreed, isPhoneNumberValid else { return }
        focusedField = nil
        Task { await store.requestPhoneOTP(phoneNumber: e164PhoneNumber) }
    }

    private func requestFocus(_ field: LoginField) {
        Task { @MainActor in
            focusedField = nil
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(140))
            focusedField = field
        }
    }

    private func expiryText(seconds: Int) -> String {
        guard seconds > 0 else {
            return store.language.text("驗證碼已過期", "인증 코드 만료", "Code expired")
        }
        let clock = String(format: "%d:%02d", seconds / 60, seconds % 60)
        return store.language.text("\(clock) 後過期", "\(clock) 후 만료", "Expires in \(clock)")
    }
}

private struct PhoneRegion: Identifiable, Hashable {
    let id: String
    let callingCode: String
    let traditionalChineseName: String
    let koreanName: String
    let englishName: String
    let example: String

    static let all: [PhoneRegion] = [
        PhoneRegion(id: "TW", callingCode: "+886", traditionalChineseName: "台灣", koreanName: "대만", englishName: "Taiwan", example: "912 345 678"),
        PhoneRegion(id: "CN", callingCode: "+86", traditionalChineseName: "中國大陸", koreanName: "중국 본토", englishName: "Mainland China", example: "138 0013 8000"),
        PhoneRegion(id: "HK", callingCode: "+852", traditionalChineseName: "香港", koreanName: "홍콩", englishName: "Hong Kong", example: "5123 4567"),
        PhoneRegion(id: "MO", callingCode: "+853", traditionalChineseName: "澳門", koreanName: "마카오", englishName: "Macao", example: "6612 3456"),
        PhoneRegion(id: "KR", callingCode: "+82", traditionalChineseName: "韓國", koreanName: "대한민국", englishName: "South Korea", example: "010 1234 5678"),
        PhoneRegion(id: "JP", callingCode: "+81", traditionalChineseName: "日本", koreanName: "일본", englishName: "Japan", example: "090 1234 5678"),
        PhoneRegion(id: "SG", callingCode: "+65", traditionalChineseName: "新加坡", koreanName: "싱가포르", englishName: "Singapore", example: "8123 4567"),
        PhoneRegion(id: "MY", callingCode: "+60", traditionalChineseName: "馬來西亞", koreanName: "말레이시아", englishName: "Malaysia", example: "012 345 6789"),
        PhoneRegion(id: "US", callingCode: "+1", traditionalChineseName: "美國／加拿大", koreanName: "미국/캐나다", englishName: "United States / Canada", example: "415 555 0123"),
        PhoneRegion(id: "AU", callingCode: "+61", traditionalChineseName: "澳洲", koreanName: "호주", englishName: "Australia", example: "0412 345 678"),
        PhoneRegion(id: "GB", callingCode: "+44", traditionalChineseName: "英國", koreanName: "영국", englishName: "United Kingdom", example: "07123 456789"),
    ]

    static var suggested: PhoneRegion {
        let currentRegion = Locale.current.region?.identifier.uppercased()
        return all.first(where: { $0.id == currentRegion }) ?? all[0]
    }

    var flag: String {
        id.unicodeScalars.compactMap { scalar in
            UnicodeScalar(127397 + scalar.value).map(String.init)
        }.joined()
    }

    func name(in language: AppLanguage) -> String {
        language.text(traditionalChineseName, koreanName, englishName)
    }

    func menuTitle(in language: AppLanguage) -> String {
        "\(flag) \(name(in: language))  \(callingCode)"
    }

    func e164Number(from localNumber: String) -> String {
        let digits = localNumber.unicodeScalars
            .filter { (48...57).contains($0.value) }
            .map(String.init)
            .joined()
        let nationalNumber = digits.drop(while: { $0 == "0" })
        return callingCode + String(nationalNumber)
    }
}

/// The WeChat brand mark drawn as two overlapping message bubbles. Keeping it
/// vector-based makes the official sign-in mark crisp at every Dynamic Type
/// and display scale without shipping a tinted screenshot asset.
private struct WeChatOfficialMark: View {
    var body: some View {
        Canvas { context, size in
            let scaleX = size.width / 30
            let scaleY = size.height / 25

            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * scaleX, y: y * scaleY)
            }

            var back = Path()
            back.addRoundedRect(
                in: CGRect(x: 0, y: 1 * scaleY, width: 20 * scaleX, height: 15 * scaleY),
                cornerSize: CGSize(width: 7 * scaleX, height: 7 * scaleY)
            )
            back.move(to: point(5.5, 14))
            back.addLine(to: point(3.5, 20))
            back.addLine(to: point(10, 15))
            back.closeSubpath()
            context.fill(back, with: .color(.white))

            var front = Path()
            front.addRoundedRect(
                in: CGRect(x: 10 * scaleX, y: 8 * scaleY, width: 20 * scaleX, height: 15 * scaleY),
                cornerSize: CGSize(width: 7 * scaleX, height: 7 * scaleY)
            )
            front.move(to: point(24, 21))
            front.addLine(to: point(27, 25))
            front.addLine(to: point(20.5, 22))
            front.closeSubpath()
            context.fill(front, with: .color(.white))

            let green = Color(red: 0.10, green: 0.67, blue: 0.30)
            for center in [point(6.5, 8), point(12.5, 8), point(17, 15), point(23, 15)] {
                let radius = min(scaleX, scaleY) * 1.05
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(green)
                )
            }
        }
        .accessibilityHidden(true)
    }
}
