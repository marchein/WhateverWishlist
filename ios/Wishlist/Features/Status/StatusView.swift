import SwiftUI

struct StatusView: View {
  @Environment(AppModel.self) private var model
  @Environment(L10n.self) private var l10n

  @State private var backendVersion: String?
  @State private var loading = true
  @State private var failed = false

  var body: some View {
    List {
      Section {
        LabeledContent(l10n.t(.statusApp), value: AppConfig.appVersion)
        LabeledContent(l10n.t(.statusAddress)) {
          Text(model.config.apiURL.absoluteString).textSelection(.enabled)
        }
        LabeledContent(l10n.t(.statusBackend)) {
          if loading {
            ProgressView().accessibilityLabel(l10n.t(.statusChecking))
          } else if failed {
            Label(l10n.t(.statusUnreachable), systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(.red)
              .multilineTextAlignment(.trailing)
          } else if let backendVersion {
            Label(backendVersion, systemImage: "checkmark.circle.fill")
              .foregroundStyle(.green)
              .accessibilityIdentifier("status.backendVersion")
          } else {
            Text(l10n.t(.statusNotReported)).multilineTextAlignment(.trailing)
          }
        }
      }

      Section {
        Button {
          Task { await load() }
        } label: {
          Label(l10n.t(.statusRefresh), systemImage: "arrow.clockwise")
        }
        .disabled(loading)
        Link(destination: model.config.webURL) {
          Label(l10n.t(.statusWebApp), systemImage: "safari")
        }
      }

      // The language follows iOS; it can be changed per app in the system settings.
      Section {
        LabeledContent(l10n.t(.commonLanguage), value: l10n.language.nativeName)
        if let settings = URL(string: UIApplication.openSettingsURLString) {
          Link(destination: settings) {
            Label(l10n.t(.languageSettings), systemImage: "gear")
          }
        }
      }
    }
    .navigationTitle(l10n.t(.statusTitle))
    .task { await load() }
    .refreshable { await load() }
  }

  private func load() async {
    loading = true
    failed = false
    backendVersion = nil
    defer { loading = false }
    do {
      let health = try await model.api.health()
      guard health.ok else { throw APIError.invalidResponse }
      backendVersion = health.version
    } catch is CancellationError {
    } catch {
      failed = true
      model.show(error: error)
    }
  }
}
