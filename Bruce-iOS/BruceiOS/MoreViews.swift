import SwiftUI

let appDisplayName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? "Brüce"

// MARK: - Welcome (logged out)

struct WelcomeView: View {
    @Environment(AppModel.self) var m
    @State private var animate = false

    var body: some View {
        VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 14) {
                    Text(appDisplayName.uppercased()).font(.system(size: 54, weight: .black).width(.expanded))
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Text(Copy.tagline).font(.system(size: 14, weight: .heavy).width(.expanded)).kerning(1)
                }
                .foregroundStyle(.white)
                Spacer()
                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        LimeButton(title: "Log in") { m.present(.login) }
                        // Sneak peek: browse the public studio list (GET /v1/studios) without an account.
                        Button { Task { await m.startSneakPeek() } } label: {
                            Text("Sneak peek").font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 36)
                        }
                        .buttonStyle(.glass).controlSize(.large)
                        // No signup endpoint is known: sign up on the website.
                        Link("Create account", destination: URL(string: "https://www.brucestudios.com")!)
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.8)).padding(.top, 6)
                    }
                }
                .padding(.horizontal, Theme.gutter).padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { background.ignoresSafeArea() }
        .environment(\.colorScheme, .dark)
        .onAppear { withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) { animate = true } }
    }

    var background: some View {
        Color(red: 0.08, green: 0.09, blue: 0.07).overlay {
            Circle().fill(Theme.lime.opacity(0.55)).frame(width: 420).blur(radius: 90)
                .offset(x: animate ? 120 : -80, y: animate ? -260 : -180)
            Circle().fill(Theme.teal.opacity(0.45)).frame(width: 360).blur(radius: 100)
                .offset(x: animate ? -110 : 90, y: animate ? 260 : 160)
            Image(systemName: "dumbbell.fill").font(.system(size: 280, weight: .black)).foregroundStyle(.white.opacity(0.04))
                .rotationEffect(.degrees(-24)).offset(x: 60, y: -40)
        }
        .clipped()
    }
}

// MARK: - Forms

func isValidEmailInput(_ s: String) -> Bool { isValidEmail(s.trimmingCharacters(in: .whitespaces)) }

/// Log in: POST /v52/access/authenticate. The session goes to the Keychain; the password is never stored.
struct LoginView: View {
    @Environment(AppModel.self) var m
    @State private var email = ""
    @State private var password = ""
    @State private var submitted = false
    @FocusState private var focus: Int?

    var body: some View {
        Form {
            Section {
                TextField("name@email.com", text: $email)
                    .textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focus, equals: 0).submitLabel(.next).onSubmit { focus = 1 }
                SecureField("Password", text: $password)
                    .textContentType(.password).focused($focus, equals: 1).submitLabel(.go).onSubmit(submit)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if submitted && !isValidEmailInput(email) { Text("Enter a valid email").foregroundStyle(Theme.red) }
                    if submitted && password.isEmpty { Text("Enter your password").foregroundStyle(Theme.red) }
                    if m.status.hasPrefix("Login failed") { Text(m.status).foregroundStyle(Theme.red) }
                    Text("Signs in to your Bruce Studios account. Only the session token is stored (in the Keychain).")
                }
            }
            Section {
                LimeButton(title: m.loading ? "Logging in…" : "Log in", action: submit).disabled(m.loading)
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            Section {
                Link("Forgot password? Reset it on brucestudios.com", destination: URL(string: "https://www.brucestudios.com")!)
            }
        }
        .sheetChrome("Log in")
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focus = 0 } }
    }

    func submit() {
        submitted = true
        guard isValidEmailInput(email), !password.isEmpty else { return }
        Task { await m.login(email: email.trimmingCharacters(in: .whitespaces), password: password) }
    }
}

/// Display-only: no signup endpoint is ever called.
struct CreateAccountView: View {
    @Environment(AppModel.self) var m
    @State private var first = ""
    @State private var last = ""
    @State private var email = ""
    @State private var password = ""
    @State private var tos = false
    @State private var marketing = false

