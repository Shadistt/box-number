import SwiftUI
import AVFoundation

/// Живое превью камеры. Используется и в маленькой плитке, и на полном экране.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var gravity: AVLayerVideoGravity = .resizeAspectFill

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = gravity
        v.backgroundColor = .black
        // По документации connection создаётся при привязке слоя к сессии; если его нет — перезапускаем сессию.
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
