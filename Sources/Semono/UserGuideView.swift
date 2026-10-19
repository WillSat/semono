import SwiftUI

/// A compact, scrollable guide to the HUD's columns, the pressure states and
/// the ways to move or hide the overlay.
struct UserGuideView: View {
    @ObservedObject private var locale = LocaleManager.shared

    private func t(_ key: String) -> String { locale.localized(key) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                readingCard
                metricsCard
                pressureCard
                usingCard
            }
            .padding(26)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .frame(minWidth: 720, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(WindowRegistration(window: .guide))
        .navigationTitle(t("User Guide"))
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 62, height: 62)
                .background(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: .rect(cornerRadius: 16)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(t("User Guide"))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(t("How to read the HUD and what each metric means."))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 2)
    }

    private var readingCard: some View {
        GuideCard(title: t("Reading the HUD"), icon: "eye", tint: .blue) {
            GuideText(t("Each cell is a label and a value. A dash means the sensor is unavailable or has no baseline yet; it is not zero."))
            GuideText(t("Metric colors run from blue through green and yellow to orange and red."))
        }
    }

    private var metricsCard: some View {
        GuideCard(title: t("Metrics"), icon: "square.grid.2x2", tint: .teal) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                metric("CPU", t("Processor utilization."), 0.20)
                metric("GPU", t("Graphics processor utilization."), 0.20)
                metric("PWR", t("System power draw. A dash means telemetry is unavailable."), 0.55)
                metric("MEM", t("Memory in use."), 0.45)
                metric("PRS", t("Kernel memory pressure, shown as #N, #W or #C."), 0.60)
                metric("SWAP", t("Swap in use."), 0.45)
                metric("DR", t("Disk read throughput."), 0.20)
                metric("DW", t("Disk write throughput."), 0.20)
                metric("THM", t("Thermal pressure."), 0.78)
                metric("NET", t("Connection type, Wi-Fi signal and network throughput."), 0.25)
            }
        }
    }

    private var pressureCard: some View {
        GuideCard(title: t("Memory Pressure"), icon: "gauge.with.dots.needle.67percent", tint: .orange) {
            Text(t("PRS is a three-state kernel signal, not a percentage."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                pressureChip("#N", t("Normal"), ColorScale.color(forPressureLevel: 0, light: true))
                pressureChip("#W", t("Warning"), ColorScale.color(forPressureLevel: 1, light: true))
                pressureChip("#C", t("Critical"), ColorScale.color(forPressureLevel: 2, light: true))
            }
        }
    }

    private var usingCard: some View {
        GuideCard(title: t("Using the HUD"), icon: "hand.draw", tint: .purple) {
            GuideBullet(
                icon: "arrow.up.and.down.and.arrow.left.and.right",
                text: t("The HUD stays in the corner selected in Settings → HUD. Use the corner and margin controls there.")
            )
            GuideBullet(
                icon: "menubar.rectangle",
                text: t("Use the menu bar to show or hide the HUD, open Settings, Device Information, this guide, or check for updates.")
            )
            GuideBullet(
                icon: "eye.slash",
                text: t("When the HUD is hidden, only a visible menu bar readout keeps updating.")
            )
        }
    }

    private func metric(_ code: String, _ description: String, _ tint: Double) -> some View {
        let color = ColorScale.color(for: tint, light: true)
        return HStack(alignment: .top, spacing: 9) {
            Text(code)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(color)
                .frame(minWidth: 38, alignment: .leading)
            Text(description)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(color.opacity(0.08), in: .rect(cornerRadius: 10))
    }

    private func pressureChip(_ code: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 7) {
            Text(code)
                .font(.system(.callout, design: .monospaced).weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.callout)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.10), in: .rect(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(color.opacity(0.25))
        }
    }
}

private struct GuideCard<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    private let content: Content

    init(title: String, icon: String, tint: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 22, height: 22)
                    .background(tint.opacity(0.12), in: .rect(cornerRadius: 6))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5))
        }
    }
}

private struct GuideText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GuideBullet: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 18)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
