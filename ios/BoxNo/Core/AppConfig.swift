import Foundation

/// Публичные настройки. Секретов здесь нет и быть не должно.
enum AppConfig {
    static let supabaseURL = URL(string: "https://zolpdtkhfndravxisuzs.supabase.co")!
    /// Публикуемый ключ — можно хранить в приложении.
    static let supabasePublishableKey = "sb_publishable_26tMBY2gqEd2MAKkptvBWA_H7H2yR4Q"
    static let redirectURL = URL(string: "boxno://auth")!
    /// OAuth client ID типа iOS из Google Cloud (публичный).
    static let googleClientID = "1076074844899-vvmmnaf81dsf0phgdu71pr80cvhaobva.apps.googleusercontent.com"

    static let freePlaces = 3
    static let freePhotos = 90
    static let maxDestinations = 5
}
