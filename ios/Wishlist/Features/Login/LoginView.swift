import SwiftUI

struct LoginView: View {
  enum Mode: String, Hashable { case login, register }
  enum Field: Hashable { case name, email, password }

  @Environment(AppModel.self) private var model
  @Environment(L10n.self) private var l10n
  @Environment(\.dismiss) private var dismiss

  /// Set when shown as a sheet from a shared list; called after a successful login.
  var onSuccess: (() -> Void)?

  @State private var mode: Mode = .login
  @State private var displayName = ""
  @State private var email = ""
  @State private var password = ""
  @State private var showPassword = false
  @State private var busy = false
  @State private var attempted = false
  @State private var openingLink = false
  @FocusState private var focus: Field?

  private var emailValid: Bool { email.trimmed.wholeMatch(of: /[^\s@]+@[^\s@]+\.[^\s@]+/) != nil }
  private var passwordValid: Bool { password.count >= 8 }
  private var nameValid: Bool { mode == .login || !displayName.trimmed.isEmpty }

  var body: some View {
    ScrollView {
      VStack(spacing: 28) {
        intro
        form
        if onSuccess == nil {
          Button {
            openingLink = true
          } label: {
            Label(l10n.t(.openLinkTitle), systemImage: "link")
          }
          .font(.subheadline)
          .accessibilityIdentifier("login.openLink")
        }
      }
      .padding(.horizontal, 24)
      .padding(.top, 12)
      .frame(maxWidth: 480)
      .frame(maxWidth: .infinity)
    }
    .scrollDismissesKeyboard(.interactively)
    .background(alignment: .top) {
      BrandBackdrop().frame(height: 380)
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle(l10n.t(.appTitle))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if onSuccess == nil {
        ToolbarItem(placement: .topBarTrailing) {
          NavigationLink(value: Route.status) {
            Label(l10n.t(.statusTitle), systemImage: "info.circle")
          }
          .accessibilityIdentifier("nav.status")
        }
      } else {
        ToolbarItem(placement: .cancellationAction) {
          Button(l10n.t(.commonCancel), role: .cancel) { dismiss() }
        }
      }
    }
    .sheet(isPresented: $openingLink) {
      OpenLinkSheet()
    }
  }

