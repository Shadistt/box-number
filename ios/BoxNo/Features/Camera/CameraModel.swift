import AVFoundation
import UIKit

/// Одна сессия камеры на приложение: её показывают и живая плитка в сетке, и полный экран.
final class CameraModel: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    static let shared = CameraModel()

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "co.boxnumber.camera")
    private let output = AVCapturePhotoOutput()
    private var configured = false
    private var device: AVCaptureDevice?
    private var pending: CheckedContinuation<Data, Error>?
    private var observers: [NSObjectProtocol] = []

    private override init() {
        super.init()
        // Штатные уведомления AVFoundation вместо опроса: ошибка сессии → перезапуск,
        // конец прерывания (звонок, другое приложение) → снова старт.
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: nil) { [weak self] n in
            print("camera runtime error:", n.userInfo?[AVCaptureSessionErrorKey] ?? "")
            self?.restart()
        })
        observers.append(nc.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: session, queue: nil) { [weak self] _ in
            self?.start()
        })
    }

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

    /// Не чаще раза в 5 секунд (перезапуск сам по себе даёт рывок превью) — кроме `force`: открытие полного экрана.
    /// Без force второе открытие камеры в течение 5 секунд оставалось чёрным: новый слой превью по документации
    /// начинает показывать кадры только после startRunning(), а перезапуск отбрасывался как «слишком частый».
    func restart(force: Bool = false) {
        queue.async { [self] in
            guard force || Date().timeIntervalSince(lastRestart) > 5 else { return }
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
        self.device = device
        output.maxPhotoQualityPrioritization = .balanced
        session.commitConfiguration()
        configured = true
    }

    /// Зум: по документации — только между lockForConfiguration/unlock, в пределах min…maxAvailableVideoZoomFactor.
    /// Ограничиваем 10×: дальше картинка только апскейлится.
    func setZoom(_ factor: CGFloat) {
        queue.async { [self] in
            guard let device else { return }
            let z = min(max(factor, device.minAvailableVideoZoomFactor), min(device.maxAvailableVideoZoomFactor, 10))
            do { try device.lockForConfiguration(); device.videoZoomFactor = z; device.unlockForConfiguration() }
            catch { print("zoom:", error) }
        }
    }
    var zoom: CGFloat { device?.videoZoomFactor ?? 1 }

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
