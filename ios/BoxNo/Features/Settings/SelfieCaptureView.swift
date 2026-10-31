import SwiftUI
import AVFoundation

/// Селфи для аватарки: своя фронтальная камера вместо системной (у той — рамка обрезки и незеркальный
/// предпросмотр «Использовать фото»). Паттерн Lyft / Airbnb (Mobbin): тёмный фон, круг, подсказка, затвор.
/// Превью и снимок зеркальные (isVideoMirrored на соединении вывода) — человек видит себя как в зеркале и получает то же.
struct SelfieCaptureView: View {
    let onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var cam = SelfieCamera()
    @State private var shot: UIImage? = nil
    @State private var busy = false
    @State private var denied = false

    var body: some View {
        GeometryReader { g in
            let d = min(g.size.width - 48, 360)
            ZStack {
                Color.black.ignoresSafeArea()
                if let shot {
                    Image(uiImage: shot).resizable().scaledToFill().frame(width: d, height: d).clipShape(Circle())
                } else if denied {
                    VStack(spacing: 12) {
                        Text("Нет доступа к камере").font(.headline).foregroundStyle(.white)
                        Button("Открыть настройки") {
                            if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                        }.buttonStyle(PrimaryButtonStyle(fill: .white, ink: Theme.ink)).padding(.horizontal, 60)
                    }
                } else {
                    SelfiePreview(session: cam.session).ignoresSafeArea()
                        // всё вне круга — затемнено, круг с белым кольцом
                        .overlay {
                            Rectangle().fill(.black.opacity(0.6))
                                .mask { Rectangle().overlay { Circle().frame(width: d, height: d).blendMode(.destinationOut) }.compositingGroup() }
                                .ignoresSafeArea()
                        }
                        .overlay { Circle().stroke(.white, lineWidth: 2).frame(width: d, height: d) }
                }

                VStack {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 44, height: 44).background(.white.opacity(0.15), in: Circle())
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.top, 8)
                    Spacer()
                    Text(shot == nil ? "Расположите лицо в круге" : "Так и оставим?")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 36).background(.black.opacity(0.55), in: Capsule())
                        .padding(.bottom, 24)
                    if let shot {
                        HStack(spacing: 12) {
                            Button("Переснять") { self.shot = nil; cam.start() }
                                .buttonStyle(PrimaryButtonStyle(fill: .white.opacity(0.15), ink: .white))
                            Button("Использовать") { onPick(shot); dismiss() }
                                .buttonStyle(PrimaryButtonStyle(fill: .white, ink: Theme.ink))
                        }
                        .padding(.horizontal, 24).padding(.bottom, 36)
                    } else {
                        Button { Task { await take() } } label: {
                            ZStack {
                                Circle().strokeBorder(.white, lineWidth: 4).frame(width: 78, height: 78)
                                Circle().fill(.white).frame(width: 64, height: 64).scaleEffect(busy ? 0.85 : 1)
                            }
                        }
                        .disabled(busy || denied).padding(.bottom, 36)
                    }
                }
            }
        }
        .statusBarHidden()
        .task {
            if await CameraModel.requestAccess() { cam.start() } else { denied = true }
        }
        .onDisappear { cam.stop() }
    }

    private func take() async {
        busy = true; defer { busy = false }
        if let img = try? await cam.capture() { withAnimation(.snappy) { shot = img }; cam.stop() }
    }
}

/// Превью фронтальной камеры: превью-соединение фронталки iOS зеркалит само.
private struct SelfiePreview: UIViewRepresentable {
    let session: AVCaptureSession
    final class V: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var layerP: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> V {
        let v = V(); v.layerP.session = session; v.layerP.videoGravity = .resizeAspectFill; v.backgroundColor = .black; return v
    }
    func updateUIView(_ uiView: V, context: Context) {}
}

/// Отдельная сессия фронтальной камеры (основная — задняя, для коробок; одновременно две камеры не нужны).
final class SelfieCamera: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "co.boxnumber.selfie")
    private let output = AVCapturePhotoOutput()
    private var configured = false
    private var pending: CheckedContinuation<UIImage, Error>?

    func start() {
        queue.async { [self] in
            if !configured { configure() }
            if configured && !session.isRunning { session.startRunning() }
        }
    }
    func stop() { queue.async { [self] in if session.isRunning { session.stopRunning() } } }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input), session.canAddOutput(output) else { session.commitConfiguration(); return }
        session.addInput(input)
        session.addOutput(output)
        // Снимок зеркальный, как превью (по документации: для фото-вывода — через EXIF, UIImage его учитывает).
        if let c = output.connection(with: .video), c.isVideoMirroringSupported {
            c.automaticallyAdjustsVideoMirroring = false
            c.isVideoMirrored = true
        }
        session.commitConfiguration()
        configured = true
    }

    func capture() async throws -> UIImage {
        try await withCheckedThrowingContinuation { cont in
            queue.async { [self] in
                guard configured, session.isRunning else { cont.resume(throwing: CameraModel.CameraError.unavailable); return }
                pending = cont
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                output.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let cont = pending; pending = nil
        if let error { cont?.resume(throwing: error); return }
        guard let data = photo.fileDataRepresentation(), let img = UIImage(data: data) else {
            cont?.resume(throwing: CameraModel.CameraError.noData); return
        }
        cont?.resume(returning: img)
    }
}
