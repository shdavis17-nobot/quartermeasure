import Foundation
import Combine
import AVFoundation
import SwiftUI
import UIKit

class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var session = AVCaptureSession()
    @Published var isSessionRunning = false
    @Published var capturedImage: UIImage? = nil
    @Published var currentZoom: CGFloat = 1.0
    @Published var isFrozen: Bool = false {
        didSet { _isFrozenAtomic = isFrozen }
    }
    @Published var minZoom: CGFloat = 1.0
    @Published var maxZoom: CGFloat = 5.0

    private var _isFrozenAtomic: Bool = false
    private var videoDevice: AVCaptureDevice?
    private let output = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var photoCaptureCompletion: ((UIImage?) -> Void)?

    var cvPixelBufferHandler: ((CVPixelBuffer) -> Void)?

    override init() {
        super.init()
        setupCamera()
    }

    func setZoom(factor: CGFloat) {
        guard let device = videoDevice else { return }
        do {
            try device.lockForConfiguration()
            // CORRECTED: Use Device-level min/max instead of format-level range
            let minZ = device.minAvailableVideoZoomFactor
            let maxZ = min(8.0, device.maxAvailableVideoZoomFactor)
            let zoom = max(minZ, min(factor, maxZ))
            device.videoZoomFactor = zoom
            self.currentZoom = zoom
            device.unlockForConfiguration()
        } catch {
            print("[CameraManager] Zoom Error: \(error)")
        }
    }

    func setupCamera() {
        // High-sensitivity for 0.5x support on modern iPhones (Pro models)
        let deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: .back)
        
        // Prefer devices that actually support ultra-wide ranges (< 1.0)
        let captureDevice = discoverySession.devices.first(where: { $0.minAvailableVideoZoomFactor < 1.0 }) 
                            ?? discoverySession.devices.first(where: { $0.deviceType == .builtInTripleCamera })
                            ?? discoverySession.devices.first
        
        guard let device = captureDevice else {
            print("[CameraManager] No compatible back camera found")
            return 
        }
        self.videoDevice = device
        
        let minZ = device.minAvailableVideoZoomFactor
        let maxZ = min(15.0, device.maxAvailableVideoZoomFactor)
        
        DispatchQueue.main.async {
            self.minZoom = minZ
            self.maxZoom = maxZ
            print("[CameraManager] Hardware Range: \(minZ)x - \(maxZ)x")
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            session.sessionPreset = .photo
            if session.canAddInput(input) { session.addInput(input) }
            
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
            if session.canAddOutput(output) { session.addOutput(output) }

            if session.canAddOutput(photoOutput) { 
                session.addOutput(photoOutput) 
                photoOutput.maxPhotoQualityPrioritization = .balanced
            }
            session.commitConfiguration()
            
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
                DispatchQueue.main.async { self?.isSessionRunning = true }
            }
        } catch {
            print("[CameraManager] Error: \(error.localizedDescription)")
        }
    }

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        guard let connection = photoOutput.connection(with: .video), connection.isActive else {
            completion(nil)
            return
        }
        photoCaptureCompletion = completion
        let settings = AVCapturePhotoSettings()
        if connection.isVideoRotationAngleSupported(90.0) { connection.videoRotationAngle = 90.0 }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func retake() {
        DispatchQueue.main.async {
            self.capturedImage = nil
            self.isFrozen = false
            self.currentZoom = 1.0
            self.setZoom(factor: 1.0)
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !_isFrozenAtomic, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        cvPixelBufferHandler?(pixelBuffer)
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            photoCaptureCompletion?(nil)
            return
        }
        DispatchQueue.main.async {
            self.capturedImage = image
            self.isFrozen = true
            self.photoCaptureCompletion?(image)
            self.photoCaptureCompletion = nil
        }
    }
}

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
