//
//  CompanionPanelView.swift
//  TipTour
//
//  SwiftUI content hosted inside the menu bar panel. The normal surface is
//  intentionally pointer-first; durable configuration lives in the separate
//  Settings window.
//  Dark aesthetic via DS.
//

import AVFoundation
import SwiftUI

struct CompanionPanelView: View {
    @ObservedObject var companionManager: CompanionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
            Divider()
                .background(DS.Colors.borderSubtle)
                .padding(.horizontal, 16)

            primaryMessageSection
                .padding(.top, 16)
                .padding(.horizontal, 16)

            if !companionManager.allPermissionsGranted {
                Spacer().frame(height: 16)
                permissionsListSection
                    .padding(.horizontal, 16)
            }

            if !companionManager.hasCompletedOnboarding && companionManager.allPermissionsGranted {
                Spacer().frame(height: 16)
                startButton
                    .padding(.horizontal, 16)
            }

            if companionManager.hasCompletedOnboarding && companionManager.allPermissionsGranted {
                Spacer().frame(height: 12)
                readyControlSection
                    .padding(.horizontal, 16)
            }

            Spacer().frame(height: 12)

            Divider()
                .background(DS.Colors.borderSubtle)
                .padding(.horizontal, 16)

            footerSection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .frame(width: 300)
        .background(panelBackground)
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: statusDotColor.opacity(0.6), radius: 4)

                Text("TipTour")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
            }

            Spacer()

            Text(statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Colors.textTertiary)

            pinToggleButton

            Button(action: {
                NotificationCenter.default.post(name: .tipTourDismissPanel, object: nil)
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DS.Colors.textTertiary)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    /// Pushpin toggle. When on, the panel stays visible regardless of
    /// outside clicks. When off (default), the panel behaves like a
    /// standard menu bar popover.
    private var pinToggleButton: some View {
        Button(action: {
            companionManager.setPanelPinned(!companionManager.isPanelPinned)
        }) {
            Image(systemName: companionManager.isPanelPinned ? "pin.fill" : "pin")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(
                    companionManager.isPanelPinned
                        ? DS.Colors.accent
                        : DS.Colors.textTertiary
                )
                .rotationEffect(.degrees(companionManager.isPanelPinned ? 0 : 45))
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(
                            companionManager.isPanelPinned
                                ? DS.Colors.accent.opacity(0.15)
                                : Color.white.opacity(0.08)
                        )
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help(companionManager.isPanelPinned
            ? "Unpin: panel will close when you click outside"
            : "Pin: panel will stay open when you click outside")
    }

    // MARK: - Primary Message

    @ViewBuilder
    private var primaryMessageSection: some View {
        if companionManager.hasCompletedOnboarding && companionManager.allPermissionsGranted {
            Text("Ctrl+K to type. Ctrl+Option to speak.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if companionManager.allPermissionsGranted {
            Text("You're all set. Hit Start to meet TipTour.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if companionManager.hasCompletedOnboarding {
            VStack(alignment: .leading, spacing: 6) {
                Text("Permissions needed")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(DS.Colors.textSecondary)

                Text("Some permissions were revoked. Grant the four below to keep using TipTour.")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hi, I'm TipTour.")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(DS.Colors.textSecondary)

                Text("Ask for one thing on screen. I'll move the pointer there, click or type, then observe what changed.")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Grant the permissions below to get started.")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Ready Controls

    private var readyControlSection: some View {
        VStack(spacing: 8) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                compactControlButton(
                    title: companionManager.isAutopilotEnabled ? "Auto-click" : "Point only",
                    subtitle: companionManager.isAutopilotEnabled ? "acts" : "guides",
                    systemImage: companionManager.isAutopilotEnabled ? "wand.and.stars" : "hand.tap",
                    isActive: companionManager.isAutopilotEnabled,
                    helpText: companionManager.isAutopilotEnabled
                        ? "TipTour clicks and types after grounding one action"
                        : "TipTour points at the target and waits for you"
                ) {
                    companionManager.setAutopilotEnabled(!companionManager.isAutopilotEnabled)
                }

                compactControlButton(
                    title: companionManager.isAccurateGroundingEnabled ? "Local" : "AX/DOM",
                    subtitle: "grounding",
                    systemImage: "scope",
                    isActive: companionManager.isAccurateGroundingEnabled,
                    helpText: "Toggle local YOLO/OCR grounding"
                ) {
                    companionManager.setAccurateGroundingEnabled(!companionManager.isAccurateGroundingEnabled)
                }

                compactControlButton(
                    title: companionManager.isScreenshotStreamingEnabled ? "Screens" : "Private",
                    subtitle: companionManager.isScreenshotStreamingEnabled ? "remote" : "local",
                    systemImage: companionManager.isScreenshotStreamingEnabled ? "eye" : "eye.slash",
                    isActive: companionManager.isScreenshotStreamingEnabled,
                    helpText: "Toggle remote screenshot context"
                ) {
                    companionManager.setScreenshotStreamingEnabled(!companionManager.isScreenshotStreamingEnabled)
                }

                compactControlButton(
                    title: longTaskRouterTitle,
                    subtitle: isLongTaskRouterEnabled ? "router" : "planner",
                    systemImage: isLongTaskRouterEnabled ? "link" : "bolt",
                    isActive: isLongTaskRouterEnabled,
                    helpText: "Toggle long-task routing"
                ) {
                    companionManager.setHermesOrchestratorEnabled(!companionManager.isHermesOrchestratorEnabled)
                }
            }

            if let activityText = companionManager.textCommandActivityText, !activityText.isEmpty {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.55)
                    Text(activityText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
            }
        }
    }

    private func compactControlButton(
        title: String,
        subtitle: String,
        systemImage: String,
        isActive: Bool,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isActive ? DS.Colors.accent : DS.Colors.textTertiary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.Colors.textSecondary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(DS.Colors.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: 42)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? DS.Colors.accent.opacity(0.11) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isActive ? DS.Colors.accent.opacity(0.28) : DS.Colors.borderSubtle, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help(helpText)
    }

    // MARK: - Start Button

    @ViewBuilder
    private var startButton: some View {
        if !companionManager.hasCompletedOnboarding && companionManager.allPermissionsGranted {
            Button(action: {
                companionManager.triggerOnboarding()
            }) {
                Text("Start")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Colors.textOnAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                            .fill(DS.Colors.accent)
                    )
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
    }

    // MARK: - Permissions List

    private var permissionsListSection: some View {
        VStack(spacing: 2) {
            Text("PERMISSIONS")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(DS.Colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 6)

            microphonePermissionRow
            accessibilityPermissionRow
            screenRecordingPermissionRow

            if companionManager.hasScreenRecordingPermission {
                screenContentPermissionRow
            }

            if !companionManager.allPermissionsGranted {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)
                        .padding(.top, 1)
                    Text("Everything stays on your Mac until you talk. Audio and optional screenshots are sent only to Gemini Live.")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
            }
        }
    }

    private var accessibilityPermissionRow: some View {
        let isGranted = companionManager.hasAccessibilityPermission
        return HStack(alignment: .top) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "hand.raised")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isGranted ? DS.Colors.textTertiary : DS.Colors.warning)
                    .frame(width: 16)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Accessibility")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.Colors.textSecondary)
                    Text("So I can move the cursor and read what's on screen.")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            if isGranted {
                grantedPill
            } else {
                HStack(spacing: 6) {
                    grantButton {
                        WindowPositionManager.requestAccessibilityPermission()
                    }
                    Button(action: {
                        WindowPositionManager.revealAppInFinder()
                        WindowPositionManager.openAccessibilitySettings()
                    }) {
                        Text("Find App")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DS.Colors.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .stroke(DS.Colors.borderSubtle, lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var screenRecordingPermissionRow: some View {
        let isGranted = companionManager.hasScreenRecordingPermission
        return HStack {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.dashed.badge.record")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isGranted ? DS.Colors.textTertiary : DS.Colors.warning)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Screen Recording")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.Colors.textSecondary)
                    Text(isGranted
                         ? "So I can see your screen when you ask for help."
                         : "Quit and reopen after granting.")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)
                }
            }

            Spacer()

            if isGranted {
                grantedPill
            } else {
                grantButton {
                    WindowPositionManager.requestScreenRecordingPermission()
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var screenContentPermissionRow: some View {
        let isGranted = companionManager.hasScreenContentPermission
        return HStack(alignment: .top) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "eye")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isGranted ? DS.Colors.textTertiary : DS.Colors.warning)
                    .frame(width: 16)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Screen Content")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.Colors.textSecondary)
                    Text("Lets me read the screen continuously without picking a window each time.")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            if isGranted {
                grantedPill
            } else {
                grantButton {
                    companionManager.requestScreenContentPermission()
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var microphonePermissionRow: some View {
        let isGranted = companionManager.hasMicrophonePermission
        return HStack(alignment: .top) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "mic")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isGranted ? DS.Colors.textTertiary : DS.Colors.warning)
                    .frame(width: 16)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Microphone")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.Colors.textSecondary)
                    Text("So you can hold ⌃⌥ and talk to me.")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            if isGranted {
                grantedPill
            } else {
                grantButton {
                    let status = AVCaptureDevice.authorizationStatus(for: .audio)
                    if status == .notDetermined {
                        AVCaptureDevice.requestAccess(for: .audio) { _ in }
                    } else {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var grantedPill: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(DS.Colors.success)
                .frame(width: 6, height: 6)
            Text("Granted")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Colors.success)
        }
    }

    private func grantButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Grant")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DS.Colors.textOnAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(DS.Colors.accent)
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    // MARK: - Autopilot Toggle

    /// Promotes TipTour from teaching ("show me how") to autopilot
    /// ("do it for me"). When ON, the cursor flies to each resolved
    /// element and TipTour clicks it for the user; workflow plans
    /// drive themselves end-to-end (including keyboard shortcuts and
    /// text typing). When OFF, TipTour only points and the
    /// user clicks themselves.
    ///
    /// We give this prominence in the panel — same row weight as Neko
    /// — because it's a real change in behavior the user should be
    /// aware of every time they open the panel.
    private var autopilotToggleRow: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: companionManager.isAutopilotEnabled
                      ? "wand.and.stars"
                      : "hand.tap")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(
                        companionManager.isAutopilotEnabled
                            ? DS.Colors.accent
                            : DS.Colors.textTertiary
                    )
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Autopilot")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.Colors.textSecondary)
                    Text(
                        companionManager.isAutopilotEnabled
                            ? "TipTour clicks for you"
                            : "TipTour only points; you click"
                    )
                    .font(.system(size: 10))
                    .foregroundColor(DS.Colors.textTertiary)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { companionManager.isAutopilotEnabled },
                set: { companionManager.setAutopilotEnabled($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(DS.Colors.accent)
            .scaleEffect(0.8)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Screenshot Streaming Toggle

    /// Privacy toggle for whether Gemini Live receives screen JPEGs.
    /// Local overlays and action execution can still use local context;
    /// this only controls remote visual context sent to Gemini.
    private var screenshotStreamingToggleRow: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: companionManager.isScreenshotStreamingEnabled
                      ? "eye"
                      : "eye.slash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(
                        companionManager.isScreenshotStreamingEnabled
                            ? DS.Colors.accent
                            : DS.Colors.textTertiary
                    )
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Screenshots")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.Colors.textSecondary)
                    Text(
                        companionManager.isScreenshotStreamingEnabled
                            ? "Gemini can see your screen"
                            : "voice + local tools only"
                    )
                    .font(.system(size: 10))
                    .foregroundColor(DS.Colors.textTertiary)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { companionManager.isScreenshotStreamingEnabled },
                set: { companionManager.setScreenshotStreamingEnabled($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(DS.Colors.accent)
            .scaleEffect(0.8)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Grounding Toggle

    private var accurateGroundingToggleRow: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: companionManager.isAccurateGroundingEnabled
                      ? "scope"
                      : "scope")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(
                        companionManager.isAccurateGroundingEnabled
                            ? DS.Colors.accent
                            : DS.Colors.textTertiary
                    )
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Accurate Grounding")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.Colors.textSecondary)
                    Text(
                        companionManager.isAccurateGroundingEnabled
                            ? "local YOLO + OCR targets"
                            : "standard AX/CDP grounding"
                    )
                    .font(.system(size: 10))
                    .foregroundColor(DS.Colors.textTertiary)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { companionManager.isAccurateGroundingEnabled },
                set: { companionManager.setAccurateGroundingEnabled($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(DS.Colors.accent)
            .scaleEffect(0.8)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Connections

    private var connectionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CONNECTIONS")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(0.4)
                .foregroundColor(DS.Colors.textTertiary)

            connectionToggleRow(
                title: "CUA Driver",
                subtitle: companionManager.isCuaActionDriverEnabled
                    ? "desktop actions enabled"
                    : "actions paused",
                systemImage: "cursorarrow",
                isOn: Binding(
                    get: { companionManager.isCuaActionDriverEnabled },
                    set: { companionManager.setCuaActionDriverEnabled($0) }
                )
            )

            connectionToggleRow(
                title: "Hermes Auto",
                subtitle: companionManager.isHermesOrchestratorEnabled
                    ? "auto delegate long tasks"
                    : "TipTour stays local",
                systemImage: "link",
                isOn: Binding(
                    get: { companionManager.isHermesOrchestratorEnabled },
                    set: { companionManager.setHermesOrchestratorEnabled($0) }
                )
            )
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
        )
    }

    private var isLongTaskRouterEnabled: Bool {
        companionManager.isHermesOrchestratorEnabled
    }

    private var longTaskRouterTitle: String {
        if companionManager.isHermesOrchestratorEnabled {
            return "Hermes"
        }
        return "Local"
    }

    private func connectionToggleRow(
        title: String,
        subtitle: String,
        systemImage: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isOn.wrappedValue ? DS.Colors.accent : DS.Colors.textTertiary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.Colors.textSecondary)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)
                }
            }

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(DS.Colors.accent)
                .scaleEffect(0.8)
        }
        .padding(.vertical, 3)
    }

    /// Whimsical toggle that swaps the blue triangle cursor for a
    /// pixel-art cat (classic oneko sprites).
    private var nekoModeToggleRow: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "cat.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(
                        companionManager.isNekoModeEnabled
                            ? DS.Colors.accent
                            : DS.Colors.textTertiary
                    )
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Neko mode")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.Colors.textSecondary)
                    Text("replace cursor with a pixel cat")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { companionManager.isNekoModeEnabled },
                set: { companionManager.setNekoModeEnabled($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(DS.Colors.accent)
            .scaleEffect(0.8)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Footer

    private var feedbackButton: some View {
        Button(action: {
            if let url = URL(string: "https://x.com/milindlabs") {
                NSWorkspace.shared.open(url)
            }
        }) {
            Image(systemName: "bubble.left")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 24)
                .foregroundColor(DS.Colors.textTertiary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help("Feedback")
    }

    private var footerSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                feedbackButton

                footerIconButton("Settings", systemImage: "gearshape") {
                    NotificationCenter.default.post(name: .tipTourOpenSettings, object: nil)
                    NotificationCenter.default.post(name: .tipTourDismissPanel, object: nil)
                }

                footerIconButton("Logs", systemImage: "doc.text.magnifyingglass") {
                    PipelineLogStore.shared.record(
                        category: "ui",
                        name: "open_logs_window",
                        status: "ok",
                        message: "Opened TipTour logs window."
                    )
                    NotificationCenter.default.post(name: .tipTourOpenLogs, object: nil)
                    NotificationCenter.default.post(name: .tipTourDismissPanel, object: nil)
                }

                footerIconButton("Follow", systemImage: "play.rectangle.on.rectangle") {
                    PipelineLogStore.shared.record(
                        category: "ui",
                        name: "open_follow_along_window",
                        status: "ok",
                        message: "Opened TipTour follow-along window."
                    )
                    NotificationCenter.default.post(name: .tipTourOpenFollowAlong, object: nil)
                    NotificationCenter.default.post(name: .tipTourDismissPanel, object: nil)
                }

                Spacer()

                footerIconButton("Quit", systemImage: "power") {
                    NSApp.terminate(nil)
                }
            }

        }
    }

    private func footerIconButton(
        _ title: String,
        systemImage: String,
        toggled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 24)
                .foregroundColor(toggled ? DS.Colors.textSecondary : DS.Colors.textTertiary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help(title)
    }

    // MARK: - Visuals

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(DS.Colors.background)
            .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
            .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
    }

    private var statusDotColor: Color {
        if !companionManager.isOverlayVisible {
            return DS.Colors.textTertiary
        }
        switch companionManager.voiceState {
        case .idle:
            return DS.Colors.success
        case .listening:
            return DS.Colors.blue400
        case .processing, .responding:
            return DS.Colors.blue400
        }
    }

    private var statusText: String {
        if !companionManager.hasCompletedOnboarding || !companionManager.allPermissionsGranted {
            return "Setup"
        }
        if !companionManager.isOverlayVisible {
            return "Ready"
        }
        switch companionManager.voiceState {
        case .idle:
            return "Active"
        case .listening:
            return "Listening"
        case .processing:
            return "Processing"
        case .responding:
            return "Responding"
        }
    }
}
