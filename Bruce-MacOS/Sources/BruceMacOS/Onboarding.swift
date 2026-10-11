import SwiftUI

extension Theme {
    static let welcomeDark = Color(red: 0x28 / 255, green: 0x28 / 255, blue: 0x28 / 255)
    static let fieldBorder = Color(white: 0.84)
    static let errorRed = Color(red: 1.0, green: 0.15, blue: 0.15)
}

// MARK: - Welcome (logged out)

struct WelcomeView: View {
    @Environment(AppModel.self) var m
    var body: some View {
        ZStack {
            Theme.welcomeDark.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button { Task { await m.startSneakPeek() } } label: {
                        Text("Sneak peek").underline().font(.system(size: 17, weight: .semibold))
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 14)
                Spacer()
                Wordmark()
                Text(Copy.tagline).font(.system(size: 15, weight: .heavy).width(.expanded))
                    .padding(.top, 24)
                Spacer()
                LimeButton(title: "Create account") { m.present(.createAccount) }
                    .padding(.horizontal, Theme.gutter)
                HStack(spacing: 5) {
                    Text("Already a member?")
                    Button { m.present(.login) } label: { Text("Log in").underline() }.buttonStyle(.plain)
                }
                .font(.system(size: 17, weight: .semibold))
                .padding(.top, 26).padding(.bottom, 34)
            }
            .foregroundStyle(.white)
        }
    }
}

/// "BRUCE / STUDIOS" wordmark drawn with system fonts.
struct Wordmark: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("BRUCE").font(.system(size: 31, weight: .heavy).width(.expanded)).kerning(3)
            Rectangle().frame(width: 1.6, height: 46).rotationEffect(.degrees(18))
            Text("STUDIOS").font(.system(size: 30, weight: .light).width(.expanded)).kerning(2)
        }
    }
}

// MARK: - Form building blocks

struct FormField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var secure = false
    var error: String?
    var focused: FocusState<Bool>.Binding? = nil
    @State private var reveal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.secondary)
            HStack {
                Group {
                    if secure && !reveal {
                        SecureField("", text: $text, prompt: Text(placeholder).foregroundColor(Color(white: 0.72)))
                    } else {
                        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Color(white: 0.72)))
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .light))
                .modifier(OptionalFocus(binding: focused))
                if secure {
                    Button { reveal.toggle() } label: {
                        Image(systemName: reveal ? "eye" : "eye.slash").font(.system(size: 19))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18).frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(error != nil ? Theme.errorRed : Theme.fieldBorder, lineWidth: 1))
            if let error { Text(error).font(.system(size: 14, weight: .light)).foregroundStyle(Theme.errorRed) }
        }
    }
}

struct OptionalFocus: ViewModifier {
    var binding: FocusState<Bool>.Binding?
    func body(content: Content) -> some View {
        if let binding { content.focused(binding) } else { content }
    }
}

struct SocialButtons: View {
    @Environment(AppModel.self) var m
    let caption: String
    var body: some View {
        VStack(spacing: 18) {
            Text(caption).font(.system(size: 17, weight: .light))
            HStack(spacing: 28) {
                Button { m.flash("Sign in with Apple is not available here") } label: {
                    RoundedRectangle(cornerRadius: 8).fill(Color.black).frame(width: 64, height: 64)
                        .overlay(Image(systemName: "apple.logo").font(.system(size: 26)).foregroundStyle(.white))
                }.buttonStyle(.plain)
                Button { m.flash("Sign in with Google is not available here") } label: {
                    RoundedRectangle(cornerRadius: 8).fill(Color.white).frame(width: 64, height: 64)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.fieldBorder))
                        .overlay(Text("G").font(.system(size: 28, weight: .bold))
                            .foregroundStyle(AngularGradient(colors: [.red, .yellow, .green, .blue, .red], center: .center)))
                }.buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct CheckRow<Content: View>: View {
    @Binding var on: Bool
    @ViewBuilder var content: Content
    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            Button { on.toggle() } label: {
                Rectangle().stroke(Theme.ink, lineWidth: 1.5).frame(width: 28, height: 28)
                    .overlay(Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).opacity(on ? 1 : 0))
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
            content.font(.system(size: 17, weight: .light)).lineSpacing(6)
        }
    }
}


