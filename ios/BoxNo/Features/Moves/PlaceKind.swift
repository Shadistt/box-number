import SwiftUI

/// Типы мест — как в enum place_kind базы и в макете TypeIcons.
enum PlaceKind: String, Codable, CaseIterable, Identifiable {
    case box, folder, container, suitcase, bag, wardrobe, large, safe, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .box: "Коробка"
        case .folder: "Папка"
        case .container: "Контейнер"
        case .suitcase: "Чемодан или сумка"
        case .bag: "Мешок или пакет"
        case .wardrobe: "Кофр для одежды"
        case .large: "Крупный предмет"
        case .safe: "Сейф"
        case .custom: "Свой вариант"
        }
    }

    /// Короткое имя для фильтров и подписей: «Коробка · 14 вещей»
    var short: String {
        switch self {
        case .suitcase: "Чемодан"
        case .bag: "Мешок"
        case .wardrobe: "Кофр"
        case .large: "Предмет"
        case .custom: "Своё"
        default: title
        }
    }

    var symbol: String {
        switch self {
        case .box: "shippingbox"
        case .folder: "folder"
        case .container: "archivebox"
        case .suitcase: "suitcase"
        case .bag: "bag"
        case .wardrobe: "hanger"
        case .large: "sofa"
        case .safe: "lock.fill"
        case .custom: "pencil.and.outline"
        }
    }

    /// Чем подписываем новое место: «Коробка № 3», «Папка № 3»
    var numberLabel: String { self == .custom ? "Место" : short }

    /// Сейф: содержимое зашифровано на устройстве, подписи только вручную, делиться нельзя (ТЗ §10а).
    var isSafe: Bool { self == .safe }
}
