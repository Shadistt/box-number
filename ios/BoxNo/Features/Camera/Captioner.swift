import Vision
import UIKit

/// AI-подпись на устройстве: классификация Vision + словарь на русский. Подпись всегда можно исправить.
enum Captioner {
    static func caption(_ image: UIImage) async -> String {
        guard let cg = image.cgImage else { return "Вещь" }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let req = VNClassifyImageRequest()
                let handler = VNImageRequestHandler(cgImage: cg, orientation: cgOrientation(image.imageOrientation))
                try? handler.perform([req])
                let results = (req.results ?? []).sorted { $0.confidence > $1.confidence }
                // Сначала то, что знаем по-русски; потом любое уверенное английское
                if let hit = results.first(where: { $0.confidence > 0.15 && ru[$0.identifier] != nil }) {
                    cont.resume(returning: ru[hit.identifier]!)
                } else if let hit = results.first(where: { $0.confidence > 0.4 }) {
                    cont.resume(returning: hit.identifier.replacingOccurrences(of: "_", with: " ").capitalized)
                } else {
                    cont.resume(returning: "Вещь")
                }
            }
        }
    }

    private static func cgOrientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    /// Идентификаторы VNClassifyImageRequest → русские подписи для домашних вещей.
    static let ru: [String: String] = [
        "mug": "Кружка", "cup": "Чашка", "coffee_cup": "Кофейная чашка", "teapot": "Чайник", "kettle": "Чайник",
        "plate": "Тарелка", "bowl": "Миска", "glass": "Стакан", "wine_glass": "Бокал", "bottle": "Бутылка",
        "pan": "Сковорода", "frying_pan": "Сковорода", "pot": "Кастрюля", "cooking_pot": "Кастрюля", "saucepan": "Кастрюля",
        "spoon": "Ложка", "fork": "Вилка", "knife": "Нож", "cutlery": "Столовые приборы", "cutting_board": "Разделочная доска",
        "toaster": "Тостер", "blender": "Блендер", "mixer": "Миксер", "microwave": "Микроволновка", "coffee_maker": "Кофеварка",
        "book": "Книга", "books": "Книги", "notebook": "Блокнот", "magazine": "Журнал", "document": "Документы", "paper": "Бумаги",
        "folder": "Папка", "envelope": "Конверт", "pen": "Ручка", "pencil": "Карандаш", "scissors": "Ножницы",
        "laptop": "Ноутбук", "computer": "Компьютер", "monitor": "Монитор", "keyboard": "Клавиатура", "mouse": "Мышь",
        "cable": "Кабель", "charger": "Зарядка", "headphones": "Наушники", "speaker": "Колонка", "camera": "Фотоаппарат",
        "phone": "Телефон", "mobile_phone": "Телефон", "tablet": "Планшет", "remote_control": "Пульт", "television": "Телевизор",
        "lamp": "Лампа", "table_lamp": "Настольная лампа", "light_bulb": "Лампочка", "candle": "Свеча", "clock": "Часы",
        "vase": "Ваза", "flower_pot": "Горшок с цветком", "plant": "Растение", "houseplant": "Комнатное растение", "picture_frame": "Рамка",
        "painting": "Картина", "mirror": "Зеркало", "pillow": "Подушка", "cushion": "Подушка", "blanket": "Плед",
        "towel": "Полотенце", "bedding": "Постельное бельё", "bed_sheet": "Простыня", "curtain": "Штора", "rug": "Ковёр",
        "shirt": "Рубашка", "t-shirt": "Футболка", "sweater": "Свитер", "jacket": "Куртка", "coat": "Пальто",
        "jeans": "Джинсы", "trousers": "Брюки", "dress": "Платье", "skirt": "Юбка", "shoe": "Обувь", "shoes": "Обувь",
        "sneaker": "Кроссовки", "boot": "Ботинки", "sandal": "Сандалии", "hat": "Шапка", "cap": "Кепка", "scarf": "Шарф",
        "glove": "Перчатки", "belt": "Ремень", "bag": "Сумка", "handbag": "Сумка", "backpack": "Рюкзак", "suitcase": "Чемодан",
        "umbrella": "Зонт", "sunglasses": "Очки", "glasses": "Очки", "watch": "Часы", "jewelry": "Украшения", "necklace": "Украшение",
        "toy": "Игрушка", "teddy_bear": "Плюшевый мишка", "doll": "Кукла", "ball": "Мяч", "puzzle": "Пазл", "board_game": "Настольная игра",
        "lego": "Конструктор", "guitar": "Гитара", "violin": "Скрипка", "piano": "Пианино", "drum": "Барабан",
        "hammer": "Молоток", "screwdriver": "Отвёртка", "wrench": "Ключ", "drill": "Дрель", "tool": "Инструмент", "toolbox": "Ящик с инструментами",
        "tape": "Скотч", "rope": "Верёвка", "box": "Коробка", "cardboard_box": "Коробка", "basket": "Корзина", "bucket": "Ведро",
        "iron": "Утюг", "hair_dryer": "Фен", "vacuum_cleaner": "Пылесос", "fan": "Вентилятор", "heater": "Обогреватель",
        "shampoo": "Шампунь", "soap": "Мыло", "toothbrush": "Зубная щётка", "perfume": "Духи", "cosmetics": "Косметика",
        "medicine": "Лекарства", "pill_bottle": "Лекарства", "first_aid_kit": "Аптечка",
        "chair": "Стул", "stool": "Табурет", "table": "Стол", "shelf": "Полка", "drawer": "Ящик", "cabinet": "Шкафчик",
        "bicycle": "Велосипед", "helmet": "Шлем", "skateboard": "Скейт", "ski": "Лыжи", "tent": "Палатка", "sleeping_bag": "Спальник",
        "dog": "Вещи собаки", "cat": "Вещи кошки", "food": "Еда", "snack": "Еда", "wine": "Вино", "beer": "Пиво",
        "cat_food": "Корм", "pet_food": "Корм", "leash": "Поводок", "printer": "Принтер", "router": "Роутер",
        "power_strip": "Удлинитель", "extension_cord": "Удлинитель", "battery": "Батарейки", "flashlight": "Фонарик"
    ]
}
