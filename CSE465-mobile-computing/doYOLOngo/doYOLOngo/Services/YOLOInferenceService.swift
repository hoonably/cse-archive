import Foundation
import TensorFlowLite
import CoreVideo
import CoreMedia
import UIKit
import Combine

final class YOLOInferenceService: ObservableObject {

    // MARK: - Config
    static let inputSize: Int = 640
    static let confidenceThreshold: Float = 0.35  //! Confidence Threshold
    
    // MARK: - State
    private(set) var precision: Precision
    private var interpreter: Interpreter?
    private(set) var modelSizeMB: Double = 0
    private let ciContext = CIContext()

    init(precision: Precision = .fp32) {
        self.precision = precision
        loadModel(precision: precision)
    }

    func switchPrecision(_ newPrecision: Precision) {
        guard newPrecision != precision else { return }
        self.precision = newPrecision
        loadModel(precision: newPrecision)
    }

    private func loadModel(precision: Precision) {
        guard let modelPath = Bundle.main.path(forResource: precision.fileName, ofType: "tflite") else {
            interpreter = nil
            return
        }
        do {
            var options = Interpreter.Options()
            options.threadCount = 4
            interpreter = try Interpreter(modelPath: modelPath, options: options)
            try interpreter?.allocateTensors()
            print("[YOLO] Model Loaded: \(precision.rawValue) (Post-processed format)")
        } catch {
            print("[YOLO] Load Error: \(error)")
            interpreter = nil
        }
    }

    func run(sampleBuffer: CMSampleBuffer, targetClass: String?) -> (detections: [Detection], latencyMs: Double) {
        guard let interpreter, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return ([], 0) }
        let start = Date()
        guard let inputData = preprocess(pixelBuffer) else { return ([], 0) }
        
        do {
            try interpreter.copy(inputData, toInputAt: 0)
            try interpreter.invoke()
        } catch {
            print("[YOLO] Inference Error: \(error)")
            return ([], 0)
        }
        
        let latency = Date().timeIntervalSince(start) * 1000
        let detections = postprocess(interpreter: interpreter, targetClass: targetClass)
        return (detections, latency)
    }

    private func preprocess(_ pixelBuffer: CVPixelBuffer) -> Data? {
        let size = CGFloat(Self.inputSize)
        let srcW = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let srcH = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        
        // 1. Center Crop with pixel rounding
        let side = min(srcW, srcH)
        let originX = floor((srcW - side) / 2)
        let originY = floor((srcH - side) / 2)
        let cropRect = CGRect(x: originX, y: originY, width: side, height: side)
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let scale = size / side
        
        // 2. Precise transformation
        let transform = CGAffineTransform(translationX: -originX, y: -originY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
        
        let transformed = ciImage.cropped(to: cropRect).transformed(by: transform)

        var out: CVPixelBuffer?
        // Use a consistent pixel format and ensure IOSurface backing for speed
        let attrs = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        CVPixelBufferCreate(nil, Int(size), Int(size), kCVPixelFormatType_32BGRA, attrs, &out)
        guard let buffer = out else { return nil }
        
        // Use explicit bounds to prevent edge bleeding
        ciContext.render(transformed, 
                         to: buffer, 
                         bounds: CGRect(x: 0, y: 0, width: size, height: size), 
                         colorSpace: CGColorSpaceCreateDeviceRGB())

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let ptr = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        
        var floats = [Float32](repeating: 0, count: 640 * 640 * 3)
        for y in 0..<640 {
            for x in 0..<640 {
                let off = y * stride + x * 4
                let i = (y * 640 + x) * 3
                floats[i + 0] = Float32(ptr[off + 2]) / 255.0 // R
                floats[i + 1] = Float32(ptr[off + 1]) / 255.0 // G
                floats[i + 2] = Float32(ptr[off + 0]) / 255.0 // B
            }
        }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private func postprocess(interpreter: Interpreter, targetClass: String?) -> [Detection] {
        guard let outputTensor = try? interpreter.output(at: 0) else { return [] }
        let shape = outputTensor.shape.dimensions // [1, 300, 6]
        let floats = outputTensor.data.withUnsafeBytes { Array($0.bindMemory(to: Float32.self)) }

        var detections: [Detection] = []
        let numDetections = shape[1] // 300
        
        for i in 0..<numDetections {
            let offset = i * 6
            // Format: [xmin, ymin, xmax, ymax, score, classIdx]
            let xmin = CGFloat(floats[offset + 0])
            let ymin = CGFloat(floats[offset + 1])
            let xmax = CGFloat(floats[offset + 2])
            let ymax = CGFloat(floats[offset + 3])
            let score = floats[offset + 4]
            let classIdx = Int(floats[offset + 5])
            
            if score < Self.confidenceThreshold { continue }
            
            // Create Rect according to coordinate order
            let rect = CGRect(x: xmin, y: ymin, width: xmax - xmin, height: ymax - ymin)
            let name = classIdx < cocoClasses.count ? cocoClasses[classIdx] : "unknown"
            
            detections.append(Detection(
                classIndex: classIdx,
                className: name,
                confidence: score,
                boundingBox: rect,
                isTarget: targetClass == name
            ))
        }
        
        return detections
    }
}
