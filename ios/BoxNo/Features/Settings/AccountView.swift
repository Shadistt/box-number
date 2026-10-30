import SwiftUI
import PhotosUI
import Supabase
import AuthenticationServices
import GoogleSignIn

/// Аккаунт (макеты Account / AccountNoPassword): аватар, имя, email, пароль, 2FA, Apple/Google.
struct AccountView: View {
    @State private var store = ProfileStore.shared
    @State private var first = ""
    @State private var last = ""
    @State private var saveTask: Task<Void, Never>?

    @State private var photoMenu = false
    @State private var selfie = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var showPicker = false
    @State private var carouselId: String?     // "photo" или id пресета — что по центру карусели

    @State private var passwordCard = false
    @State private var twoFACard = false
    @State private var unlinkProvider: String?
    @State private var error: String?
    @State private var busy = false
    @State private var appleLinker = AppleLinker()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                AvatarCarousel(store: store, selection: $carouselId, onPhotoTap: { photoMenu = true })
                Text(avatarCaption).font(.footnote).foregroundStyle(Theme.muted).padding(.bottom, 4)

                SectionTitle("Данные")
                SettingsCard {
                    FieldRow(label: "Имя", text: $first, placeholder: "Имя", contentType: .givenName)
                    Divider().padding(.leading, 16)
                    FieldRow(label: "Фамилия", text: $last, placeholder: "Фамилия", contentType: .familyName)
                    Divider().padding(.leading, 16)
                    NavigationLink { ChangeEmailView() } label: { LabeledRow(label: "Email", value: store.profile?.email ?? "") }
                    Divider().padding(.leading, 16)
                    Button { withAnimation(.snappy) { passwordCard = true } } label: {
                        LabeledRow(label: "Пароль", value: store.hasPassword ? "••••••••" : "Не задан", muted: !store.hasPassword)
                    }
                }

