import AppKit
import SwiftUI

/// Small native About window: icon, version, project links and update entry.
struct AboutView: View {
    @ObservedObject private var locale = LocaleManager.shared
    @ObservedObject private var updates = UpdateChecker.shared

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var repositoryURL: URL {
        URL(string: "https://github.com/WillSat/semono")!
    }

    private var licenseURL: URL {
        URL(string: "https://github.com/WillSat/semono/blob/main/LICENSE")!
    }

    private func t(_ key: String) -> String { locale.localized(key) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 6)

                Text("Semono")
                    .font(.system(size: 32, weight: .bold, design: .rounded))

                Text(t("A pixel-art performance HUD for macOS."))
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Text("\(t("Version")) \(version)")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 30)
            .padding(.bottom, 24)
            .background(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.16), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Divider()

            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Link(destination: repositoryURL) {
                        Label(t("GitHub"), systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Link(destination: licenseURL) {
                        Label(t("License"), systemImage: "doc.text")
                    }
                    Button {
                        if updates.hasUpdate {
                            updates.openRelease()
                        } else {
                            updates.checkForUpdates(manual: true)
                        }
                    } label: {
                        Label(
                            updates.hasUpdate
                                ? t("Go to Update")
                                : updates.isChecking
                                    ? t("Checking for Updates…")
                                    : t("Check for Updates…"),
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .disabled(updates.isChecking)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Text(t("MIT License"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("© 2026 WillSat")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(24)
        }
        .frame(width: 520, height: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(WindowRegistration(window: .about))
        .navigationTitle(t("About Semono"))
    }
}