    var body: some View {
        Form {
            Section {
                TextField("First name", text: $first)
                TextField("Last name", text: $last)
                TextField("Email", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                SecureField("Password (at least 8 characters)", text: $password)
            }
            Section {
                Toggle("I accept Bruce Studios' terms and privacy policy", isOn: $tos)
                Toggle("Email offers from Bruce Studios", isOn: $marketing)
            }
            Section {
                LimeButton(title: "Create account") { m.flash("Creating an account is not available here. Use the official app.") }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            } footer: { Text("Account creation is display-only in this unofficial client.") }
        }
        .tint(Theme.lime)
        .sheetChrome("Create account")
    }
}

/// Display-only: no reset request is sent.
struct ResetPasswordView: View {
    @Environment(AppModel.self) var m
    @State private var email = ""
    var body: some View {
        Form {
            Section {
                TextField("name@email.com", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
            } footer: {
                Text(Copy.resetPassword)
            }
            Section {
                LimeButton(title: "Reset password") { m.flash("Password reset is not available here") }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
        }
        .sheetChrome("Reset password")
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(AppModel.self) var m
    var body: some View {
        Form {
            Section {
                NavigationLink(value: SheetRoute.selectCity) { InfoRow(title: "Change city", subtitle: m.cityName, chevron: false) }
                Toggle(isOn: Binding(get: { m.social ?? true }, set: { m.setSocial($0) })) {
                    InfoRow(title: "Social", subtitle: (m.social ?? true) ? "Everyone can see your profile" : "Only friends can see your profile", chevron: false)
                }
                LocationSettingsRow()
                Button { copyCalendarURL() } label: { InfoRow(title: "Calendar subscription", subtitle: "Subscribe to your bookings in Calendar") }
                NavigationLink(value: SheetRoute.push) {
                    InfoRow(title: "Push notifications", subtitle: "Reminders and studio news", chevron: false)
                }
            }
            Section {
                NavigationLink(value: SheetRoute.info("Terms and conditions")) { Text("Terms and conditions") }
                NavigationLink(value: SheetRoute.info("Privacy policy")) { Text("Privacy policy") }
                NavigationLink(value: SheetRoute.info("Open source licenses")) { Text("Open source licenses") }
                Button("Clear cached images") { URLCache.shared.removeAllCachedResponses(); m.flash("Image cache cleared") }
            }
            Section {
                Toggle("Push", isOn: marketing("marketing_push", \.marketingPush))
                Toggle("Email", isOn: marketing("marketing_email", \.marketingEmail))
                Toggle("SMS", isOn: marketing("marketing_sms", \.marketingSms))
            } header: { Text("Marketing") } footer: { Text(Copy.marketing) }
            Section {
                VStack(spacing: 4) {
                    Text("\(appDisplayName) \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                    Text("Unofficial client. Not affiliated with Bruce Studios.")
                }
                .font(.system(size: 13)).foregroundStyle(Theme.secondary).frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
        }
        .sheetChrome("Settings")
        .task { await m.loadSettings() }
    }

    func marketing(_ field: String, _ kp: KeyPath<BruceAPI.NotificationSetting, Bool?>) -> Binding<Bool> {
        Binding(get: { m.notificationSetting?[keyPath: kp] ?? true }, set: { m.setMarketing(field, $0) })
    }

    /// The calendar feed URL contains the user's secret; it is only copied, never shown or logged.
    func copyCalendarURL() {
        guard let uid = m.userId, let secret = m.user?.secret, !secret.isEmpty else { m.flash("Calendar link not available"); return }
        UIPasteboard.general.string = "webcal://api.bruce.app/v52/user/\(uid)/calendar/\(secret).ics"
        m.flash("Calendar link copied. Add it in Settings › Calendar › Accounts › Add Subscribed Calendar")
    }
}

struct PushSettingsView: View {
    @Environment(AppModel.self) var m
    var body: some View {
        Form {
            row("Booking reminders", "booking_reminder")
            row("Check in", "check_in_reminder")
            row("New studios", "new_studio")
        }
        .sheetChrome("Push notifications")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: SheetRoute.pushInfo) { Image(systemName: "info.circle") }
            }
        }
        .task { if m.notificationSetting == nil { await m.loadSettings() } }
    }
    /// Subtitle from the API's notification type description, else our own fallback.
    func row(_ t: String, _ k: String) -> some View {
        let type = m.notificationSetting?.types?.first { $0.key == k }
        return Toggle(isOn: Binding(get: { type?.enabled ?? true }, set: { m.setPushType(k, $0) })) {
            InfoRow(title: t, subtitle: type?.description ?? Copy.pushSubtitle(k), chevron: false)
        }
    }
}

struct TextInfoSheet: View {
    let title: String
    let paragraphs: [String]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(title.uppercased()).font(Theme.heading(26)).padding(.bottom, 8)
                ForEach(paragraphs, id: \.self) { Text($0).font(.system(size: 16)).lineSpacing(5) }
            }
            .padding(Theme.gutter)
        }
        .sheetChrome("")
    }
}

// MARK: - Invite friends to a class

/// Class page "Invite": pick friends and send them this class (POST /v52/class/<id>/invite).
struct ClassInviteSheet: View {
    @Environment(AppModel.self) var m
    let classId: Int
    @State private var picked: Set<Int> = []
    var c: BruceAPI.BruceClass? { m.classDetails[classId] ?? m.findClass(classId) }
    var friends: [BruceAPI.UserLite] {
        m.friends.compactMap(\.friendUser).sorted { ($0.firstName ?? "") < ($1.firstName ?? "") }
    }

