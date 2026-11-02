import SwiftUI

/// Единицы веса в описи (02.11.2026): кг, г, фунты, унции. В базе вес всегда в килограммах;
/// выбранная единица — общая настройка приложения (по умолчанию — фунты для США, иначе кг).
enum WeightUnit: String, CaseIterable, Identifiable {
    case kg, g, lb, oz
    var id: String { rawValue }
    var title: String { switch self { case .kg: "кг"; case .g: "г"; case .lb: "lb"; case .oz: "oz" } }
    var name: String { switch self { case .kg: "Килограммы"; case .g: "Граммы"; case .lb: "Фунты (lb)"; case .oz: "Унции (oz)" } }
    /// Сколько килограммов в одной единице.
    var kg: Double { switch self { case .kg: 1; case .g: 0.001; case .lb: 0.45359237; case .oz: 0.028349523125 } }

    private static let key = "weight_unit"
    static var current: WeightUnit {
        get {
            if let s = UserDefaults.standard.string(forKey: key), let u = WeightUnit(rawValue: s) { return u }
            return Locale.current.measurementSystem == .us ? .lb : .kg
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    func show(_ kgValue: Double?) -> String {
        guard let kgValue else { return "" }
        return (kgValue / kg).formatted(.number.precision(.fractionLength(0...(self == .g ? 0 : 2))).grouping(.never))
    }
    func summary(_ kgValue: Double) -> String { show(kgValue) + " " + title }
}

/// Валюты описи: частые + валюта региона телефона. Хранится у каждой вещи/места (value_currency).
enum InventoryCurrency {
    static var list: [String] {
        var l = ["EUR", "USD", "GBP", "UAH", "PLN", "CZK", "CHF"]
        if let c = Locale.current.currency?.identifier, !l.contains(c) { l.insert(c, at: 0) }
        return l
    }
    static func name(_ code: String) -> String {
        let n = Locale.current.localizedString(forCurrencyCode: code) ?? code
        return "\(code) · \(n)"
    }
}

/// Кнопка-выпадашка единицы рядом с полем: «кг ⌄». Видно, что единицу можно сменить.
struct UnitMenuButton<Option: Hashable>: View {
    let title: String
    let options: [Option]
    let label: (Option) -> String
    let selected: Option
    let enabled: Bool
    let onPick: (Option) -> Void

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { o in
                Button { onPick(o) } label: {
                    if o == selected { Label(label(o), systemImage: "checkmark") } else { Text(label(o)) }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(enabled ? Theme.ink : Theme.muted)
            .padding(.horizontal, 9).frame(minWidth: 52, minHeight: 34)
            .background(enabled ? Theme.fill : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .disabled(!enabled)
    }
}
