import Foundation
import Combine
import AVFoundation
import SwiftUI
import UIKit

class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var session = AVCaptureSession()
    @Published var capturedImage: UIImage? = nil
    @Published var isFrozen: Bool = false {
        didSet { _isFrozenAtomic = isFrozen }
    }
    // Safe to read from videoQueue — mirrors isFrozen without @Published main-thread requirement
    private var _isFrozenAtomic: Bool = false

    private let output = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var photoCompletion: ((UIImage?) -> Void)?

    var cvPixelBufferHandler: ((CVPixelBuffer) -> Void)?

    override init() {
        super.init()
    }

    func start() {
        checkPermissions()
    }

    private func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async { self?.setupCamera() }
                }
            }
        default:
            break
        }
    }

    func setupCamera() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }

        // Live video for Vision pass-through
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if session.canAddOutput(output) { session.addOutput(output) }

        // Photo output for still capture
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }

        session.commitConfiguration()
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }

    // MARK: - Capture Photo
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        photoCompletion = completion
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - Reset to live view
    func retake() {
        capturedImage = nil
        isFrozen = false
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Use _isFrozenAtomic — reading @Published isFrozen from a background queue is a data race
        guard !_isFrozenAtomic, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        cvPixelBufferHandler?(pixelBuffer)
    }
}

// MARK: - Photo Delegate
extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            photoCompletion?(nil)
            return
        }
        DispatchQueue.main.async {
            self.capturedImage = image
            self.isFrozen = true
            self.photoCompletion?(image)
        }
    }
}

// MARK: - Camera Preview (live)
class VideoPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraManager: CameraManager

    func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.backgroundColor = .black
        view.videoPreviewLayer.session = cameraManager.session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: VideoPreviewView, context: Context) {}
}
