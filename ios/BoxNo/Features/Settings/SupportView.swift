import SwiftUI
import PhotosUI
import Supabase

/// Поддержка (макет Support): тема, сообщение, до 3 скриншотов, галочка «данные об устройстве».
/// «Отправить» активна только при заполненных теме и сообщении.
struct SupportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = ProfileStore.shared
    @State private var subject = ""
    @State private var message = ""
    @State private var shots: [UIImage] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var withDevice = true
    @State private var busy = false
    @State private var sent = false
    @State private var error: String?
    private let max = 3

    private var missing: String? {
        let s = subject.trimmingCharacters(in: .whitespaces).isEmpty, m = message.trimmingCharacters(in: .whitespaces).isEmpty
        return s && m ? "Заполните тему и сообщение" : s ? "Заполните тему" : m ? "Заполните сообщение" : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if sent {
                    VStack(spacing: 14) {
                        Image(systemName: "checkmark").font(.system(size: 30, weight: .bold))
                            .frame(width: 72, height: 72).background(Theme.ink, in: Circle()).foregroundStyle(.white)
                        Text("Отправили").font(.system(size: 26, weight: .heavy))
                        Text("Ответим на \(store.profile?.email ?? ""), обычно в течение дня.")
                            .multilineTextAlignment(.center).foregroundStyle(Theme.muted)
                        Button("Готово") { dismiss() }.buttonStyle(PrimaryButtonStyle()).padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    Text("Живой человек ответит на \(store.profile?.email ?? ""), обычно в течение дня.")
                        .font(.subheadline).foregroundStyle(Theme.muted).padding(.horizontal, 4)

                    SettingsCard {
                        TextField("Тема", text: $subject).font(.system(size: 17, weight: .semibold))
                            .padding(.horizontal, 16).frame(height: 56)
                        Divider().padding(.leading, 16)
                        TextField("Сообщение", text: $message, axis: .vertical).lineLimit(5...12).font(.system(size: 17))
                            .padding(16)
                    }

                    SectionTitle("Скриншоты")
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(shots.isEmpty ? "необязательно · до \(max)" : "\(shots.count) из \(max)")
                                .font(.footnote).foregroundStyle(Theme.muted)
                            HStack(spacing: 10) {
                                ForEach(Array(shots.enumerated()), id: \.offset) { i, img in
                                    Image(uiImage: img).resizable().scaledToFill()
                                        .frame(width: 72, height: 110).clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(alignment: .topTrailing) {
                                            Button { shots.remove(at: i) } label: {
                                                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                                                    .frame(width: 22, height: 22).background(Theme.ink, in: Circle()).foregroundStyle(.white)
                                            }.offset(x: 6, y: -6)
                                        }
                                        .accessibilityLabel("Скриншот \(i + 1)")
                                }
                                if shots.count < max {
                                    PhotosPicker(selection: $pickerItems, maxSelectionCount: max - shots.count, matching: .screenshots) {
                                        VStack(spacing: 6) {
                                            Image(systemName: "plus").font(.system(size: 18, weight: .bold))
                                            Text(shots.isEmpty ? "Приложить" : "Ещё").font(.caption.weight(.semibold))
                                        }
                                        .frame(width: 72, height: 110)
                                        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 10))
                                        .foregroundStyle(Theme.ink)
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }

                    SettingsCard {
                        Toggle(isOn: $withDevice) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Приложить данные об устройстве").font(.system(size: 17, weight: .semibold))
                                Text("Версия приложения и iOS — так быстрее разберёмся").font(.footnote).foregroundStyle(Theme.muted)
                            }
                        }
                        .tint(Theme.accent).padding(16)
                    }

                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    Button { Task { await send() } } label: {
                        if busy { ProgressView().tint(.white) } else { Text("Отправить") }
                    }
                    .buttonStyle(PrimaryButtonStyle()).disabled(missing != nil || busy).opacity(missing == nil ? 1 : 0.5)
                    if let missing { Text(missing).font(.footnote).foregroundStyle(Theme.muted).frame(maxWidth: .infinity) }
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle("Поддержка").navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if shots.count >= max { break }
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { shots.append(img) }
                }
                pickerItems = []
            }
        }
    }

    private func send() async {
        busy = true; defer { busy = false }; error = nil
        struct Body: Encodable { var subject: String; var message: String; var device: String?; var screenshots: [String] }
        let device = withDevice ? Self.deviceInfo : nil
        let shotsB64 = shots.compactMap { $0.resized(maxSide: 1600).jpegData(compressionQuality: 0.75)?.base64EncodedString() }
        do {
            try await supabase.functions.invoke("support-ticket", options: .init(body: Body(subject: subject, message: message, device: device, screenshots: shotsB64)))
            sent = true
        } catch { self.error = "Не удалось отправить. Проверьте сеть и попробуйте ещё раз." }
    }

    static var deviceInfo: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "Box Nº \(v) (\(b)) · \(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)"
    }
}
