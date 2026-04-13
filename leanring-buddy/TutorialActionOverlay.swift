import SwiftUI

/// Overlay animations for tutorial actions (keyboard, scroll, etc.)
/// Rendered in the main overlay window alongside the cursor.
struct TutorialActionOverlay: View {
    @ObservedObject var companionManager: CompanionManager
    let cursorPosition: CGPoint

    var body: some View {
        if companionManager.isTutorialActive {
            // Keyboard — key cap appears NEXT TO the arrow (arrow stays visible)
            if companionManager.tutorialActionType == "keyboard" {
                KeyboardActionView(keyLabel: companionManager.tutorialKeyLabel)
                    .position(x: cursorPosition.x + 40, y: cursorPosition.y - 20)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: companionManager.tutorialKeyLabel)
            }
        }
    }
}

// MARK: - Keyboard Action Animation

struct KeyboardActionView: View {
    let keyLabel: String
    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 4) {
            // Key cap
            Text(keyLabel)
                .font(.system(size: keyLabel.count > 3 ? 11 : 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(minWidth: 36, minHeight: 36)
                .padding(.horizontal, keyLabel.count > 3 ? 8 : 4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#3a3a3c"), Color(hex: "#2c2c2e")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .black.opacity(0.5), radius: 0, y: isPressed ? 1 : 3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
                .offset(y: isPressed ? 2 : 0)
                .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .onAppear {
            // Animate key press
            withAnimation(.easeIn(duration: 0.15).delay(0.3)) {
                isPressed = true
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.55)) {
                isPressed = false
            }

            // Repeat the press animation
            Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                withAnimation(.easeIn(duration: 0.15)) {
                    isPressed = true
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.25)) {
                    isPressed = false
                }
            }
        }
    }
}


