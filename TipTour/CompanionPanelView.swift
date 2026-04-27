//
//  CompanionPanelView.swift
//  TipTour
//
//  The SwiftUI content hosted inside the menu bar panel. Shows the companion
//  voice status, push-to-talk shortcut, and quick settings. Designed to feel
//  like Loom's recording panel — dark, rounded, minimal, and special.
//

import AVFoundation
import SwiftUI

struct CompanionPanelView: View {
    @ObservedObject var companionManager: CompanionManager
    @ObservedObject private var workflowRunner: WorkflowRunner = .shared
    @State private var emailInput: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
            Divider()
                .background(DS.Colors.borderSubtle)
                .padding(.horizontal, 16)

            permissionsCopySection
                .padding(.top, 16)
                .padding(.horizontal, 16)

            if let activePlan = workflowRunner.activePlan,
               !activePlan.steps.isEmpty {
                Spacer().frame(height: 12)
                planChecklistSection(plan: activePlan)
                    .padding(.horizontal, 16)
            }

            // Voice-mode / Claude-model picker hidden — TipTour ships
            // Gemini-only. Claude/ElevenLabs code paths remain compiled
            // but are no longer user-selectable.

            if !companionManager.allPermissionsGranted {
                Spacer()
                    .frame(height: 16)

                settingsSection
                    .padding(.horizontal, 16)
            }

            if !companionManager.hasCompletedOnboarding && companionManager.allPermissionsGranted {
                Spacer()
                    .frame(height: 16)

                startButton
                    .padding(.horizontal, 16)
            }

            // Show TipTour toggle — hidden for now
            // if companionManager.hasCompletedOnboarding && companionManager.allPermissionsGranted {
            //     Spacer()
            //         .frame(height: 16)
            //
            //     showTipTourCursorToggleRow
            //         .padding(.horizontal, 16)
            // }

            if companionManager.hasCompletedOnboarding && companionManager.allPermissionsGranted {
                Spacer()
                    .frame(height: 12)

                nekoModeToggleRow
                    .padding(.horizontal, 16)

                Spacer()
                    .frame(height: 12)

                Divider()
                    .background(DS.Colors.borderSubtle)
                    .padding(.horizontal, 16)

                Spacer()
                    .frame(height: 12)

                tutorialSection
                    .padding(.horizontal, 16)
            }

            if companionManager.hasCompletedOnboarding && companionManager.allPermissionsGranted {
                Spacer()
                    .frame(height: 12)

                developerSection
                    .padding(.horizontal, 16)
            }

            Spacer()
                .frame(height: 12)

            Divider()
                .background(DS.Colors.borderSubtle)
                .padding(.horizontal, 16)

