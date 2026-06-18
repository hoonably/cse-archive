import AVFoundation
import UIKit
import Combine

/// Manages AVCaptureSession lifecycle and delivers frames via a publisher.
final class CameraService: NSObject, ObservableObject {

    // MARK: - Public
    let session = AVCaptureSession()
    /// Emits every captured sample buffer on a background queue.
    let framePublisher = PassthroughSubject<CMSampleBuffer, Never>()
    @Published var isRunning: Bool = false
    @Published var permissionStatus: AVAuthorizationStatus = .notDetermined

    // MARK: - Private
    private let sessionQueue = DispatchQueue(label: "cam.sessionQueue", qos: .userInitiated)
    private var videoOutput = AVCaptureVideoDataOutput()

    // MARK: - Setup

    func requestPermissionAndConfigure() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        permissionStatus = status
        switch status {
        case .authorized:
            sessionQueue.async { self.configureSession() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.permissionStatus = granted ? .authorized : .denied
                }
                if granted {
                    self.sessionQueue.async { self.configureSession() }
                }
            }
        default:
            break   // denied / restricted — UI handles this
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        // Set to high quality preset (HD 1280x720)
        session.sessionPreset = .hd1280x720

        // Input
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                  for: .video,
                                                  position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        // Output
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "cam.outputQueue", qos: .userInitiated))
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            // Portrait orientation
            if let connection = videoOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            }
        }

        session.commitConfiguration()
    }

    // MARK: - Start / Stop

    func start() {
        sessionQueue.async {
            if !self.session.isRunning {
                self.session.startRunning()
                DispatchQueue.main.async { self.isRunning = true }
            }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
                DispatchQueue.main.async { self.isRunning = false }
            }
        }
    }

    // MARK: - Flashlight Control
    func setFlashlight(on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if on {
                try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
        } catch {
            print("Torch could not be used")
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        framePublisher.send(sampleBuffer)
    }
}
