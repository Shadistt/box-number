import SwiftUI

/// Камера на весь экран: только ×, снимаем подряд. Снимок → «Подписываем…» → подпись, отмена последнего тостом.
struct CameraView: View {
    let store: PlacesStore
    let placeId: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var granted: Bool? = nil
    @State private var flash = false
    @State private var toast: Toast? = nil
    @State private var lastItem: UUID? = nil
    @State private var shots = 0
    @State private var lastThumb: UIImage? = nil
    @State private var busy = false
    @State private var zoom: CGFloat = 1
    @State private var zoomAtPinchStart: CGFloat = 1

    struct Toast: Equatable { var text: String; var undo: Bool }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if granted == true {
                CameraPreview(session: CameraModel.shared.session, restartOnAttach: true).ignoresSafeArea()
                    // Щипок — зум как в системной камере (MagnifyGesture, iOS 17).
                    .gesture(MagnifyGesture()
                        .onChanged { v in
                            let z = min(max(zoomAtPinchStart * v.magnification, 1), 10)
                            zoom = z; CameraModel.shared.setZoom(z)
                        }
                        .onEnded { _ in zoomAtPinchStart = zoom })
            } else if granted == false {
                VStack(spacing: 12) {
                    Text("Нет доступа к камере").font(.headline).foregroundStyle(.white)
                    Button("Открыть настройки") {
                        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                    }.buttonStyle(PrimaryButtonStyle(fill: .white, ink: Theme.ink)).padding(.horizontal, 60)
                }
            }
            if flash { Color.white.ignoresSafeArea().transition(.opacity) }

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 44, height: 44).background(.black.opacity(0.45), in: Circle())
                    }
                    Spacer()
                    // Чип зума: тап переключает 1× / 2×, при щипке показывает текущее значение.
                    Button {
                        let z: CGFloat = zoom < 1.5 ? 2 : 1
                        withAnimation(.snappy) { zoom = z }; zoomAtPinchStart = z; CameraModel.shared.setZoom(z)
                    } label: {
                        Text(zoom == zoom.rounded() ? "\(Int(zoom))×" : String(format: "%.1f×", zoom))
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(zoom > 1 ? Theme.accent : .white)
                            .frame(minWidth: 40).frame(height: 32).padding(.horizontal, 6).background(.black.opacity(0.45), in: Capsule())
                    }
                    if shots > 0 {
                        Text("+\(shots)").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 12).frame(height: 32).background(.black.opacity(0.45), in: Capsule())
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8)
                Spacer()
                if let toast {
                    HStack(spacing: 12) {
                        if !toast.undo { ProgressView().tint(.white) }
                        Text(toast.text).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Spacer()
                        if toast.undo {
                            Button("Отменить") { Task { await undo() } }.font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.horizontal, 16).frame(height: 52).foregroundStyle(.white)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 16).padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                ZStack {
                    Button { Task { await shoot() } } label: {
                        ZStack {
                            Circle().strokeBorder(.white, lineWidth: 4).frame(width: 78, height: 78)
                            Circle().fill(.white).frame(width: 64, height: 64).scaleEffect(busy ? 0.85 : 1)
                        }
                    }
                    .disabled(granted != true || busy)
                    HStack {
                        if let lastThumb {
                            Button { dismiss() } label: {
                                Image(uiImage: lastThumb).resizable().scaledToFill()
                                    .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.8), lineWidth: 1.5))
                                    .overlay(alignment: .topTrailing) {
                                        Text("\(shots)").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.ink)
                                            .padding(.horizontal, 6).frame(height: 20).background(Theme.accent, in: Capsule())
                                            .offset(x: 8, y: -8)
                                    }
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                        Spacer()
                    }
                    .padding(.leading, 28)
                }
                .padding(.bottom, 36)
            }
        }
        .statusBarHidden()
        .task {
            granted = await CameraModel.requestAccess()
            // Перезапуск сессии делает сам CameraPreview после привязки слоя (restartOnAttach); здесь только зум.
            if granted == true { zoom = 1; zoomAtPinchStart = 1; CameraModel.shared.setZoom(1) }
        }
        .animation(.snappy, value: toast)
    }

    private func shoot() async {
        busy = true
        withAnimation(.easeOut(duration: 0.08)) { flash = true }
        defer { busy = false }
        do {
            let data = try await CameraModel.shared.capture()
            withAnimation(.easeIn(duration: 0.15)) { flash = false }
            guard let image = UIImage(data: data) else { return }
            let id = UUID()
            toast = Toast(text: "Подписываем…", undo: false)
            guard let saved = PhotoStore.save(image, for: id) else { return }
            let caption = await Captioner.caption(image)
            try await store.addItem(to: placeId, title: caption, source: .ai, id: id)
            shots += 1; lastItem = id
            withAnimation(.snappy) { lastThumb = UIImage(data: saved.thumb) }
            toast = Toast(text: caption, undo: true)
            Task.detached { await PhotoStore.upload(id, photo: saved.photo, thumb: saved.thumb, store: store) }
            try? await Task.sleep(for: .seconds(3))
            if lastItem == id, toast?.undo == true { toast = nil }
        } catch {
            flash = false
            toast = Toast(text: error.localizedDescription, undo: false)
            try? await Task.sleep(for: .seconds(2)); toast = nil
        }
    }

    private func undo() async {
        guard let id = lastItem else { return }
        toast = nil; lastItem = nil; shots = max(0, shots - 1)
        if shots == 0 { lastThumb = nil }
        try? await store.deleteItem(id)
    }
}
