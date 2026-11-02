import SwiftUI

/// Камера на весь экран: только ×, снимаем подряд. Снимок → «Подписываем…» → подпись, отмена последнего тостом.
struct CameraView: View {
    let store: PlacesStore
    let placeId: UUID
    /// «Досканировать страницы» из карточки документа: каждый снимок листа — новая страница этого документа.
    var appendTo: Item? = nil
    @Environment(\.dismiss) private var dismiss
    // Документы (03.11.2026): лист в кадре определяется сам; снимок листа → страница PDF.
    @State private var detector = DocDetector.shared
    @State private var forcePhoto = false
    @State private var docItemId: UUID? = nil
    @State private var docPages = 0
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
                CameraPreview(session: CameraModel.shared.session, fullScreen: true).ignoresSafeArea()
                    .overlay { if !forcePhoto { DocQuadOverlay(quad: detector.isDocument ? detector.quad : nil).ignoresSafeArea() } }
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
                    }.buttonStyle(PrimaryButtonStyle(fill: .white, ink: Theme.dark)).padding(.horizontal, 60)
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
                docChip.padding(.top, 10)
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
        .onAppear {
            CameraModel.shared.detectDocuments = true
            if let appendTo { docItemId = appendTo.id; docPages = appendTo.docPages ?? 0 }
        }
        .onDisappear { CameraModel.shared.detectDocuments = false; detector.reset() }
        .onChange(of: detector.isDocument) { _, doc in if !doc && docItemId == nil { forcePhoto = false } }
        .animation(.snappy, value: detector.isDocument)
        .task {
            granted = await CameraModel.requestAccess()
            // Слой превью общий и уже идёт (CameraPreview); здесь только зум.
            if granted == true { zoom = 1; zoomAtPinchStart = 1; CameraModel.shared.setZoom(1) }
        }
        .animation(.snappy, value: toast)
    }

    /// Подсказка сверху: лист в кадре → «Документ → PDF · Это фото»; идёт документ → «Стр. N · Новый документ».
    @ViewBuilder private var docChip: some View {
        let inDoc = docItemId != nil
        if (detector.isDocument && !forcePhoto) || inDoc {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.fill")
                Text(inDoc ? "Стр. \(docPages + 1) этого PDF" : "Документ → PDF").font(.system(size: 14, weight: .semibold))
                if appendTo == nil {
                    Button(inDoc ? "Новый документ" : "Это фото") {
                        if inDoc { docItemId = nil; docPages = 0 } else { forcePhoto = true }
                    }
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(Color(hex: 0xFFD60A))
                }
            }
            .foregroundStyle(.white).padding(.horizontal, 14).frame(height: 36)
            .background(.black.opacity(0.6), in: Capsule())
            .transition(.opacity)
        }
    }

    private func shoot() async {
        busy = true
        withAnimation(.easeOut(duration: 0.08)) { flash = true }
        defer { busy = false }
        do {
            let data = try await CameraModel.shared.capture()
            withAnimation(.easeIn(duration: 0.15)) { flash = false }
            guard let image = UIImage(data: data) else { return }
            // Лист в кадре (или досканируем документ) — выравниваем и кладём страницей в PDF.
            let wantDoc = !forcePhoto && (detector.isDocument || docItemId != nil)
            forcePhoto = false
            if wantDoc {
                if let page = await DocScanner.extractPage(from: image) { try await addPage(page); return }
                if appendTo != nil {
                    toast = Toast(text: "Лист не найден — наведите камеру на страницу", undo: false)
                    try? await Task.sleep(for: .seconds(2)); toast = nil; return
                }
            }
            docItemId = nil; docPages = 0          // обычное фото завершает документ
            let id = UUID()
            // Сейф: фото не покидает устройство в открытом виде — подписи не распознаём, байты шифруем (ТЗ §10а).
            let safe = store.isSafe(placeId)
            toast = Toast(text: safe ? "Сохраняем…" : "Подписываем…", undo: false)
            guard let saved = PhotoStore.save(image, for: id, encrypted: safe) else { return }
            let caption = safe ? "Без названия" : await Captioner.caption(image)
            try await store.addItem(to: placeId, title: caption, source: safe ? .user : .ai, id: id)
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

    /// Страница документа: первая — создаёт вещь (фото = первая страница, подпись по тексту), следующие — дописывают PDF.
    private func addPage(_ page: UIImage) async throws {
        let safe = store.isSafe(placeId)
        guard let jpeg = DocScanner.pageJPEG(page) else { return }
        if let target = docItemId {
            guard let r = DocStore.append(jpeg, to: target, encrypted: safe) else { return }
            docPages = r.pages
            try await store.updateDocument(target, pages: r.pages)
            toast = Toast(text: "Документ · \(r.pages) стр.", undo: false)
            Task.detached { await DocStore.upload(target, pdf: r.pdf, pages: r.pages, store: store) }
            try? await Task.sleep(for: .seconds(1.5)); if toast?.text == "Документ · \(r.pages) стр." { toast = nil }
            return
        }
        let id = UUID()
        toast = Toast(text: "Сохраняем документ…", undo: false)
        guard let saved = PhotoStore.save(page, for: id, encrypted: safe) else { return }
        // Сейф: текст не распознаём (ТЗ §10а), подпись — вручную.
        let title = safe ? "Документ" : (await DocScanner.titleSuggestions(page).first ?? "Документ")
        try await store.addItem(to: placeId, title: title, source: safe ? .user : .ai, id: id)
        guard let r = DocStore.append(jpeg, to: id, encrypted: safe) else { return }
        try await store.updateDocument(id, pages: r.pages)
        docItemId = id; docPages = r.pages
        shots += 1; lastItem = id
        withAnimation(.snappy) { lastThumb = UIImage(data: saved.thumb) }
        toast = Toast(text: "\(title) · 1 стр.", undo: true)
        Task.detached {
            await PhotoStore.upload(id, photo: saved.photo, thumb: saved.thumb, store: store)
            await DocStore.upload(id, pdf: r.pdf, pages: r.pages, store: store)
        }
        try? await Task.sleep(for: .seconds(3))
        if lastItem == id, toast?.undo == true { toast = nil }
    }

    private func undo() async {
        guard let id = lastItem else { return }
        if docItemId == id { docItemId = nil; docPages = 0 }
        toast = nil; lastItem = nil; shots = max(0, shots - 1)
        if shots == 0 { lastThumb = nil }
        try? await store.deleteItem(id)
    }
}


/// Жёлтая рамка по краям найденного листа поверх превью (координаты устройства → слой превью).
private struct DocQuadOverlay: View {
    let quad: [CGPoint]?
    var body: some View {
        Canvas { ctx, _ in
            guard let quad, quad.count == 4 else { return }
            let layer = CameraModel.shared.previewView.previewLayer
            let pts = quad.map { layer.layerPointConverted(fromCaptureDevicePoint: $0) }
            var p = Path(); p.addLines(pts); p.closeSubpath()
            ctx.fill(p, with: .color(Color(hex: 0xFFD60A).opacity(0.16)))
            ctx.stroke(p, with: .color(Color(hex: 0xFFD60A)), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.12), value: quad?.first?.x)
    }
}