// MARK: - Log in (wired to POST /v52/access/authenticate)

struct LoginView: View {
    @Environment(AppModel.self) var m
    @State private var email = ""
    @State private var password = ""
    @State private var submitted = false
    @FocusState private var emailFocused: Bool
    @FocusState private var passwordFocused: Bool

    var emailError: String? { submitted && !isValidEmail(email) ? "Enter a valid email" : nil }
    var passwordError: String? { submitted && password.isEmpty ? "Enter your password" : nil }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "Log in", leading: .close) { m.dismissSheets() }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    FormField(label: "Email", placeholder: "name@email.com", text: $email, error: emailError, focused: $emailFocused)
                        .onSubmit { passwordFocused = true }
                    FormField(label: "Password", placeholder: "password", text: $password, secure: true, error: passwordError, focused: $passwordFocused)
                        .onSubmit(submit)
                    HStack(spacing: 5) {
                        Text("Forgot password?")
                        Button { m.pushSheet(.resetPassword) } label: { Text("Reset").underline() }.buttonStyle(.plain)
                    }
                    .font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity).padding(.top, 14)
                    LimeButton(title: m.loading ? "Logging in…" : "Log in", action: submit)
                        .disabled(m.loading).padding(.top, 54)
                    if !m.status.isEmpty && m.status.hasPrefix("Login failed") {
                        Text(m.status).font(.system(size: 13)).foregroundStyle(Theme.errorRed)
                    }
                    SocialButtons(caption: "Or continue with:").padding(.top, 6)
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 18).padding(.bottom, 30)
            }
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { emailFocused = true } }
    }

    func submit() {
        submitted = true
        guard isValidEmail(email), !password.isEmpty else { return }
        Task { await m.login(email: email, password: password) }
    }
}

// MARK: - Create account (display-only; no signup endpoint is ever called)

struct CreateAccountView: View {
    @Environment(AppModel.self) var m
    @State private var first = ""
    @State private var last = ""
    @State private var email = ""
    @State private var password = ""
    @State private var tos = false
    @State private var marketing = false

    var complete: Bool { !first.isEmpty && !last.isEmpty && isValidEmail(email) && password.count >= 8 && tos }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "Create account", leading: .close) { m.dismissSheets() }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    FormField(label: "First name", placeholder: "first name", text: $first)
                    FormField(label: "Last name", placeholder: "last name", text: $last)
                    FormField(label: "Email", placeholder: "name@email.com", text: $email)
                    FormField(label: "Password", placeholder: "at least 8 characters", text: $password, secure: true)
                    CheckRow(on: $tos) {
                        Text("I accept Bruce Studios' ") + Text("terms").fontWeight(.bold).underline()
                            + Text(" and ") + Text("privacy policy").fontWeight(.bold).underline()
                    }
                    .padding(.top, 24)
                    CheckRow(on: $marketing) {
                        Text("Email me offers from Bruce Studios. ") + Text("More info").fontWeight(.bold).underline()
                    }
                    Button { m.flash("Creating an account is not available here") } label: {
                        Text("Create account").font(.system(size: 17, weight: .bold))
                            .foregroundStyle(complete ? Color.black : Theme.ink)
                            .frame(maxWidth: .infinity).frame(height: 54)
                            .background(Capsule().fill(complete ? Theme.lime : Color(white: 0.91)))
                    }
                    .buttonStyle(.plain).padding(.top, 14)
                    SocialButtons(caption: "Or sign up with:")
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 18).padding(.bottom, 30)
            }
        }
    }
}

// MARK: - Reset password (display-only; no reset request is sent)

struct ResetPasswordView: View {
    @Environment(AppModel.self) var m
    @State private var email = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "Reset password", leading: m.sheets.count > 1 ? .back : .close) {
                m.sheets.count > 1 ? m.popSheet() : m.dismissSheets()
            }
            VStack(alignment: .leading, spacing: 22) {
                Text(Copy.resetPassword)
                    .font(.system(size: 17, weight: .light)).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                FormField(label: "Email", placeholder: "name@email.com", text: $email, focused: $focused)
                LimeButton(title: "Reset password") { m.flash("Password reset is not available here") }
                Spacer()
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 14)
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true } }
    }
}