                SectionTitle("Защита")
                SettingsCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Двухфакторная защита").font(.system(size: 17, weight: .semibold))
                            Text("Код на email каждые 30 дней").font(.footnote).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(get: { store.profile?.twoFactor ?? false }, set: { _ in withAnimation(.snappy) { twoFACard = true } }))
                            .labelsHidden().tint(Theme.accent)
                    }
                    .padding(16)
                }

                SectionTitle("Способы входа")
                SettingsCard {
                    providerRow("Apple", symbol: "apple.logo", provider: "apple")
                    Divider().padding(.leading, 16)
                    providerRow("Google", symbol: "g.circle.fill", provider: "google")
                }
                if store.identities.count == 1, store.identity("email") == nil {
                    Text("Это единственный способ входа — его нельзя отвязать. Задайте пароль или привяжите другой.")
                        .font(.footnote).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle("Аккаунт").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            first = store.profile?.firstName ?? ""; last = store.profile?.lastName ?? ""
            carouselId = store.profile?.hasCustomAvatar == true ? "photo" : AvatarPreset.named(store.profile?.avatar ?? "").id
        }
        .onChange(of: first) { _, _ in scheduleSave() }
        .onChange(of: last) { _, _ in scheduleSave() }
        .onChange(of: carouselId) { _, id in
            // Остановились на аватарке — она и выбрана. Пустой слот «своё фото» выбором не считается.
            guard let id else { return }
            if id == "photo" { if store.profile?.photo != nil { Task { await store.setAvatar("photo") } } }
            else { Task { await store.setPreset(id) } }
        }
        .onDisappear { saveTask?.cancel(); Task { await saveNames() } }
        .confirmationDialog("Своё фото", isPresented: $photoMenu, titleVisibility: .hidden) {
            Button("Сделать селфи") { selfie = true }
            Button("Выбрать из фото") { showPicker = true }
            if store.profile?.photo != nil { Button("Удалить фото", role: .destructive) { Task { await store.deletePhoto(); carouselId = "box" } } }
            Button("Отмена", role: .cancel) {}
        }
        .confirmationDialog("Отвязать \(unlinkProvider == "apple" ? "Apple" : "Google")?",
                            isPresented: .init(get: { unlinkProvider != nil }, set: { if !$0 { unlinkProvider = nil } }), titleVisibility: .visible) {
            Button("Отвязать", role: .destructive) { if let p = unlinkProvider { Task { await unlink(p) } } }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Войти этим способом больше не получится, пока не привяжете снова.") }
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { await setPhoto(img) }
                pickerItem = nil
            }
        }
        .fullScreenCover(isPresented: $selfie) {
            SelfiePicker { img in if let img { Task { await setPhoto(img) } } }.ignoresSafeArea()
        }
        // Нижние карточки поверх этого же экрана (как «Запаковать»), а не системные sheet'ы со стопкой окон.
        .overlay { if passwordCard { BottomCard(isPresented: $passwordCard) { PasswordCard(close: { withAnimation(.snappy) { passwordCard = false } }) } } }
        .overlay { if twoFACard { BottomCard(isPresented: $twoFACard) { TwoFactorCard(close: { withAnimation(.snappy) { twoFACard = false } }) } } }
        .overlay { if busy { ProgressView().padding(20).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14)) } }
        .task { await store.loadIdentities() }
    }

    private var avatarCaption: String {
        if carouselId == "photo" { return store.profile?.photo != nil ? "Нажмите, чтобы изменить или удалить фото" : "Нажмите — селфи или фото из галереи" }
        return "Листайте или загрузите своё фото"
    }

    private func setPhoto(_ img: UIImage) async {
        busy = true; defer { busy = false }
        do { try await store.setPhoto(img); carouselId = "photo" } catch { self.error = "Не удалось загрузить фото. Попробуйте ещё раз." }
    }

    // MARK: имя

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { try? await Task.sleep(for: .seconds(1)); if !Task.isCancelled { await saveNames() } }
    }
    private func saveNames() async {
        let f = first.trimmingCharacters(in: .whitespaces), l = last.trimmingCharacters(in: .whitespaces)
        guard let p = store.profile, p.firstName != f || p.lastName != l else { return }
        await store.update(firstName: f, lastName: l)
    }

    // MARK: Apple / Google

    private func providerRow(_ title: String, symbol: String, provider: String) -> some View {
        let linked = store.identity(provider) != nil
        let last = linked && !store.canUnlinkProvider
        return HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                .frame(width: 40, height: 40).background(Theme.ink, in: Circle()).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 17, weight: .semibold))
                Text(linked ? (store.identityEmail(provider) ?? "Привязан") : "Не привязан").font(.footnote).foregroundStyle(Theme.muted)
            }
            Spacer()
            if last {
                // Последний способ входа: кнопки нет, пояснение под списком.
                Text("Единственный способ").font(.footnote).foregroundStyle(Theme.muted)
            } else {
                Button(linked ? "Отвязать" : "Привязать") {
                    if linked { unlinkProvider = provider } else { Task { await link(provider) } }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).frame(height: 36)
                .background(Color(hex: 0xE4E2DC), in: Capsule())
                .foregroundStyle(Theme.ink)
            }
        }
        .padding(16)
    }

    private func link(_ provider: String) async {
        busy = true; defer { busy = false }
        do {
            if provider == "apple" {
                let (token, nonce) = try await appleLinker.request()
                _ = try await supabase.auth.linkIdentityWithIdToken(credentials: .init(provider: .apple, idToken: token, nonce: nonce))
            } else {
                guard let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else { return }
                GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: AppConfig.googleClientID)
                let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: root)
                guard let idToken = result.user.idToken?.tokenString else { throw URLError(.userAuthenticationRequired) }
                _ = try await supabase.auth.linkIdentityWithIdToken(credentials: .init(provider: .google, idToken: idToken, accessToken: result.user.accessToken.tokenString))
            }
            await store.loadIdentities()
        } catch let e as GIDSignInError where e.code == .canceled {
        } catch AppleLinker.LinkError.canceled {
        } catch { self.error = "Не удалось привязать: \(error.localizedDescription)" }
    }

    private func unlink(_ provider: String) async {
        guard let identity = store.identity(provider) else { return }
        busy = true; defer { busy = false }
        do { try await supabase.auth.unlinkIdentity(identity); await store.loadIdentities() }
        catch { self.error = "Не удалось отвязать: \(error.localizedDescription)" }
    }
}

// MARK: - Карусель аватарок: активная по центру крупно, остальные мельче по бокам

struct AvatarCarousel: View {
    let store: ProfileStore
    @Binding var selection: String?
    let onPhotoTap: () -> Void
    private let big: CGFloat = 96

