import SwiftUI
import AVFoundation

/// Живое превью камеры. Используется и в маленькой плитке, и на полном экране.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var gravity: AVLayerVideoGravity = .resizeAspectFill

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        private var watchdog: Timer?
        private var badTicks = 0

        /// Раз в секунду проверяем, что сессия идёт. Признак `connection.isActive` не используем —
        /// он мигает при движении и вызывал ложные перезапуски (рывки превью).
        func startWatchdog() {
            watchdog?.invalidate()
            watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self, self.window != nil else { return }
                let ok = self.previewLayer.session?.isRunning == true && self.previewLayer.connection != nil
                self.badTicks = ok ? 0 : self.badTicks + 1
                if self.badTicks >= 3 { self.badTicks = 0; CameraModel.shared.restart() }
            }
        }
        override func willMove(toWindow newWindow: UIWindow?) {
            super.willMove(toWindow: newWindow)
            if newWindow == nil { watchdog?.invalidate(); watchdog = nil } else { startWatchdog() }
        }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = gravity
        v.backgroundColor = .black
        // Если слой не получил соединение с сессией (бывает, когда сессия уже идёт) — перезапускаем её.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if v.previewLayer.connection == nil { CameraModel.shared.restart() }
        }
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.videoGravity = gravity
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
