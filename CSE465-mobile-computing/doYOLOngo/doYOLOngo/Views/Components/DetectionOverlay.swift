import SwiftUI

/// Bounding-box + label overlay drawn on top of the camera preview.
/// All coordinates are normalised (0…1) and mapped to the view's actual size.
struct DetectionOverlay: View {
    let detections: [Detection]
    let frameSize: CGSize

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ForEach(detections) { det in
                let rect = CGRect(
                    x: det.boundingBox.minX * w,
                    y: det.boundingBox.minY * h,
                    width: det.boundingBox.width * w,
                    height: det.boundingBox.height * h
                )
                let color: Color = det.isTarget ? .boxTarget : .boxOther

                // Bounding box
                Rectangle()
                    .stroke(color, lineWidth: 2)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                // Label chip
                Text("\(det.className) \(Int(det.confidence * 100))%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(color)
                    .cornerRadius(5)
                    .position(x: rect.minX + 50, y: max(rect.minY - 10, 10))
            }
        }
    }
}

#Preview {
    DetectionOverlay(
        detections: [
            Detection(classIndex: 63, className: "laptop", confidence: 0.86,
                      boundingBox: CGRect(x: 0.45, y: 0.15, width: 0.35, height: 0.3), isTarget: true),
            Detection(classIndex: 66, className: "keyboard", confidence: 0.72,
                      boundingBox: CGRect(x: 0.1, y: 0.55, width: 0.3, height: 0.2), isTarget: false)
        ],
        frameSize: CGSize(width: 375, height: 280)
    )
    .frame(width: 375, height: 280)
    .background(Color.black.opacity(0.8))
}
