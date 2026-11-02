import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Подсказки подписи места по вещам внутри (02.11.2026). Всё на устройстве — подписи никуда не уходят:
/// iOS 26+ с Apple Intelligence и поддержкой языка — системная модель; иначе — словарь категорий.
/// Показываем только при ≥ 3 подписанных вещах; у сейфа подсказок нет (вызывающий не зовёт).
enum PlaceTitleSuggester {
    static let minItems = 3

    static func suggest(itemTitles: [String]) async -> [String] {
        let titles = itemTitles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "Вещь" }
        guard titles.count >= minItems else { return [] }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), let ai = await modelSuggestions(titles), !ai.isEmpty { return ai }
        #endif
        return dictionarySuggestions(titles)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    @Generable
    struct Names {
        @Guide(description: "Три коротких названия для коробки при переезде, 1–3 слова каждое, по-русски, с заглавной буквы, без кавычек и номеров.", .count(3))
        var names: [String]
    }

    @available(iOS 26.0, *)
    private static func modelSuggestions(_ titles: [String]) async -> [String]? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability, model.supportsLocale() else { return nil }
        let session = LanguageModelSession(instructions: "Ты помогаешь подписать коробку при переезде. Отвечай по-русски.")
        let list = titles.prefix(40).joined(separator: ", ")
        do {
            let r = try await session.respond(to: "В коробке лежит: \(list). Предложи три общих названия для этой коробки, например «Кухня», «Зимние вещи», «Книги».", generating: Names.self)
            return Captioner.dedupe(r.content.names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "«»\"."))) }.filter { !$0.isEmpty && $0.count <= 30 })
        } catch {
            return nil
        }
    }
    #endif

    // MARK: - словарь (без Apple Intelligence)

    private struct Category { let names: [String]; let stems: [String] }
    private static let categories: [Category] = [
        .init(names: ["Кухня", "Посуда", "Кухонные принадлежности"],
              stems: ["кружк", "чашк", "тарел", "чайник", "кастрюл", "сковород", "нож", "ложк", "вилк", "стакан", "бокал", "миск", "посуд", "блендер", "тостер", "кофевар", "кофемаш", "термос", "разделоч", "поднос", "контейнер", "микроволн", "ковш", "половник", "специ", "дуршлаг", "тёрк", "терк"]),
        .init(names: ["Одежда", "Вещи", "Гардероб"],
              stems: ["свитер", "кофт", "футболк", "рубашк", "брюк", "джинс", "плать", "юбк", "костюм", "пиджак", "бель", "худи", "халат", "шорт", "майк", "блузк"]),
        .init(names: ["Зимние вещи", "Верхняя одежда", "Одежда"],
              stems: ["куртк", "пальто", "пуховик", "шарф", "шапк", "перчат", "варежк", "шуб", "свитер"]),
        .init(names: ["Обувь"], stems: ["обув", "кроссов", "ботин", "сапог", "туфл", "тапк", "тапоч", "кед", "сандал", "шлёпан", "шлепан"]),
        .init(names: ["Книги", "Книги и журналы", "Документы"], stems: ["книг", "журнал", "тетрад", "альбом", "документ", "папк", "блокнот"]),
        .init(names: ["Электроника", "Техника", "Гаджеты"], stems: ["ноутбук", "компьютер", "клавиатур", "мыш", "наушник", "телефон", "планшет", "зарядк", "кабел", "провод", "монитор", "колонк", "роутер", "камер", "приставк", "пульт", "часы умн", "фотоаппарат"]),
        .init(names: ["Ванная", "Косметика и гигиена"], stems: ["полотенц", "шампун", "мыл", "зубн", "фен", "косметик", "крем", "бритв", "расчёск", "расческ", "гель"]),
        .init(names: ["Постельное", "Спальня", "Текстиль"], stems: ["подушк", "одеял", "плед", "простын", "постел", "покрывал", "наволоч", "матрас", "кроват"]),
        .init(names: ["Игрушки", "Детские вещи"], stems: ["игрушк", "кукл", "мяч", "конструктор", "лего", "пазл", "машинк"]),
        .init(names: ["Инструменты"], stems: ["молот", "отвёртк", "отвертк", "дрель", "шуруповёрт", "шуруповерт", "плоскогуб", "рулетк", "пил", "инструмент", "уровень"]),
        .init(names: ["Декор", "Интерьер"], stems: ["ваз", "картин", "рамк", "свеч", "ламп", "светильник", "зеркал", "растени", "цвет", "статуэтк", "ковёр", "ковер"]),
        .init(names: ["Мебель"], stems: ["кресл", "стул", "стол", "диван", "полк", "тумб", "шкаф"]),
        .init(names: ["Спорт", "Спортивные вещи"], stems: ["гантел", "коврик", "велосипед", "ролик", "лыж", "ракетк", "гир", "скакалк"]),
    ]

    static func dictionarySuggestions(_ titles: [String]) -> [String] {
        let lower = titles.map { $0.lowercased() }
        let scored = categories.map { c in (c, lower.filter { t in c.stems.contains { t.contains($0) } }.count) }
            .filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        guard let top = scored.first, top.1 * 3 >= titles.count else {
            // Вещи разные: подсказки ничего не добавят — полосы не будет.
            return []
        }
        var out = top.0.names
        if scored.count > 1, scored[1].1 >= 2, let a = top.0.names.first, let b = scored[1].0.names.first, a != b {
            out.insert("\(a) и \(b.lowercased())", at: min(1, out.count))
        }
        return Array(Captioner.dedupe(out).prefix(3))
    }
}
