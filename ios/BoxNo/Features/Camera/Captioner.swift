import Vision
import UIKit

/// AI-подпись на устройстве: классификация Vision + словарь на русский. Подпись всегда можно исправить.
enum Captioner {
    static func caption(_ image: UIImage) async -> String {
        await candidates(image).first ?? "Вещь"
    }

    /// Порог «уверены»: ниже него подпись считаем предварительной (потом — уточнение на сервере).
    static let confident: Float = 0.35

    /// Сначала SigLIP 2 (если модель в сборке), иначе встроенная Vision.
    /// Перед распознаванием вырезаем главный предмет кадра: иначе модель описывает комнату, а не вещь.
    static func candidates(_ image: UIImage) async -> [String] {
        let subject = await focusOnSubject(image)
        let clip = await ClipCaptioner.shared.candidates(subject)
        if !clip.isEmpty { return clip.map(\.title) }
        return await visionCandidates(subject)
    }

    /// Объектная заметность (Vision, на устройстве): рамка самого заметного предмета → вырезка с полями.
    /// Если предмет и так занимает почти весь кадр или рамка не найдена — возвращаем исходное фото.
    static func focusOnSubject(_ image: UIImage) async -> UIImage {
        guard let cg = image.cgImage else { return image }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let req = VNGenerateObjectnessBasedSaliencyImageRequest()
                let handler = VNImageRequestHandler(cgImage: cg, orientation: cgOrientation(image.imageOrientation))
                try? handler.perform([req])
                guard let obs = req.results?.first as? VNSaliencyImageObservation,
                      let box = obs.salientObjects?.max(by: { $0.confidence < $1.confidence })?.boundingBox,
                      box.width * box.height < 0.8 else { cont.resume(returning: image); return }
                // bounding box в нормированных координатах с началом внизу слева; добавляем 15 % полей
                let pad: CGFloat = 0.15
                let w = image.size.width, h = image.size.height
                let rect = CGRect(x: (box.minX - box.width * pad) * w,
                                  y: (1 - box.maxY - box.height * pad) * h,
                                  width: box.width * (1 + 2 * pad) * w,
                                  height: box.height * (1 + 2 * pad) * h)
                    .intersection(CGRect(origin: .zero, size: image.size))
                guard rect.width > 64, rect.height > 64 else { cont.resume(returning: image); return }
                let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
                let out = UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
                    image.draw(at: CGPoint(x: -rect.minX, y: -rect.minY))
                }
                cont.resume(returning: out)
            }
        }
    }

    /// До 5 вариантов подписи по убыванию уверенности. Порог — по точности/полноте модели, а не по «сырой» уверенности:
    /// у бытовых вещей она часто 0,05–0,2, и строгий порог отбрасывал всё.
    static func visionCandidates(_ image: UIImage) async -> [String] {
        guard let cg = image.cgImage else { return [] }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let req = VNClassifyImageRequest()
                let handler = VNImageRequestHandler(cgImage: cg, orientation: cgOrientation(image.imageOrientation))
                try? handler.perform([req])
                let all = (req.results ?? []).sorted { $0.confidence > $1.confidence }
                let good = all.filter { $0.hasMinimumPrecision(0.1, forRecall: 0.6) }
                let pool = good.isEmpty ? Array(all.prefix(8)) : good
                var out: [String] = []
                // сначала то, что знаем по-русски
                for r in pool { if let t = ru[r.identifier], !out.contains(t) { out.append(t) } }
                for r in pool where out.count < 5 {
                    let t = r.identifier.replacingOccurrences(of: "_", with: " ").capitalized
                    if ru[r.identifier] == nil, r.confidence > 0.1, !out.contains(t) { out.append(t) }
                }
                cont.resume(returning: Array(out.prefix(5)))
            }
        }
    }

    static func cgOrientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
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
        "power_strip": "Удлинитель", "extension_cord": "Удлинитель", "battery": "Батарейки", "flashlight": "Фонарик",
        "tableware": "Посуда", "dish": "Посуда", "dishware": "Посуда", "kitchenware": "Кухонная утварь", "kitchen_utensil": "Кухонная утварь",
        "cookware": "Посуда для готовки", "tray": "Поднос", "jar": "Банка", "container": "Контейнер", "lid": "Крышка", "thermos": "Термос",
        "coffee": "Кофе", "tea": "Чай", "spice": "Специи", "grocery": "Продукты", "can": "Консервы", "cereal": "Хлопья",
        "clothing": "Одежда", "clothes": "Одежда", "apparel": "Одежда", "garment": "Одежда", "hoodie": "Худи", "pajamas": "Пижама",
        "sock": "Носки", "underwear": "Бельё", "lingerie": "Бельё", "swimsuit": "Купальник", "tie": "Галстук", "suit": "Костюм",
        "textile": "Текстиль", "fabric": "Ткань", "linen": "Бельё", "quilt": "Одеяло", "duvet": "Одеяло", "mattress": "Матрас",
        "furniture": "Мебель", "sofa": "Диван", "couch": "Диван", "armchair": "Кресло", "bed": "Кровать", "desk": "Стол", "bookshelf": "Книжная полка",
        "electronics": "Электроника", "appliance": "Техника", "home_appliance": "Техника", "gadget": "Гаджет", "device": "Устройство",
        "wire": "Провода", "cord": "Провода", "adapter": "Адаптер", "plug": "Вилка", "earphone": "Наушники", "earbuds": "Наушники",
        "game_controller": "Геймпад", "console": "Приставка", "video_game": "Видеоигра", "dvd": "Диски", "cd": "Диски", "vinyl": "Пластинки",
        "stationery": "Канцелярия", "office_supplies": "Канцелярия", "marker": "Маркер", "tape_dispenser": "Скотч", "stapler": "Степлер",
        "photo": "Фотографии", "photograph": "Фотографии", "album": "Альбом", "poster": "Постер", "map": "Карта", "calendar": "Календарь",
        "decoration": "Декор", "ornament": "Украшение", "figurine": "Фигурка", "statue": "Статуэтка", "sculpture": "Скульптура",
        "christmas_tree": "Ёлка", "christmas_decoration": "Ёлочные игрушки", "garland": "Гирлянда", "string_lights": "Гирлянда",
        "cosmetic": "Косметика", "makeup": "Косметика", "lotion": "Крем", "cream": "Крем", "deodorant": "Дезодорант", "razor": "Бритва",
        "toiletry": "Гигиена", "toilet_paper": "Туалетная бумага", "tissue": "Салфетки", "detergent": "Моющее средство", "cleaning_product": "Бытовая химия",
        "sponge": "Губка", "broom": "Веник", "mop": "Швабра", "dustpan": "Совок", "trash_can": "Мусорное ведро",
        "sports_equipment": "Спортинвентарь", "dumbbell": "Гантели", "yoga_mat": "Коврик", "racket": "Ракетка", "tennis_racket": "Ракетка",
        "fishing_rod": "Удочка", "golf_club": "Клюшка", "surfboard": "Доска", "snowboard": "Сноуборд", "roller_skate": "Ролики", "scooter": "Самокат",
        "baby": "Детские вещи", "stroller": "Коляска", "crib": "Кроватка", "pacifier": "Соска", "diaper": "Подгузники", "bottle_baby": "Бутылочка",
        "pet": "Вещи питомца", "pet_bed": "Лежанка", "collar": "Ошейник", "aquarium": "Аквариум", "cage": "Клетка",
        "wood": "Дерево", "plank": "Доски", "metal": "Металл", "plastic": "Пластик", "glassware": "Стекло", "ceramic": "Керамика", "porcelain": "Фарфор",
        "trophy": "Кубок", "medal": "Медаль", "coin": "Монеты", "stamp": "Марки", "key": "Ключи", "keychain": "Брелок", "wallet": "Кошелёк", "purse": "Кошелёк",
        "passport": "Документы", "card": "Карточки", "money": "Деньги", "cash": "Деньги", "safe": "Сейф",
        "sewing_machine": "Швейная машинка", "thread": "Нитки", "yarn": "Пряжа", "needle": "Иголки", "button": "Пуговицы",
        "paint": "Краска", "brush": "Кисти", "paintbrush": "Кисти", "canvas": "Холст", "easel": "Мольберт", "crayon": "Мелки",
        "instrument": "Инструмент", "musical_instrument": "Музыкальный инструмент", "microphone": "Микрофон", "amplifier": "Усилитель",
        "wheel": "Колесо", "tire": "Шина", "helmet_bike": "Шлем", "pump": "Насос", "lock": "Замок", "chain": "Цепь",
        "garden": "Садовое", "garden_tool": "Садовый инструмент", "shovel": "Лопата", "rake": "Грабли", "hose": "Шланг", "watering_can": "Лейка", "seed": "Семена",
        "person": "Вещь", "people": "Вещь", "hand": "Вещь", "indoor": "Вещь", "room": "Вещь", "floor": "Вещь", "wall": "Вещь", "structure": "Вещь"
    ]
}
