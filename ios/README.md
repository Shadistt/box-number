# Box Nº · iOS

Swift 6 · SwiftUI · iOS 17+ · Supabase Swift SDK.

## Как собрать

1. Xcode 16+, Mac. `brew install xcodegen`.
2. В папке `ios/`: `xcodegen generate` → откроется `BoxNo.xcodeproj`.
3. Xcode подтянет пакет `supabase-swift`. Signing — автоматический, Team `2P3PUF975G`, Bundle ID `co.boxnumber.app`.
4. Запуск на iPhone: выбрать устройство, ⌘R.

Проект `.xcodeproj` в git не хранится — генерируется из `project.yml`.

## Что есть в первом спринте

- Вход: Apple, Google (OAuth через Supabase), email + пароль, подтверждение кодом, забыли пароль.
- Главный: Переезды (Хранение и Посылки неактивны), карточки переездов, пустое состояние.
- Новый переезд: Откуда, Куда 1…5 с перетаскиванием.
- Места переезда: список (пока без создания).

Дальше по `docs/tz-moves.md`: тип места, экран места с камерой и плашкой, вещи, доступ.

## TestFlight

Каждый push в `main`, который меняет `ios/`, собирает архив на GitHub Actions и отправляет его в TestFlight (`.github/workflows/ios-testflight.yml`). Номер сборки = номер запуска.

Нужны секреты репозитория (Settings → Secrets and variables → Actions):
- `ASC_KEY_ID` — Key ID ключа App Store Connect API
- `ASC_ISSUER_ID` — Issuer ID
- `ASC_KEY_P8` — содержимое файла `AuthKey_XXXX.p8`

Подпись автоматическая: сертификат распространения и профиль Xcode создаёт сам через API-ключ.
