import SwiftUI

// Screens 4-8. Handoff §6.

private struct AuthTemplate<Fields: View>: View {
    let status: String
    let loud: String
    var soft: String? = nil
    let cta: String
    var ctaEnabled: Bool = true
    let onCTA: () -> Void
    var footer: String? = nil
    var onFooter: (() -> Void)? = nil
    @ViewBuilder var fields: () -> Fields

    var body: some View {
        ScreenScaffold(top: 20) {
            MonoLabel(status, size: 10, color: .steel)
                .padding(.top, 32)
                .padding(.bottom, Space.section)

            Headline(loud, soft, size: 32)
                .padding(.bottom, Space.section)

            VStack(spacing: 22, content: fields)

            Spacer(minLength: Space.section)

            PrimaryCTA(title: cta, enabled: ctaEnabled, action: onCTA)

            if let footer {
                FooterLink(text: footer, action: onFooter ?? {})
                    .padding(.top, 18)
            }
            Spacer().frame(height: Space.block)
        }
    }
}

struct SignUpScreen: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var app: AppState
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?

    var body: some View {
        AuthTemplate(status: Copy.SignUp.status,
                    loud: Copy.SignUp.body,
                    cta: Copy.SignUp.cta,
                    ctaEnabled: !name.isEmpty && !email.isEmpty && password.count >= 8,
                    onCTA: submit,
                    footer: Copy.SignUp.footer) {
            router.push(.logIn)
        } fields: {
            StrideField(label: Copy.SignUp.name, value: $name)
            StrideField(label: Copy.SignUp.email, value: $email, keyboard: .emailAddress, contentType: .emailAddress)
            StrideField(label: Copy.SignUp.pass, value: $password, secure: true, contentType: .newPassword)
            if let error {
                MonoLabel(error, size: 10, color: .danger)
            }
        }
    }

    private func submit() {
        Task {
            do {
                app.user = try await app.auth.signUp(name: name, email: email, password: password)
                app.isSignedIn = true
                router.startOnboarding()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct LogInScreen: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var app: AppState
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?

    var body: some View {
        AuthTemplate(status: Copy.LogIn.status,
                    loud: Copy.LogIn.body,
                    cta: Copy.LogIn.cta,
                    ctaEnabled: !email.isEmpty && password.count >= 8,
                    onCTA: submit,
                    footer: Copy.LogIn.footer) {
            router.push(.signUp)
        } fields: {
            StrideField(label: Copy.LogIn.email, value: $email, keyboard: .emailAddress, contentType: .emailAddress)
            StrideField(label: Copy.LogIn.pass, value: $password, secure: true, contentType: .password)
            HStack {
                Spacer()
                Button(Copy.LogIn.forgot) { router.push(.forgotPassword) }
                    .buttonStyle(.plain)
                    .font(Type.mono(11))
                    .foregroundStyle(Color.dim)
            }
            if let error {
                MonoLabel(error, size: 10, color: .danger)
            }
        }
    }

    private func submit() {
        Task {
            do {
                app.user = try await app.auth.logIn(email: email, password: password)
                app.isSignedIn = true
                router.enterMain()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct ForgotPasswordScreen: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var app: AppState
    @State private var email = ""

    var body: some View {
        AuthTemplate(status: Copy.Forgot.status,
                    loud: Copy.Forgot.loud, soft: Copy.Forgot.soft,
                    cta: Copy.Forgot.cta,
                    ctaEnabled: !email.isEmpty,
                    onCTA: {
                        Task {
                            try? await app.auth.sendPasswordReset(to: email)
                            router.push(.forgotPasswordSent)
                        }
                    },
                    footer: nil, onFooter: nil) {
            Text(Copy.Forgot.body)
                .font(Type.archivo(15))
                .foregroundStyle(Color.dim)
            StrideField(label: "Where we find you", value: $email, keyboard: .emailAddress, contentType: .emailAddress)
        }
        .overlay(alignment: .topLeading) { BackBar { router.pop() }.padding(.horizontal, Space.screen).padding(.top, 4) }
    }
}

struct ForgotPasswordSentScreen: View {
    @EnvironmentObject private var router: Router
    // In a real flow this is passed in; ForgotPasswordScreen would carry it via Route params.
    var email: String = "you@gmail.com"

    var body: some View {
        ScreenScaffold(top: 20) {
            BackBar { router.pop() }
            Spacer().frame(height: 40)
            Headline(Copy.Forgot.sentLoud, Copy.Forgot.sentSoft, size: 32)
                .padding(.bottom, Space.block)
            Text(Copy.Forgot.sentBody(email: email))
                .font(Type.archivo(15))
                .foregroundStyle(Color.dim)
            Spacer().frame(height: Space.section)
            MonoLabel(Copy.Forgot.spam, size: 10, color: .dimmer)
            Spacer(minLength: 0)
            FooterLink(text: Copy.Forgot.resend) { router.pop() }
                .padding(.bottom, Space.block)
        }
    }
}

struct SetNewPasswordScreen: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var app: AppState
    @State private var password = ""
    @State private var confirm = ""

    var body: some View {
        AuthTemplate(status: Copy.NewPassword.status,
                    loud: Copy.NewPassword.loud, soft: Copy.NewPassword.soft,
                    cta: Copy.NewPassword.cta,
                    ctaEnabled: password.count >= 8 && password == confirm,
                    onCTA: {
                        Task {
                            try? await app.auth.setNewPassword(password, token: "")
                            router.phase = .auth
                            router.popToRoot()
                        }
                    },
                    footer: nil, onFooter: nil) {
            StrideField(label: "New password", value: $password, secure: true, contentType: .newPassword)
            StrideField(label: "Type it again", value: $confirm, secure: true, contentType: .newPassword)
        }
    }
}

#Preview { SignUpScreen().environmentObject(Router()).environmentObject(AppState()) }