    var body: some View {
        List {
            Section("Friends") {
                if friends.isEmpty {
                    Text(m.isLoggedIn ? "Add friends in Bruce to invite them to classes." : "Log in to invite friends.")
                        .foregroundStyle(Theme.secondary)
                }
                ForEach(friends, id: \.id) { u in
                    Button {
                        if picked.contains(u.id) { picked.remove(u.id) } else { picked.insert(u.id) }
                    } label: {
                        HStack(spacing: 14) {
                            Avatar(fileId: u.photo, initials: u.initials, size: 44)
                            Text(u.firstName ?? u.fullName).font(.system(size: 17, weight: .medium))
                            Spacer()
                            Image(systemName: picked.contains(u.id) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 24)).foregroundStyle(picked.contains(u.id) ? Theme.limeInk : Theme.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            LimeButton(title: m.loading ? "Inviting…" : "Invite friends") {
                Task { if await m.inviteToClass(classId, userIds: Array(picked)) { m.dismissSheets() } }
            }
            .disabled(picked.isEmpty || m.loading)
            .padding(.horizontal, Theme.gutter).padding(.vertical, 8)
        }
        .sheetChrome(c?.title ?? "Invite friends")
        .task { if m.friends.isEmpty { await m.loadSocial() } }
        .toolbar {
            if let c {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: ShareURL.forClass(classId, title: c.title),
                              message: Text(Copy.classInvite(c, studio: m.studioName(c.studioId)))) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

// MARK: - Invite friends

struct InviteSheet: View {
    @Environment(AppModel.self) var m
    var open: [BruceAPI.Voucher] { m.invites.filter { !$0.accepted } }
    var accepted: [BruceAPI.Voucher] { m.invites.filter { $0.accepted } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("INVITE A FRIEND").font(Theme.screenTitle(30))
                Text(Copy.inviteIntro(open: m.openInvites))
                    .font(.system(size: 15)).foregroundStyle(Theme.secondary)
                Text("INVITES").font(Theme.heading(16)).padding(.top, 10)
                if open.isEmpty {
                    Text(m.isLoggedIn ? "No invite codes left." : "Log in to see your invite codes.").foregroundStyle(Theme.secondary)
                }
                GlassEffectContainer(spacing: 10) {
                    VStack(spacing: 10) {
                        ForEach(open) { v in
                            HStack(spacing: 14) {
                                Image(systemName: "gift.fill").foregroundStyle(Theme.limeInk)
                                Text(v.code.uppercased()).font(.system(size: 18, weight: .bold, design: .monospaced))
                                Spacer()
                                ShareLink(item: Copy.shareInvite(v.code)) {
                                    Label("Share", systemImage: "square.and.arrow.up").font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                                }
                                .buttonStyle(.glassProminent).tint(Theme.lime)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .glassEffect(.regular, in: .rect(cornerRadius: 22))
                        }
                    }
                }
                if !accepted.isEmpty {
                    Text("ACCEPTED").font(Theme.heading(16)).padding(.top, 10)
                    ForEach(accepted) { v in
                        HStack(spacing: 14) {
                            Avatar(fileId: nil, initials: "?", size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.friends.first { $0.friendUser?.id == v.userId }?.friendUser?.firstName ?? "Invited friend").font(.system(size: 16, weight: .semibold))
                                Text(v.code.uppercased()).font(.system(size: 14, design: .monospaced)).foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            Text("Pending").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }
            .padding(Theme.gutter)
        }
        .sheetChrome("Invite friends")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { NavigationLink(value: SheetRoute.howItWorks) { Image(systemName: "info.circle") } }
        }
        .task { await m.loadAccount() }
    }
}

// MARK: - Voucher (display-only)

struct VoucherSheet: View {
    @Environment(AppModel.self) var m
    @State private var code = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("REDEEM VOUCHER").font(Theme.screenTitle(28)).padding(.top, 20)
            TextField("XXXXXX", text: $code)
                .font(.system(size: 22, weight: .bold, design: .monospaced)).textInputAutocapitalization(.characters)
                .padding(.horizontal, 18).frame(height: 58)
                .glassEffect(.regular.interactive(), in: .capsule)
                .focused($focused)
            LimeButton(title: "Activate") { m.flash("Redeeming vouchers is not available here") }
            Spacer()
        }
        .padding(Theme.gutter)
        .sheetChrome("")
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = true } }
    }
}

// MARK: - Support & help

/// Support chat and FAQ run on Bruce Studios' own help desk inside the official app; this client links to
/// their website (the only confirmed public URL) instead of imitating the chat.
struct SupportSheet: View {
    @Environment(AppModel.self) var m
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hi \(m.user?.firstName ?? "there") 👋").font(.system(size: 26, weight: .bold))
                    Text("Support chat and the FAQ are run by Bruce Studios. Contact them through their website or the official app.")
                        .font(.system(size: 15)).foregroundStyle(Theme.secondary)
                }
                .padding(.vertical, 6)
            }
            Section {
                Link(destination: URL(string: "https://www.brucestudios.com")!) {
                    Label("brucestudios.com", systemImage: "safari")
                }
            }
        }
        .sheetChrome("Support")
    }
}

typealias HelpSheet = SupportSheet

/// Real location permission state (no local fake toggle).
struct LocationSettingsRow: View {
    @EnvironmentObject var loc: LocationProvider
    var body: some View {
        Button { loc.authorized || loc.denied ? loc.openSettings() : loc.request() } label: {
            InfoRow(title: "Location", subtitle: loc.authorized ? "On – distances and nearby gyms use your location"
                    : loc.denied ? "Off – tap to allow in Settings" : "Not set – tap to use your location for nearby gyms")
        }
    }
}
