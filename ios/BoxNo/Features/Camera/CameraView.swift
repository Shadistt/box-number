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
    @State private var busy = false

    struct Toast: Equatable { var text: String; var undo: Bool }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if granted == true {
                CameraPreview(session: CameraModel.shared.session).ignoresSafeArea()
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
                Button { Task { await shoot() } } label: {
                    ZStack {
                        Circle().strokeBorder(.white, lineWidth: 4).frame(width: 78, height: 78)
                        Circle().fill(.white).frame(width: 64, height: 64).scaleEffect(busy ? 0.85 : 1)
                    }
                }
                .disabled(granted != true || busy)
                .padding(.bottom, 36)
            }
        }
        .statusBarHidden()
        .task {
            granted = await CameraModel.requestAccess()
            // Полный экран всегда поднимает сессию заново: так второй слой превью гарантированно получает кадры.
            if granted == true { CameraModel.shared.restart() }
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
        try? await store.deleteItem(id)
    }
}
