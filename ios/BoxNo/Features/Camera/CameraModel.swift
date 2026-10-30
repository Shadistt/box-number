import AVFoundation
import UIKit

/// Одна сессия камеры на приложение: её показывают и живая плитка в сетке, и полный экран.
final class CameraModel: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    static let shared = CameraModel()

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "co.boxnumber.camera")
    private let output = AVCapturePhotoOutput()
    private var configured = false
    private var pending: CheckedContinuation<Data, Error>?

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func start() {
        queue.async { [self] in
            if !configured { configure() }
            if configured && !session.isRunning { session.startRunning() }
        }
    }

    /// Перезапуск: нужен, когда к уже идущей сессии подключили новый слой превью и он не получил поток.
    private var lastRestart = Date.distantPast

    /// Не чаще раза в 5 секунд: перезапуск сам по себе даёт рывок превью.
    func restart() {
        queue.async { [self] in
            guard Date().timeIntervalSince(lastRestart) > 5 else { return }
            lastRestart = Date()
            if !configured { configure() }
            guard configured else { return }
            if session.isRunning { session.stopRunning() }
            session.startRunning()
        }
    }

    func stop() {
        queue.async { [self] in if session.isRunning { session.stopRunning() } }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration(); return
        }
        session.addInput(input)
        session.addOutput(output)
        output.maxPhotoQualityPrioritization = .balanced
        session.commitConfiguration()
        configured = true
    }

    /// Снимок → JPEG. Снимаем подряд, без «Готово».
    func capture() async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            queue.async { [self] in
                if !configured { configure() }
                if configured && !session.isRunning { session.startRunning() }
                guard configured, session.isRunning else { cont.resume(throwing: CameraError.unavailable); return }
                if let old = pending { old.resume(throwing: CameraError.busy) }
                pending = cont
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                settings.photoQualityPrioritization = .balanced
                output.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let cont = pending; pending = nil
        if let error { cont?.resume(throwing: error); return }
        guard let data = photo.fileDataRepresentation() else { cont?.resume(throwing: CameraError.noData); return }
        cont?.resume(returning: data)
    }

    enum CameraError: LocalizedError {
        case unavailable, noData, busy
        var errorDescription: String? {
            switch self {
            case .unavailable: "Камера недоступна"
            case .noData: "Снимок не получился"
            case .busy: "Подождите, предыдущий снимок ещё обрабатывается"
            }
        }
    }
}