            footerSection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .frame(width: 320)
        .background(panelBackground)
    }

    // MARK: - Developer (bring-your-own-key)

    /// Collapsible section for developers building TipTour from source
    /// who don't want to deploy their own Cloudflare Worker. Paste a
    /// Gemini API key here and the app uses it directly via Keychain
    /// instead of hitting the Worker's /gemini-live-key endpoint.
    /// Hidden behind a disclosure so the shipped DMG doesn't invite
    /// end-users to paste keys they don't need.
    @State private var isDeveloperSectionExpanded: Bool = false
    @State private var developerGeminiKeyInput: String = ""
    @State private var developerKeyStatus: String = ""

    private var developerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDeveloperSectionExpanded.toggle()
                }
                if isDeveloperSectionExpanded {
                    developerGeminiKeyInput = KeychainStore.geminiAPIKey ?? ""
                    developerKeyStatus = ""
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "hammer")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.Colors.textTertiary)
                        .frame(width: 16)
                    Text("Developer")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DS.Colors.textSecondary)
                    Spacer()
                    Image(systemName: isDeveloperSectionExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Colors.textTertiary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .pointerCursor()

            if isDeveloperSectionExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bring your own Gemini key")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DS.Colors.textSecondary)
                        .padding(.top, 8)

                    Text("For source builds. Paste a Gemini API key and TipTour uses it directly instead of the Cloudflare Worker proxy. Stored in macOS Keychain, never synced.")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    SecureField("AIzaSy...", text: $developerGeminiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))

                    HStack(spacing: 6) {
                        Button("Save") {
                            KeychainStore.geminiAPIKey = developerGeminiKeyInput
                            developerKeyStatus = "Saved"
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .pointerCursor()
                        .disabled(developerGeminiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Clear") {
                            developerGeminiKeyInput = ""
                            KeychainStore.geminiAPIKey = nil
                            developerKeyStatus = "Cleared"
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .pointerCursor()

                        Text(developerKeyStatus)
                            .font(.system(size: 10))
                            .foregroundColor(DS.Colors.textTertiary)

                        Spacer()

                        Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                            Text("Get a key ↗")
                                .font(.system(size: 10))
                                .foregroundColor(DS.Colors.accent)
                        }
                        .pointerCursor()
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack {
            HStack(spacing: 8) {
                // Animated status dot
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
    /// outside clicks — useful for using TipTour as a workspace tool
    /// while referring to another app. When off (default), the panel
    /// behaves like a standard menu bar popover.
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

    // MARK: - Permissions Copy

    @ViewBuilder
    private var permissionsCopySection: some View {
        if companionManager.hasCompletedOnboarding && companionManager.allPermissionsGranted {
            Text("Hold Control+Option to talk.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if companionManager.allPermissionsGranted && !companionManager.hasSubmittedEmail {
            VStack(alignment: .leading, spacing: 4) {
                Text("Drop your email to get started.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Colors.textSecondary)
                Text("If I keep building this, I'll keep you in the loop.")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if companionManager.allPermissionsGranted {
            Text("You're all set. Hit Start to meet TipTour.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if companionManager.hasCompletedOnboarding {
            // Permissions were revoked after onboarding — tell user to re-grant
            VStack(alignment: .leading, spacing: 6) {
                Text("Permissions needed")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(DS.Colors.textSecondary)

                Text("Some permissions were revoked. Grant all four below to keep using TipTour.")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hi, I'm Milind. This is TipTour.")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(DS.Colors.textSecondary)

                Text("A side project I made to help me learn stuff as I use my computer.")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Grant the three permissions below to get started — each one explains what it's for.")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Email + Start Button

    @ViewBuilder
    private var startButton: some View {
        if !companionManager.hasCompletedOnboarding && companionManager.allPermissionsGranted {
            if !companionManager.hasSubmittedEmail {
                VStack(spacing: 8) {
                    TextField("Enter your email", text: $emailInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(DS.Colors.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                                .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
                        )

                    Button(action: {
                        companionManager.submitEmail(emailInput)
                    }) {
                        Text("Submit")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DS.Colors.textOnAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
                                    .fill(emailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                          ? DS.Colors.accent.opacity(0.4)
                                          : DS.Colors.accent)
                            )
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                    .disabled(emailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
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
    }

    // MARK: - Permissions

    private var settingsSection: some View {
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

            // Trust footer — appears once any permission is still
            // missing, so the user sees the privacy story BEFORE they
            // start clicking Grant. Suppressed once everything is on.
            if !companionManager.allPermissionsGranted {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)
                        .padding(.top, 1)
                    Text("Everything stays on your Mac. Screenshots and audio are only sent to Gemini when you hold ⌃⌥ to talk.")
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
                HStack(spacing: 4) {
                    Circle()
                        .fill(DS.Colors.success)
                        .frame(width: 6, height: 6)
                    Text("Granted")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.Colors.success)
                }
            } else {
                HStack(spacing: 6) {
                    Button(action: {
                        // Triggers the system accessibility prompt (AXIsProcessTrustedWithOptions)
                        // on first attempt, then opens System Settings on subsequent attempts.
                        WindowPositionManager.requestAccessibilityPermission()
                    }) {
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

                    Button(action: {
                        // Reveals the app in Finder so the user can drag it into
                        // the Accessibility list if it doesn't appear automatically
                        // (common with unsigned dev builds).
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
                HStack(spacing: 4) {
                    Circle()
                        .fill(DS.Colors.success)
                        .frame(width: 6, height: 6)
                    Text("Granted")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.Colors.success)
                }
            } else {
                Button(action: {
                    // Triggers the native macOS screen recording prompt on first
                    // attempt (auto-adds app to the list), then opens System Settings
                    // on subsequent attempts.
                    WindowPositionManager.requestScreenRecordingPermission()
                }) {
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
                    Text("Lets me read the screen continuously without picking a window each time. Apple makes us re-confirm this monthly.")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            if isGranted {
                HStack(spacing: 4) {
                    Circle()
                        .fill(DS.Colors.success)
                        .frame(width: 6, height: 6)
                    Text("Granted")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.Colors.success)
                }
            } else {
                Button(action: {
                    companionManager.requestScreenContentPermission()
                }) {
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
                HStack(spacing: 4) {
                    Circle()
                        .fill(DS.Colors.success)
                        .frame(width: 6, height: 6)
                    Text("Granted")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.Colors.success)
                }
            } else {
                Button(action: {
                    // Triggers the native macOS microphone permission dialog on
                    // first attempt. If already denied, opens System Settings.
                    let status = AVCaptureDevice.authorizationStatus(for: .audio)
                    if status == .notDetermined {
                        AVCaptureDevice.requestAccess(for: .audio) { _ in }
                    } else {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }) {
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
        }
        .padding(.vertical, 6)
    }

    private func permissionRow(
        label: String,
        iconName: String,
        isGranted: Bool,
        settingsURL: String
    ) -> some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isGranted ? DS.Colors.textTertiary : DS.Colors.warning)
                    .frame(width: 16)

                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.Colors.textSecondary)
            }

            Spacer()

            if isGranted {
                HStack(spacing: 4) {
                    Circle()
                        .fill(DS.Colors.success)
                        .frame(width: 6, height: 6)
                    Text("Granted")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.Colors.success)
                }
            } else {
                Button(action: {
                    if let url = URL(string: settingsURL) {
                        NSWorkspace.shared.open(url)
                    }
                }) {
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
        }
        .padding(.vertical, 6)
    }



    // MARK: - Neko Mode Toggle

    /// Whimsical toggle that swaps the blue triangle cursor for a
    /// pixel-art cat (classic oneko sprites). Purely visual — behavior
    /// is unchanged. Persisted via UserDefaults in CompanionManager.
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

    // MARK: - Show TipTour Cursor Toggle

    private var showTipTourCursorToggleRow: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Colors.textTertiary)
                    .frame(width: 16)

                Text("Show TipTour")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.Colors.textSecondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { companionManager.isTipTourCursorEnabled },
                set: { companionManager.setTipTourCursorEnabled($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(DS.Colors.accent)
            .scaleEffect(0.8)
        }
        .padding(.vertical, 4)
    }

    private var speechToTextProviderRow: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "mic.badge.waveform")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Colors.textTertiary)
                    .frame(width: 16)

                Text("Speech to Text")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.Colors.textSecondary)
            }

            Spacer()

            Text(companionManager.buddyDictationManager.transcriptionProviderDisplayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Colors.textTertiary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Plan Checklist

    /// Minimal checklist shown while a workflow plan is active. Lists every
    /// step with the current one highlighted. ClickDetector advances the
    /// highlight automatically when the user clicks the resolved target;
    /// the debug toggle at the bottom loosens that to "any click advances"
    /// for when YOLO/AX resolves wrong and the user still wants to walk
    /// through the plan.
    private func planChecklistSection(plan: WorkflowPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.Colors.textTertiary)
                Text(plan.goal)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
                    .lineLimit(1)
                Spacer()
                if let app = plan.app, !app.isEmpty {
                    Text(app)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Colors.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.06))
                        )
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                    planChecklistRow(
                        step: step,
                        index: index,
                        isCurrent: index == workflowRunner.activeStepIndex
                    )
                }
            }

            if let failureLabel = workflowRunner.currentStepResolutionFailureLabel {
                planResolutionFailurePrompt(failureLabel: failureLabel)
            }

            Divider()
                .background(DS.Colors.borderSubtle)
                .padding(.top, 2)

            planControlsRow

            advanceOnAnyClickDebugToggleRow
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
        )
    }

    /// Debug switch that tells ClickDetector to advance on any click
    /// (not just clicks within the 40pt tolerance of the resolved
    /// target). Hidden in a subtle "Debug" row so it reads as a power
    /// user affordance, not a primary UI feature.
    private var advanceOnAnyClickDebugToggleRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "ladybug")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.Colors.textTertiary)
            Text("Advance on any click")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Colors.textTertiary)
            Spacer()
            Toggle("", isOn: Binding(
                get: { companionManager.advanceOnAnyClickEnabled },
                set: { companionManager.setAdvanceOnAnyClickEnabled($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(DS.Colors.accent)
            .scaleEffect(0.7)
        }
    }

    /// Compact button style used by the plan controls (Stop, Skip, Retry).
    /// Primary = accent fill; secondary = subtle background so destructive/
    /// neutral actions read at different weights.
    private struct PlanControlButtonStyle: ButtonStyle {
        let isPrimary: Bool

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundColor(isPrimary ? .white : DS.Colors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isPrimary
                              ? DS.Colors.accent.opacity(configuration.isPressed ? 0.7 : 1.0)
                              : Color.white.opacity(configuration.isPressed ? 0.14 : 0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
                )
                .onHover { isHovering in
                    if isHovering { NSCursor.pointingHand.push() }
                    else { NSCursor.pop() }
                }
        }
    }

    private func planChecklistRow(step: WorkflowStep, index: Int, isCurrent: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Numbered disc — highlighted if current, muted otherwise.
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(isCurrent ? .white : DS.Colors.textTertiary)
                .frame(width: 18, height: 18)
                .background(
                    Circle().fill(isCurrent ? DS.Colors.accent : Color.white.opacity(0.06))
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(step.label ?? "(unlabeled)")
                        .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                        .foregroundColor(isCurrent ? DS.Colors.textPrimary : DS.Colors.textSecondary)
                        .lineLimit(1)

                    // Subtle "looking for element..." indicator while the
                    // resolver is still polling AX/YOLO for this step.
                    if isCurrent && workflowRunner.isResolvingCurrentStep {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                    }
                }
                if !step.hint.isEmpty {
                    Text(step.hint)
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)
                        .lineLimit(2)
                }
            }
        }
    }

    /// Shown when the current step failed to resolve within the runner's
    /// budget. Gives the user a clear way out (retry / skip) instead of
    /// leaving the UI appearing stuck.
    private func planResolutionFailurePrompt(failureLabel: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.orange)

            Text("Can't find \"\(failureLabel)\"")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Colors.textSecondary)
                .lineLimit(1)

            Spacer()

            Button("Retry") {
                workflowRunner.retryCurrentStep()
            }
            .buttonStyle(PlanControlButtonStyle(isPrimary: false))

            Button("Skip") {
                workflowRunner.skipCurrentStep()
            }
            .buttonStyle(PlanControlButtonStyle(isPrimary: true))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 0.5)
        )
    }

    /// Stop + Skip controls — always visible while a plan is active so
    /// the user has a clean escape hatch without having to wait for a
    /// failure prompt or toggle debug settings.
    private var planControlsRow: some View {
        HStack(spacing: 8) {
            Button(role: .destructive) {
                workflowRunner.stop()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Stop")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .buttonStyle(PlanControlButtonStyle(isPrimary: false))

            Spacer()

            Button {
                workflowRunner.skipCurrentStep()
            } label: {
                HStack(spacing: 4) {
                    Text("Skip step")
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .semibold))
                }
            }
            .buttonStyle(PlanControlButtonStyle(isPrimary: true))
        }
    }

    // MARK: - Model Picker

    private var modelPickerRow: some View {
        VStack(spacing: 8) {
            voiceModePickerRow

            // Only show Claude model options when using the Claude pipeline —
            // Gemini Live has its own model baked in.
            if companionManager.voiceMode == .claudeAndElevenLabs {
                claudeModelPickerRow
            }
        }
        .padding(.vertical, 4)
    }

    private var voiceModePickerRow: some View {
        HStack {
            Text("Voice")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.Colors.textSecondary)

            Spacer()

            HStack(spacing: 0) {
                voiceModeOptionButton(label: "Claude", mode: .claudeAndElevenLabs)
                voiceModeOptionButton(label: "Gemini Live", mode: .geminiLive)
            }
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
            )
        }
    }

    private var claudeModelPickerRow: some View {
        HStack {
            Text("Model")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.Colors.textSecondary)

            Spacer()

            HStack(spacing: 0) {
                modelOptionButton(label: "Sonnet", modelID: "claude-sonnet-4-6")
                modelOptionButton(label: "Opus", modelID: "claude-opus-4-6")
            }
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
            )
        }
    }

    private func voiceModeOptionButton(label: String, mode: CompanionManager.VoiceMode) -> some View {
        let isSelected = companionManager.voiceMode == mode
        return Button(action: {
            companionManager.setVoiceMode(mode)
        }) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isSelected ? DS.Colors.textPrimary : DS.Colors.textTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private func modelOptionButton(label: String, modelID: String) -> some View {
        let isSelected = companionManager.selectedModel == modelID
        return Button(action: {
            companionManager.setSelectedModel(modelID)
        }) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isSelected ? DS.Colors.textPrimary : DS.Colors.textTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    // MARK: - Tutorial Section

    @State private var tutorialURLInput: String = ""
    @State private var tutorialStatus: String = ""
    @State private var isTutorialLoading: Bool = false

    private var tutorialSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tutorial")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Colors.textTertiary)

            HStack(spacing: 6) {
                TextField("Paste YouTube URL", text: $tutorialURLInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(DS.Colors.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(DS.Colors.surface2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
                    )

                Button(action: { startTutorial() }) {
                    Group {
                        if isTutorialLoading {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .frame(width: 28, height: 28)
                    .foregroundColor(tutorialURLInput.isEmpty ? DS.Colors.textTertiary : DS.Colors.textPrimary)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(tutorialURLInput.isEmpty ? DS.Colors.surface2 : DS.Colors.surface3)
                    )
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .disabled(tutorialURLInput.isEmpty || isTutorialLoading)
            }

            if !tutorialStatus.isEmpty {
                Text(tutorialStatus)
                    .font(.system(size: 10))
                    .foregroundColor(tutorialStatus.contains("Error") ? .red.opacity(0.7) : DS.Colors.textTertiary)
            }

            // Tutorial surface. The YouTube embed and the instruction
            // card occupy the same 16:9 frame and cross-fade as the
            // CompanionManager flips tutorialDisplayPhase between
            // .video (embed playing) and .instruction (transcript
            // chunk shown for the user to act on). Only renders inline
            // here when tutorialVideoMode == .menuBar — the cursor-
            // following mode renders the same swap in OverlayWindow
            // next to the cursor instead.
            if companionManager.isTutorialActive,
               companionManager.tutorialVideoMode == .menuBar,
               let embedController = companionManager.tutorialEmbedController,
               let videoID = companionManager.activeTutorialVideoID {
                tutorialSwapSurface(videoID: videoID, controller: embedController)
                tutorialControlsRow
            }

            tutorialVideoModeToggleRow
        }
    }

    /// Row of compact tutorial controls under the swap surface:
    /// Replay current chunk · Play/Pause · Skip · Stop. Bigger and
    /// more discoverable than the hotkeys (which still work in
    /// parallel), and works in both menu-bar and cursor-following
    /// modes — when the panel is open the user has both options.
    private var tutorialControlsRow: some View {
        HStack(spacing: 6) {
            tutorialIconButton(systemImage: "backward.fill", help: "Replay this chunk") {
                companionManager.replayCurrentTutorialChunk()
            }
            tutorialIconButton(
                systemImage: companionManager.isTutorialPaused ? "play.fill" : "pause.fill",
                help: companionManager.isTutorialPaused ? "Resume" : "Pause"
            ) {
                companionManager.toggleTutorialPause()
            }
            tutorialIconButton(systemImage: "forward.fill", help: "Skip ahead") {
                companionManager.skipTutorialChunk()
            }
            Spacer()
            tutorialIconButton(systemImage: "stop.fill", help: "Stop", isDestructive: true) {
                companionManager.stopTutorial()
            }
        }
        .padding(.top, 4)
    }

    private func tutorialIconButton(
        systemImage: String,
        help: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isDestructive ? .red.opacity(0.85) : DS.Colors.textPrimary)
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help(help)
    }

    /// Lets the user choose where the tutorial swap surface renders:
    /// inside this menu bar panel (default) or as a chip following
    /// the cursor.
    private var tutorialVideoModeToggleRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.Colors.textTertiary)
            Text("Video plays")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Colors.textTertiary)
            Spacer()
            HStack(spacing: 0) {
                tutorialVideoModeOptionButton(label: "Menu Bar", mode: .menuBar)
                tutorialVideoModeOptionButton(label: "Cursor", mode: .cursorFollowing)
            }
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
            )
        }
        .padding(.top, 4)
    }

    private func tutorialVideoModeOptionButton(
        label: String,
        mode: CompanionManager.TutorialVideoMode
    ) -> some View {
        let isSelected = companionManager.tutorialVideoMode == mode
        return Button(action: {
            companionManager.setTutorialVideoMode(mode)
        }) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isSelected ? .white : DS.Colors.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isSelected ? DS.Colors.accent : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    /// Stacks the YouTube embed and the instruction card in the same
    /// 16:9 area and cross-fades them based on tutorialDisplayPhase.
    /// The embed stays mounted in both phases (just opacity-toggled)
    /// so we don't lose player state between swaps.
    ///
    /// Note: The panel content is 320pt wide minus 16pt of horizontal
    /// padding on each side = 288pt available. The embed used to use
    /// `.aspectRatio(.fit)` which collapsed to its (zero) intrinsic
    /// size on first layout — explicit `.frame(maxWidth: .infinity,
    /// minHeight:...)` forces a real size from the moment the WKWebView
    /// loads, so the IFrame Player initializes at the right dimensions
    /// and doesn't render tiny.
    private func tutorialSwapSurface(videoID: String, controller: YouTubeEmbedController) -> some View {
        ZStack {
            YouTubeEmbedView(videoID: videoID, controller: controller)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .opacity(companionManager.tutorialDisplayPhase == .video ? 1 : 0)
                .allowsHitTesting(companionManager.tutorialDisplayPhase == .video)

            tutorialInstructionCard
                .opacity(companionManager.tutorialDisplayPhase == .instruction ? 1 : 0)
                .allowsHitTesting(companionManager.tutorialDisplayPhase == .instruction)
        }
        .frame(maxWidth: .infinity, minHeight: 162, idealHeight: 162)
    }

    /// The card shown in place of the embed during the .instruction
    /// phase. Shows the raw transcript text instantly; if Gemini's
    /// `/tutorial-chunk` response lands within the swap window, the
    /// text upgrades to a tight imperative ("Click File → New") and
    /// the cursor flies to the named element on the user's app.
    private var tutorialInstructionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DS.Colors.accent)
                Text("Your turn")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.Colors.textSecondary)
                Spacer()
                if companionManager.isTutorialInstructionLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.45)
                        .frame(width: 12, height: 12)
                }
            }

            Text(companionManager.tutorialInstructionText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Colors.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(6)

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DS.Colors.accent.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DS.Colors.accent.opacity(0.35), lineWidth: 0.8)
        )
    }

    private func startTutorial() {
        let urlString = tutorialURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else { return }
        tutorialStatus = ""
        companionManager.startTutorial(youtubeURL: urlString)
    }

    // MARK: - Feedback Button

    private var feedbackButton: some View {
        Button(action: {
            if let url = URL(string: "https://x.com/milindlabs") {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack(spacing: 5) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 10))
                Text("Feedback")
                    .font(.system(size: 11))
            }
            .foregroundColor(DS.Colors.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                feedbackButton

                #if DEBUG
                footerButton("Dev", systemImage: "wrench", toggled: showDevTools) {
                    showDevTools.toggle()
                }
                #endif

                Spacer()

                footerButton("Quit", systemImage: "power") {
                    NSApp.terminate(nil)
                }
            }

            #if DEBUG
            if showDevTools {
                devToolsSection
                    .padding(.top, 8)
            }
            #endif
        }
    }

    private func footerButton(
        _ title: String,
        systemImage: String,
        toggled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 11))
            }
            .foregroundColor(toggled ? DS.Colors.textSecondary : DS.Colors.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    // MARK: - Dev Tools (DEBUG only)

    #if DEBUG
    @State private var showDevTools: Bool = false

    private var devToolsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            devToolRow("Detection Overlay", systemImage: "square.grid.3x3") {
                companionManager.showDetectionOverlay.toggle()
                if companionManager.showDetectionOverlay {
                    companionManager.startDetectionOverlayFeeding()
                } else {
                    NativeElementDetector.shared.stopLiveFeeding()
                }
                NotificationCenter.default.post(name: .tipTourDismissPanel, object: nil)
            } trailing: {
                Text(companionManager.showDetectionOverlay ? "On" : "Off")
                    .foregroundColor(companionManager.showDetectionOverlay ? DS.Colors.textSecondary : DS.Colors.textTertiary)
            }

            devToolRow("Test Cursor Flight", systemImage: "arrow.up.right") {
                let s = NSScreen.main!
                companionManager.detectedElementScreenLocation = CGPoint(x: s.frame.midX, y: s.frame.midY)
                companionManager.detectedElementDisplayFrame = s.frame
                companionManager.detectedElementBubbleText = "Test"
                NotificationCenter.default.post(name: .tipTourDismissPanel, object: nil)
            }

            devToolRow("Reset All", systemImage: "xmark.circle", destructive: true) {
                companionManager.clearDetectedElementLocation()
                companionManager.onboardingPromptText = ""
                companionManager.onboardingPromptOpacity = 0.0
                companionManager.showOnboardingPrompt = false
                companionManager.stopTutorial()
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(DS.Colors.surface1)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
                )
        )
    }

    private var devToolDivider: some View {
        Rectangle()
            .fill(DS.Colors.borderSubtle)
            .frame(height: 0.5)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
    }

    private func devToolRow(
        _ title: String,
        systemImage: String,
        destructive: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder trailing: () -> some View = { EmptyView() }
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                    .foregroundColor(destructive ? .red.opacity(0.7) : DS.Colors.textTertiary)
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(destructive ? .red.opacity(0.7) : DS.Colors.textSecondary)

                Spacer()

                trailing()
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(DevToolRowButtonStyle())
        .pointerCursor()
    }

    #endif

    // MARK: - Visual Helpers

    #if DEBUG
    /// macOS-native menu row hover style — subtle background highlight on hover.
    private struct DevToolRowButtonStyle: ButtonStyle {
        @State private var isHovered = false

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(configuration.isPressed
                              ? DS.Colors.surface4
                              : isHovered ? DS.Colors.surface3 : Color.clear)
                )
                .onHover { isHovered = $0 }
        }
    }
    #endif

    // MARK: -

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

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
