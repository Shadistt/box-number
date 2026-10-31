import SwiftUI
import AVFoundation
import Contacts
import Photos
import UserNotifications

/// Настройки → Разрешения: что приложению разрешено, что — нет; недостающее можно дать здесь.
/// Просим разрешения по-прежнему только там, где они нужны; этот экран — обзор и «догнать».
struct PermissionsView: View {
    @State private var camera = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var contacts = CNContactStore.authorizationStatus(for: .contacts)
    @State private var notifications: UNAuthorizationStatus = .notDetermined
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Просим доступ только там, где он нужен. Здесь видно, что уже разрешено, и можно дать недостающее.")
                    .font(.subheadline).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                SettingsCard {
                    row("Камера", "camera.fill", "Снимать вещи и коробки", status: cameraStatus) {
                        if camera == .notDetermined { _ = await AVCaptureDevice.requestAccess(for: .video); refresh() } else { openSettings() }
                    }
                    Divider().padding(.leading, 68)
                    row("Фото", "photo.on.rectangle", "Выбор из галереи — через системное окно, разрешение не нужно", status: .notNeeded) {}
                    Divider().padding(.leading, 68)
                    row("Контакты", "person.crop.circle", "Выбор через окно iOS — видим только выбранных, разрешение не нужно", status: .notNeeded) {}
                    Divider().padding(.leading, 68)
                    row("Уведомления", "bell.badge", "Приглашения и общие места (скоро)", status: notifStatus) {
                        if notifications == .notDetermined { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]); refresh() } else { openSettings() }
                    }
                }
                Text("Геопозиция понадобится позже — для Посылок.").font(.footnote).foregroundStyle(Theme.muted).padding(.horizontal, 4)
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle("Разрешения").navigationBarTitleDisplayMode(.inline)
        .task { refresh() }
        .onChange(of: scenePhase) { _, p in if p == .active { refresh() } }   // вернулись из Настроек iOS — перечитать
    }

    enum Status { case granted, denied, notAsked, notNeeded
        var title: String { switch self { case .granted: "Разрешено"; case .denied: "Запрещено"; case .notAsked: "Не запрошено"; case .notNeeded: "Не нужно" } }
        var color: Color { switch self { case .granted: Color(hex: 0x3C8A4A); case .denied: .red; case .notAsked: Theme.muted; case .notNeeded: Theme.muted } }
    }
    private var cameraStatus: Status { switch camera { case .authorized: .granted; case .notDetermined: .notAsked; default: .denied } }
    private var contactsStatus: Status { switch contacts { case .authorized: .granted; case .notDetermined: .notAsked; default: .denied } }   // .limited (iOS 18) намеренно не используем — таргет iOS 17
    private var notifStatus: Status { switch notifications { case .authorized, .provisional, .ephemeral: .granted; case .notDetermined: .notAsked; default: .denied } }
    private var contactsSub: String { "Выбор из контактов — через системное окно (без разрешения). Полный доступ пригодится для подсказок" }

    private func row(_ title: String, _ symbol: String, _ sub: String, status: Status, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).frame(width: 40, height: 40).background(Theme.fill, in: Circle()).foregroundStyle(Theme.ink)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text(sub).font(.footnote).foregroundStyle(Theme.muted)
                }
                Spacer()
                Text(status.title).font(.footnote.weight(.semibold)).foregroundStyle(status.color)
                if status == .denied || status == .notAsked { Chevron() }
            }
            .padding(12).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(status == .granted || status == .notNeeded)
    }

    private func refresh() {
        camera = AVCaptureDevice.authorizationStatus(for: .video)
        contacts = CNContactStore.authorizationStatus(for: .contacts)
        UNUserNotificationCenter.current().getNotificationSettings { s in Task { @MainActor in notifications = s.authorizationStatus } }
    }
    private func openSettings() { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
}
