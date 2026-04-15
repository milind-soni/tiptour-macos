import SwiftUI

/// Draws YOLO detection bounding boxes on the overlay.
/// Green boxes for all detected elements, coral for the highlighted one.
struct DetectionOverlayView: View {
    let elements: [[String: Any]]
    let highlightedLabel: String?
    let screenFrame: CGRect
    let imageSize: [Int]  // [width, height] of the screenshot sent to YOLO

    var body: some View {
        Canvas { context, size in
            // Scale YOLO pixel coords to overlay point coords
            let imgW = CGFloat(imageSize.count >= 2 ? imageSize[0] : 1512)
            let imgH = CGFloat(imageSize.count >= 2 ? imageSize[1] : 982)
            let scaleX = screenFrame.width / imgW
            let scaleY = screenFrame.height / imgH

            for element in elements {
                guard let bbox = element["bbox"] as? [Int], bbox.count == 4 else { continue }
                let label = element["label"] as? String ?? ""
                let conf = element["conf"] as? Double ?? 0

                // Convert pixel coords to overlay coords
                let x1 = CGFloat(bbox[0]) * scaleX
                let y1 = CGFloat(bbox[1]) * scaleY
                let x2 = CGFloat(bbox[2]) * scaleX
                let y2 = CGFloat(bbox[3]) * scaleY

                let rect = CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)

                let isHighlighted = highlightedLabel != nil && label.lowercased().contains(highlightedLabel!.lowercased())

                // Box
                let boxColor: Color = isHighlighted ? Color(hex: "#FF6B6B") : .green
                let boxOpacity: Double = isHighlighted ? 0.8 : 0.3
                let lineWidth: CGFloat = isHighlighted ? 2.5 : 1.0

                context.stroke(
                    Path(roundedRect: rect, cornerRadius: 3),
                    with: .color(boxColor.opacity(boxOpacity)),
                    lineWidth: lineWidth
                )

                // Fill for highlighted
                if isHighlighted {
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 3),
                        with: .color(boxColor.opacity(0.1))
                    )
                }

                // Label text (only for elements with labels or highlighted)
                if !label.isEmpty || isHighlighted {
                    let displayText = label.isEmpty ? "•" : label
                    let fontSize: CGFloat = isHighlighted ? 10 : 8

                    let textColor: Color = isHighlighted ? .white : .green.opacity(0.7)

                    // Background pill for label
                    let textSize = CGSize(width: CGFloat(displayText.count) * fontSize * 0.6 + 8, height: fontSize + 6)
                    let textRect = CGRect(
                        x: x1,
                        y: max(0, y1 - textSize.height - 2),
                        width: textSize.width,
                        height: textSize.height
                    )

                    if isHighlighted {
                        context.fill(
                            Path(roundedRect: textRect, cornerRadius: 3),
                            with: .color(boxColor.opacity(0.85))
                        )
                    } else {
                        context.fill(
                            Path(roundedRect: textRect, cornerRadius: 2),
                            with: .color(.black.opacity(0.5))
                        )
                    }

                    context.draw(
                        Text(displayText)
                            .font(.system(size: fontSize, weight: isHighlighted ? .bold : .regular, design: .monospaced))
                            .foregroundColor(textColor),
                        at: CGPoint(x: textRect.midX, y: textRect.midY)
                    )
                }

                // Confidence dot (small circle in corner)
                if conf > 0.5 && !isHighlighted {
                    let dotSize: CGFloat = 4
                    context.fill(
                        Path(ellipseIn: CGRect(x: x2 - dotSize, y: y1, width: dotSize, height: dotSize)),
                        with: .color(.green.opacity(0.5))
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.3), value: elements.count)
    }
}
