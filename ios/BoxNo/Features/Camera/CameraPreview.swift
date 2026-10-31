import SwiftUI
import AVFoundation

/// Живое превью камеры: ОДИН слой на приложение (CameraModel.previewView), который переезжает между плиткой
/// и полным экраном. Второй слой на той же сессии (подключение/перезапуск) давал чёрный экран и долгий старт
/// (сборки 83–89); с одним слоем сессия не перенастраивается вообще.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var gravity: AVLayerVideoGravity = .resizeAspectFill
    /// Полный экран забирает слой у плитки и не отдаёт, пока открыт (плитка в это время всё равно скрыта).
    var fullScreen = false

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    /// Контейнер: при появлении на экране «усыновляет» общий слой превью, если его не держит кто-то важнее.
    final class Container: UIView {
        var priority = 0
        var gravity: AVLayerVideoGravity = .resizeAspectFill
        private var observer: NSObjectProtocol?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            observer = NotificationCenter.default.addObserver(forName: CameraModel.previewReleased, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.adopt() }
            }
        }
        required init?(coder: NSCoder) { fatalError() }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

        override func didMoveToWindow() { super.didMoveToWindow(); if window != nil { adopt() } }
        override func layoutSubviews() { super.layoutSubviews(); subviews.first?.frame = bounds }

        func adopt() {
            guard window != nil else { return }
            let model = CameraModel.shared
            if let owner = model.previewOwner, owner !== self, owner.priority > priority { return }
            let v = model.previewView
            v.previewLayer.videoGravity = gravity
            if v.superview !== self { addSubview(v); v.frame = bounds }
            model.previewOwner = self
            model.start()
        }

        func release() {
            let model = CameraModel.shared
            guard model.previewOwner === self else { return }
            model.previewView.removeFromSuperview()
            model.previewOwner = nil
            NotificationCenter.default.post(name: CameraModel.previewReleased, object: nil)
        }
    }

    func makeUIView(context: Context) -> Container {
        let c = Container(frame: .zero)
        c.priority = fullScreen ? 1 : 0
        c.gravity = gravity
        return c
    }

    func updateUIView(_ uiView: Container, context: Context) {
        uiView.gravity = gravity
        uiView.adopt()
    }

    static func dismantleUIView(_ uiView: Container, coordinator: ()) {
        MainActor.assumeIsolated { uiView.release() }
    }
}

/// Живая плитка камеры — первая в сетке вещей (как в Telegram). Тап открывает полный экран.
struct CameraTile: View {
    let enabled: Bool
    let action: () -> Void
    @State private var granted = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if granted && enabled {
                    CameraPreview(session: CameraModel.shared.session)
                } else {
                    Color(hex: 0x2A2B30)
                }
                VStack(spacing: 6) {
                    Image(systemName: "camera.fill").font(.system(size: 26, weight: .semibold))
                    Text(enabled ? "Снять" : "Запаковано").font(.footnote.weight(.semibold))
                }
                .foregroundStyle(.white).shadow(radius: 4)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .task {
            granted = await CameraModel.requestAccess()
            if granted && enabled { CameraModel.shared.start() }
        }
    }
}