    var body: some View {
        GeometryReader { outer in
            let side = (outer.size.width - big) / 2
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    item("photo") {
                        ZStack {
                            if let img = store.avatarImage, store.profile?.photo != nil {
                                Image(uiImage: img).resizable().scaledToFill()
                            } else {
                                Color(hex: 0xE4E2DC)
                                Image(systemName: "camera.fill").font(.system(size: 30, weight: .semibold)).foregroundStyle(Color(hex: 0x4F5157))
                            }
                        }
                    }
                    .onTapGesture { if selection == "photo" { onPhotoTap() } else { withAnimation(.snappy) { selection = "photo" } } }
                    ForEach(AvatarPreset.all) { p in
                        item(p.id) {
                            ZStack {
                                p.color
                                Image(systemName: p.symbol).font(.system(size: 34, weight: .semibold)).foregroundStyle(.white)
                            }
                        }
                        .onTapGesture { withAnimation(.snappy) { selection = p.id } }
                        .accessibilityLabel(p.title)
                    }
                }
                .scrollTargetLayout()
            }
            .safeAreaPadding(.horizontal, side)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selection, anchor: .center)
        }
        .frame(height: big + 8)
    }

    /// Масштаб по расстоянию от центра экрана: в центре 1, у краёв 0.6.
    private func item<C: View>(_ id: String, @ViewBuilder content: () -> C) -> some View {
        GeometryReader { g in
            let mid = g.frame(in: .global).midX
            let screenMid = UIScreen.main.bounds.midX
            let k: CGFloat = min(1, abs(mid - screenMid) / (big + 12))
            let scale: CGFloat = 1 - 0.4 * k
            let alpha: Double = 1 - 0.35 * Double(k)
            content()
                .frame(width: big, height: big).clipShape(Circle())
                .overlay(Circle().stroke(Theme.ink, lineWidth: k < 0.3 ? 3 : 0))
                .scaleEffect(scale)
                .opacity(alpha)
        }
        .frame(width: big, height: big)
        .id(id)
        .contentShape(Circle())
    }
}

// MARK: - Строки

struct FieldRow: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var contentType: UITextContentType? = nil
    var body: some View {
        HStack(spacing: 12) {
            Text(label).font(.footnote).foregroundStyle(Theme.muted).frame(width: 72, alignment: .leading)
            TextField(placeholder, text: $text).font(.system(size: 17, weight: .semibold)).textContentType(contentType)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 16).frame(minHeight: 56)
    }
}

struct LabeledRow: View {
    let label: String
    let value: String
    var muted = false
    var body: some View {
        HStack(spacing: 12) {
            Text(label).font(.footnote).foregroundStyle(Theme.muted).frame(width: 72, alignment: .leading)
            Text(value).font(.system(size: 17, weight: .semibold)).foregroundStyle(muted ? Theme.muted : Theme.ink).lineLimit(1)
            Spacer()
            Chevron()
        }
        .padding(.horizontal, 16).frame(minHeight: 56).contentShape(Rectangle())
    }
}

// MARK: - Нижняя карточка поверх экрана (затемнение + белая карточка до низа)

struct BottomCard<Content: View>: View {
    @Binding var isPresented: Bool
    @ViewBuilder let content: Content
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.18).ignoresSafeArea()
                .onTapGesture { withAnimation(.snappy) { isPresented = false } }
            VStack(alignment: .leading, spacing: 14) {
                Capsule().fill(Theme.line).frame(width: 36, height: 5).frame(maxWidth: .infinity)
                content
            }
            .padding(20).padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22).fill(.white)
                    .shadow(color: .black.opacity(0.12), radius: 20, y: -4)
                    .ignoresSafeArea(edges: .bottom)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Селфи (фронтальная камера, обрезка в квадрат, зеркально — как в превью)

struct SelfiePicker: UIViewControllerRepresentable {
    let onPick: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        if p.sourceType == .camera, UIImagePickerController.isCameraDeviceAvailable(.front) { p.cameraDevice = .front }
        p.allowsEditing = true
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: SelfiePicker
        init(_ parent: SelfiePicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            var img = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            // Фронтальная камера отдаёт незеркальный кадр, а в превью человек видел себя как в зеркале —
            // отзеркаливаем, чтобы фото выглядело привычно.
            if picker.sourceType == .camera, picker.cameraDevice == .front, let i = img { img = i.withHorizontallyFlippedOrientation() }
            parent.onPick(img); parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.onPick(nil); parent.dismiss() }
    }
}

// MARK: - Apple: id_token для привязки

@MainActor
final class AppleLinker: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    enum LinkError: Error { case canceled, noToken }
    private var cont: CheckedContinuation<(token: String, nonce: String), Error>?
    private var nonce = ""

    func request() async throws -> (token: String, nonce: String) {
        nonce = AuthView.randomNonce()
        let req = ASAuthorizationAppleIDProvider().createRequest()
        req.requestedScopes = [.email, .fullName]
        req.nonce = AuthView.sha256(nonce)
        let c = ASAuthorizationController(authorizationRequests: [req])
        c.delegate = self; c.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { cont in self.cont = cont; c.performRequests() }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = cred.identityToken, let token = String(data: data, encoding: .utf8) else {
            cont?.resume(throwing: LinkError.noToken); cont = nil; return
        }
        cont?.resume(returning: (token: token, nonce: nonce)); cont = nil
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if (error as? ASAuthorizationError)?.code == .canceled { cont?.resume(throwing: LinkError.canceled) } else { cont?.resume(throwing: error) }
        cont = nil
    }
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? UIWindow()
    }
}
