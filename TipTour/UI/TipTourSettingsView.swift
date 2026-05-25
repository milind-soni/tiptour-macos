import AVFoundation
import SwiftUI

struct TipTourSettingsView: View {
    @ObservedObject var companionManager: CompanionManager
    @State private var selectedSection: SettingsSection = .voice
    @State private var hermesServerURLInput: String = TipTourDefaults.hermesAPIBaseURL
    private let sidebarWidth: CGFloat = 178
    private let contentMaxWidth: CGFloat = 620

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()
                .background(DS.Colors.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    selectedContent
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 24)
                .frame(maxWidth: contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(DS.Colors.background)
        .onAppear {
            hermesServerURLInput = companionManager.hermesAPIBaseURL
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SettingsPointerMark()
                    .fill(DS.Colors.textSecondary)
                    .frame(width: 18, height: 18)

                Text("TipTour")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
            }
            .padding(.bottom, 16)

            ForEach(SettingsSection.allCases) { section in
                sidebarButton(section)
            }

            Spacer()

            Text("Ctrl+K for text\nCtrl+Option for voice")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .padding(.horizontal, 14)
        .padding(.top, 24)
        .padding(.bottom, 18)
        .frame(width: sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(DS.Colors.surface1)
    }

    private func sidebarButton(_ section: SettingsSection) -> some View {
        Button {
            selectedSection = section
        } label: {
            HStack(spacing: 9) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(selectedSection == section ? DS.Colors.textPrimary : DS.Colors.textTertiary)
                    .frame(width: 16)

                Text(section.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(selectedSection == section ? DS.Colors.textPrimary : DS.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selectedSection == section ? Color.white.opacity(0.075) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(selectedSection.title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(DS.Colors.textPrimary)
                .lineLimit(1)

            Text(selectedSection.subtitle)
                .font(.system(size: 12))
                .foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedSection {
        case .voice:
            voiceSection
        case .connections:
            connectionsSection
        case .privacy:
            privacySection
        case .permissions:
            permissionsSection
        case .advanced:
            advancedSection
        }
    }

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProviderSetupView(companionManager: companionManager)

            settingsRow(
                title: "Pipecat Voice",
                subtitle: companionManager.isPipecatVoiceHarnessEnabled
                    ? "Use the local realtime voice sidecar when it is available."
                    : "Use native Gemini Live directly for now.",
                systemImage: "waveform",
                isOn: Binding(
                    get: { companionManager.isPipecatVoiceHarnessEnabled },
                    set: { companionManager.setPipecatVoiceHarnessEnabled($0) }
                )
            )

            note("Gemini is the built-in realtime voice path. Pipecat is kept as a local sidecar so it can own voice orchestration while TipTour keeps macOS grounding and actions.")
        }
    }

    private var connectionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingsRow(
                title: "CUA Driver",
                subtitle: companionManager.isCuaActionDriverEnabled
                    ? "Desktop clicking, typing, launching, and shortcuts are enabled."
                    : "TipTour can observe and plan, but desktop actions are blocked.",
                systemImage: "cursorarrow.motionlines",
                isOn: Binding(
                    get: { companionManager.isCuaActionDriverEnabled },
                    set: { companionManager.setCuaActionDriverEnabled($0) }
                )
            )

            settingsRow(
                title: "Hermes Auto",
                subtitle: companionManager.isHermesOrchestratorEnabled
                    ? "Long Ctrl+K tasks can route to Hermes."
                    : "Ctrl+K stays local or uses Claude one-step planning.",
                systemImage: "link",
                isOn: Binding(
                    get: { companionManager.isHermesOrchestratorEnabled },
                    set: { companionManager.setHermesOrchestratorEnabled($0) }
                )
            )

            hermesConnectionCard

            settingsRow(
                title: "Pipecat Voice",
                subtitle: "Local sidecar health is checked when you enable it.",
                systemImage: "dot.radiowaves.left.and.right",
                isOn: Binding(
                    get: { companionManager.isPipecatVoiceHarnessEnabled },
                    set: { companionManager.setPipecatVoiceHarnessEnabled($0) }
                )
            )

            pipecatConnectionCard
        }
    }

    private var hermesConnectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                rowIcon("network")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Hermes Connection")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.Colors.textSecondary)
                    Text(companionManager.hermesConnectionStatus.detail)
                        .font(.system(size: 11))
                        .foregroundColor(DS.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                statusBadge(companionManager.hermesConnectionStatus.state)
            }

            TextField("http://127.0.0.1:8642", text: $hermesServerURLInput)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(DS.Colors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(fieldBackground)
                .padding(.leading, 34)
                .onSubmit {
                    companionManager.setHermesAPIBaseURL(hermesServerURLInput)
                    hermesServerURLInput = companionManager.hermesAPIBaseURL
                }

            HStack(spacing: 8) {
                Spacer(minLength: 34)

                Button("Detect") {
                    companionManager.setHermesAPIBaseURL(hermesServerURLInput)
                    Task {
                        await companionManager.detectHermesConnection()
                        await MainActor.run {
                            hermesServerURLInput = companionManager.hermesAPIBaseURL
                        }
                    }
                }
                .controlSize(.small)
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.bordered)
                .pointerCursor()

                Button("Test") {
                    companionManager.setHermesAPIBaseURL(hermesServerURLInput)
                    Task {
                        await companionManager.testHermesConnection()
                        await MainActor.run {
                            hermesServerURLInput = companionManager.hermesAPIBaseURL
                        }
                    }
                }
                .controlSize(.small)
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.borderedProminent)
                .tint(DS.Colors.accent)
                .pointerCursor()
            }

