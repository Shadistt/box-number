import Foundation
import Supabase
import Realtime

/// Живые обновления (Supabase Realtime, RLS фильтрует события на сервере).
/// Главный: мне выдали/закрыли доступ к переезду или месту, добавили в семью, чужой переезд изменился — список перезагружается.
/// Экран мест: кто-то из семьи добавил/переименовал место или вещь — экран перезагружается.
/// События сыплются пачками, поэтому перезагрузка одна на все изменения за 0,6 с.
/// Вызовы — из `.task` экрана: при уходе с экрана задача отменяется и канал снимается.
enum LiveUpdates {
    /// Главный экран. Работает, пока задача жива.
    static func watchHome(userId: UUID, onChange: @escaping @MainActor () async -> Void) async {
        let ch = supabase.realtimeV2.channel("home:\(userId.uuidString)")
        let me = "user_id=eq.\(userId.uuidString)"
        let bump = Debouncer(onChange)
        var subs: [RealtimeSubscription] = []
        subs.append(ch.onPostgresChange(AnyAction.self, schema: "public", table: "move_access", filter: me) { _ in bump.fire() })
        subs.append(ch.onPostgresChange(AnyAction.self, schema: "public", table: "place_access", filter: me) { _ in bump.fire() })
        subs.append(ch.onPostgresChange(AnyAction.self, schema: "public", table: "family_members", filter: me) { _ in bump.fire() })
        subs.append(ch.onPostgresChange(AnyAction.self, schema: "public", table: "moves") { _ in bump.fire() })
        await run(ch, subs)
    }

    /// Экран мест одного переезда.
    static func watchMove(_ moveId: UUID, onChange: @escaping @MainActor () async -> Void) async {
        let ch = supabase.realtimeV2.channel("move:\(moveId.uuidString)")
        let mine = "move_id=eq.\(moveId.uuidString)"
        let bump = Debouncer(onChange)
        var subs: [RealtimeSubscription] = []
        subs.append(ch.onPostgresChange(AnyAction.self, schema: "public", table: "places", filter: mine) { _ in bump.fire() })
        subs.append(ch.onPostgresChange(AnyAction.self, schema: "public", table: "move_destinations", filter: mine) { _ in bump.fire() })
        // У вещей нет move_id — слушаем все видимые (RLS) и перезагружаем; лишние события редки.
        subs.append(ch.onPostgresChange(AnyAction.self, schema: "public", table: "items") { _ in bump.fire() })
        await run(ch, subs)
    }

    /// Подписаться и ждать отмены задачи; при отмене — снять канал.
    private static func run(_ ch: RealtimeChannelV2, _ subs: [RealtimeSubscription]) async {
        await ch.subscribe()
        await withTaskCancellationHandler {
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
        } onCancel: {
            Task { for s in subs { s.cancel() }; await supabase.realtimeV2.removeChannel(ch) }
        }
    }

    /// Несколько событий подряд → одна перезагрузка.
    final class Debouncer: @unchecked Sendable {
        private let action: @MainActor () async -> Void
        private var task: Task<Void, Never>?
        private let lock = NSLock()
        init(_ action: @escaping @MainActor () async -> Void) { self.action = action }
        func fire() {
            lock.lock(); defer { lock.unlock() }
            task?.cancel()
            task = Task { @MainActor [action] in
                try? await Task.sleep(for: .seconds(0.6))
                if !Task.isCancelled { await action() }
            }
        }
    }
}