  private var intro: some View {
    VStack(spacing: 12) {
      Image("BrandIcon")
        .resizable()
        .frame(width: 84, height: 84)
        .clipShape(.rect(cornerRadius: 20))
        .shadow(color: .accentColor.opacity(0.35), radius: 16, y: 8)
        .accessibilityHidden(true)
      Text(l10n.t(.loginHeadline))
        .font(.title.bold())
        .multilineTextAlignment(.center)
      Text(l10n.t(.loginIntro))
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding(.top, 8)
  }

  private var form: some View {
    VStack(spacing: 16) {
      Picker("", selection: $mode.animation(.snappy)) {
        Text(l10n.t(.loginTabLogin)).tag(Mode.login)
        Text(l10n.t(.loginTabRegister)).tag(Mode.register)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .accessibilityIdentifier("login.mode")

      VStack(spacing: 12) {
        if mode == .register {
          field(
            title: l10n.t(.commonYourName), helper: l10n.t(.loginNameHelper),
            error: attempted && !nameValid ? l10n.t(.loginInvalidRegister) : nil
          ) {
            TextField(l10n.t(.commonYourName), text: $displayName)
              .textContentType(.name)
              .submitLabel(.next)
              .focused($focus, equals: .name)
              .accessibilityIdentifier("login.name")
              .onSubmit { focus = .email }
          }
          .transition(.move(edge: .top).combined(with: .opacity))
        }

        field(title: l10n.t(.loginEmail), error: attempted && !emailValid ? l10n.t(.loginEmailError) : nil) {
          TextField(l10n.t(.loginEmail), text: $email)
            .textContentType(.username)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .focused($focus, equals: .email)
            .accessibilityIdentifier("login.email")
            .onSubmit { focus = .password }
        }

        field(title: l10n.t(.loginPassword), error: attempted && !passwordValid ? l10n.t(.loginPasswordError) : nil) {
          HStack {
            Group {
              if showPassword {
                TextField(l10n.t(.loginPassword), text: $password)
              } else {
                SecureField(l10n.t(.loginPassword), text: $password)
              }
            }
            .textContentType(mode == .register ? .newPassword : .password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .focused($focus, equals: .password)
            .accessibilityIdentifier("login.password")
            .onSubmit { Task { await submit() } }

            Button {
              showPassword.toggle()
            } label: {
              Image(systemName: showPassword ? "eye.slash" : "eye")
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(l10n.t(showPassword ? .loginHidePassword : .loginShowPassword))
          }
        }
      }

      Button {
        Task { await submit() }
      } label: {
        ZStack {
          Text(l10n.t(mode == .register ? .loginTabRegister : .loginTabLogin)).opacity(busy ? 0 : 1)
          if busy { ProgressView() }
        }
        .font(.headline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
      }
      .prominentButtonStyle()
      .disabled(busy)
      .accessibilityIdentifier("login.submit")
      .sensoryFeedback(.impact, trigger: busy) { _, new in new }
    }
  }

  private func field(
    title: String, helper: String? = nil, error: String? = nil, @ViewBuilder content: () -> some View
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      content()
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .overlay {
          RoundedRectangle(cornerRadius: 16).strokeBorder(error == nil ? .clear : .red, lineWidth: 1)
        }
      if let text = error ?? helper {
        Text(text)
          .font(.caption)
          .foregroundStyle(error == nil ? Color.secondary : Color.red)
          .padding(.horizontal, 6)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(title)
  }

  private func submit() async {
    guard !busy else { return }
    attempted = true
    guard emailValid, passwordValid, nameValid else {
      model.show(errorMessage: l10n.t(mode == .register ? .loginInvalidRegister : .loginInvalidLogin))
      return
    }
    focus = nil
    busy = true
    defer { busy = false }
    do {
      if mode == .register {
        try await model.register(email: email, password: password, displayName: displayName)
      } else {
        try await model.login(email: email, password: password)
      }
      password = ""
      onSuccess?()
    } catch {
      model.show(error: error)
    }
  }
}

/// iOS has no address bar, so links someone sent can also be pasted here.
struct OpenLinkSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(L10n.self) private var l10n
  @Environment(Router.self) private var router
  @Environment(\.dismiss) private var dismiss
  @State private var text = ""
  @State private var invalid = false
  @FocusState private var focused: Bool

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField(l10n.t(.openLinkPlaceholder), text: $text, axis: .vertical)
            .lineLimit(1...4)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focused)
            .onSubmit(open)
            .accessibilityIdentifier("openLink.field")
          PasteButton(payloadType: String.self) { strings in
            text = strings.first ?? ""
            open()
          }
          .labelStyle(.titleAndIcon)
        } footer: {
          Text(invalid ? l10n.t(.openLinkInvalid) : l10n.t(.openLinkHint))
            .foregroundStyle(invalid ? .red : .secondary)
        }
      }
      .navigationTitle(l10n.t(.openLinkTitle))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(l10n.t(.commonCancel), role: .cancel) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(l10n.t(.openLinkOpen), action: open)
            .disabled(text.trimmed.isEmpty)
            .accessibilityIdentifier("openLink.open")
        }
      }
      .onAppear { focused = true }
      .onChange(of: text) { invalid = false }
    }
    .presentationDetents([.medium])
    .toastHost()
  }

  private func open() {
    guard let token = DeepLink.shareToken(fromText: text, scheme: model.config.urlScheme) else {
      invalid = !text.trimmed.isEmpty
      return
    }
    dismiss()
    router.show(token: token)
  }
}