            if let installPath = companionManager.hermesConnectionStatus.detectedInstallPath {
                Text(installPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(DS.Colors.textTertiary.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, 34)
            }
        }
        .padding(.vertical, 8)
    }

    private var pipecatConnectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                rowIcon("waveform")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Pipecat Sidecar")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.Colors.textSecondary)
                    Text(companionManager.pipecatVoiceHarnessStatus.detail)
                        .font(.system(size: 11))
                        .foregroundColor(DS.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                statusBadge(companionManager.pipecatVoiceHarnessStatus.state)
            }

            HStack(spacing: 8) {
                Spacer(minLength: 34)

                Button("Test") {
                    Task {
                        await companionManager.testPipecatVoiceHarnessConnection()
                    }
                }
                .controlSize(.small)
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.bordered)
                .pointerCursor()

                Button(companionManager.pipecatVoiceHarnessStatus.isActive ? "Stop" : "Start") {
                    Task {
                        if companionManager.pipecatVoiceHarnessStatus.isActive {
                            await companionManager.stopPipecatVoiceHarness()
                        } else {
                            companionManager.setPipecatVoiceHarnessEnabled(true)
                        }
                    }
                }
                .controlSize(.small)
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.borderedProminent)
                .tint(DS.Colors.accent)
                .pointerCursor()
            }

            Text("Run harnesses/pipecat-voice on 127.0.0.1:7860. The sidecar calls TipTour's local harness for observe, targets, and actions.")
                .font(.system(size: 10))
                .foregroundColor(DS.Colors.textTertiary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 34)
        }
        .padding(.vertical, 8)
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingsRow(
                title: "Remote Screenshots",
                subtitle: companionManager.isScreenshotStreamingEnabled
                    ? "Gemini can receive screen context when you ask for help."
                    : "Remote visual context is off; local grounding can still run.",
                systemImage: companionManager.isScreenshotStreamingEnabled ? "eye" : "eye.slash",
                isOn: Binding(
                    get: { companionManager.isScreenshotStreamingEnabled },
                    set: { companionManager.setScreenshotStreamingEnabled($0) }
                )
            )

            settingsRow(
                title: "Accurate Grounding",
                subtitle: companionManager.isAccurateGroundingEnabled
                    ? "Local YOLO/OCR targets improve grounding before LLM coordinates."
                    : "Use AX/DOM and standard local resolvers.",
                systemImage: "scope",
                isOn: Binding(
                    get: { companionManager.isAccurateGroundingEnabled },
                    set: { companionManager.setAccurateGroundingEnabled($0) }
                )
            )

            note("Screenshots only controls remote visual context. TipTour still uses local screen understanding for grounding and safety when enabled.")
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            permissionRow(
                title: "Microphone",
                subtitle: "Required for voice input.",
                systemImage: "mic",
                isGranted: companionManager.hasMicrophonePermission
            ) {
                let status = AVCaptureDevice.authorizationStatus(for: .audio)
                if status == .notDetermined {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in }
                } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            }

            permissionRow(
                title: "Accessibility",
                subtitle: "Required to read app UI and drive desktop actions.",
                systemImage: "hand.raised",
                isGranted: companionManager.hasAccessibilityPermission
            ) {
                WindowPositionManager.requestAccessibilityPermission()
            }

            permissionRow(
                title: "Screen Recording",
                subtitle: "Required to capture screen context.",
                systemImage: "rectangle.dashed.badge.record",
                isGranted: companionManager.hasScreenRecordingPermission
            ) {
                WindowPositionManager.requestScreenRecordingPermission()
            }

            if companionManager.hasScreenRecordingPermission {
                permissionRow(
                    title: "Screen Content",
                    subtitle: "Lets TipTour read the screen without choosing a window each time.",
                    systemImage: "eye",
                    isGranted: companionManager.hasScreenContentPermission
                ) {
                    companionManager.requestScreenContentPermission()
                }
            }
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingsRow(
                title: "Neko Mode",
                subtitle: "Use the pixel-art cursor instead of the standard pointer.",
                systemImage: "cat.fill",
                isOn: Binding(
                    get: { companionManager.isNekoModeEnabled },
                    set: { companionManager.setNekoModeEnabled($0) }
                )
            )

            #if DEBUG
            settingsRow(
                title: "Detection Overlay",
                subtitle: "Show local CoreML and OCR boxes for debugging.",
                systemImage: "viewfinder",
                isOn: Binding(
                    get: { companionManager.isDetectionOverlayEnabled },
                    set: { companionManager.setDetectionOverlayEnabled($0) }
                )
            )

            Button {
                let screen = NSScreen.main
                companionManager.detectedElementScreenLocation = screen.map {
                    CGPoint(x: $0.frame.midX, y: $0.frame.midY)
                }
                companionManager.detectedElementDisplayFrame = screen?.frame
                companionManager.detectedElementBubbleText = "Test"
            } label: {
                settingsActionLabel(
                    title: "Test Cursor Flight",
                    subtitle: "Send the overlay pointer to the center of the main screen.",
                    systemImage: "arrow.up.right"
                )
            }
            .buttonStyle(.plain)
            .pointerCursor()
            #endif
        }
    }

    private func settingsRow(
        title: String,
        subtitle: String,
        systemImage: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            rowIcon(systemImage)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.Colors.textSecondary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(DS.Colors.accent)
                .scaleEffect(0.82)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func permissionRow(
        title: String,
        subtitle: String,
        systemImage: String,
        isGranted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            rowIcon(systemImage)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.Colors.textSecondary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)

            if isGranted {
                HStack(spacing: 5) {
                    Circle()
                        .fill(DS.Colors.success)
                        .frame(width: 6, height: 6)
                    Text("Granted")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.Colors.success)
                }
            } else {
                Button("Grant", action: action)
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(DS.Colors.accent)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsActionLabel(
        title: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            rowIcon(systemImage)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.Colors.textSecondary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func rowIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(DS.Colors.textTertiary)
            .frame(width: 22)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(DS.Colors.surface1.opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(DS.Colors.borderSubtle.opacity(0.65), lineWidth: 0.8)
            )
    }

    private func statusBadge(_ state: HermesConnectionState) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(hermesStatusColor(state))
                .frame(width: 6, height: 6)
            Text(state.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(hermesStatusColor(state))
        }
        .lineLimit(1)
    }

    private func statusBadge(_ state: PipecatVoiceHarnessConnectionState) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(pipecatStatusColor(state))
                .frame(width: 6, height: 6)
            Text(state.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(pipecatStatusColor(state))
        }
        .lineLimit(1)
    }

    private func hermesStatusColor(_ state: HermesConnectionState) -> Color {
        switch state {
        case .connected:
            return DS.Colors.success
        case .checking:
            return DS.Colors.textSecondary
        case .wrongServer:
            return DS.Colors.warning
        case .notFound, .notRunning, .error:
            return DS.Colors.destructiveText
        case .idle:
            return DS.Colors.textTertiary
        }
    }

    private func pipecatStatusColor(_ state: PipecatVoiceHarnessConnectionState) -> Color {
        switch state {
        case .connected:
            return DS.Colors.success
        case .checking:
            return DS.Colors.textSecondary
        case .wrongServer:
            return DS.Colors.warning
        case .notRunning, .error:
            return DS.Colors.destructiveText
        case .idle:
            return DS.Colors.textTertiary
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(DS.Colors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case voice
    case connections
    case privacy
    case permissions
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .voice: return "Voice"
        case .connections: return "Connections"
        case .privacy: return "Privacy"
        case .permissions: return "Permissions"
        case .advanced: return "Advanced"
        }
    }

    var subtitle: String {
        switch self {
        case .voice:
            return "Provider keys and the optional Pipecat voice sidecar."
        case .connections:
            return "Local harnesses and desktop action integrations."
        case .privacy:
            return "Control what can leave the Mac and how local grounding runs."
        case .permissions:
            return "macOS access TipTour needs to hear, see, and act."
        case .advanced:
            return "Experimental visuals and development controls."
        }
    }

    var systemImage: String {
        switch self {
        case .voice: return "waveform.badge.mic"
        case .connections: return "point.3.connected.trianglepath.dotted"
        case .privacy: return "lock.shield"
        case .permissions: return "checkmark.shield"
        case .advanced: return "slider.horizontal.3"
        }
    }
}

private struct SettingsPointerMark: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let originX = rect.midX - 12 * scale
        let originY = rect.midY - 12 * scale

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: originX + x * scale, y: originY + y * scale)
        }

        var path = Path()
        path.move(to: point(4.037, 4.688))
        path.addCurve(
            to: point(4.688, 4.037),
            control1: point(3.90, 3.90),
            control2: point(3.90, 3.90)
        )
        path.addLine(to: point(20.688, 10.537))
        path.addCurve(
            to: point(20.625, 11.484),
            control1: point(21.42, 10.84),
            control2: point(21.42, 10.84)
        )
        path.addLine(to: point(14.501, 13.064))
        path.addCurve(
            to: point(13.063, 14.499),
            control1: point(13.43, 13.34),
            control2: point(13.43, 13.34)
        )
        path.addLine(to: point(11.484, 20.625))
        path.addCurve(
            to: point(10.537, 20.688),
            control1: point(11.17, 21.42),
            control2: point(11.17, 21.42)
        )
        path.closeSubpath()
        return path
    }
}
