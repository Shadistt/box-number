// Сайт boxnumber.co на Cloudflare Worker (кастомные домены boxnumber.co и www).
// 1) /.well-known/apple-app-site-association — universal links: boxnumber.co/b/<код> открывает приложение.
// 2) /b/<код> — страница для тех, у кого приложения нет: что за место и от кого (RPC share_preview, анонимно),
//    кнопка «Открыть в Box Nº» (boxno://) и ссылка на установку.
// 3) / → редирект на /<язык>/ (язык: выбор пользователя в cookie → Accept-Language → страна → en).
//    /<язык>/ — заглавная с формой «Сообщить о запуске»; POST /<язык>/notify → Edge Function `waitlist`.
// 4) /w/c/<token>, /w/u/<token> — подтверждение подписки и отписка (по кнопке, POST — чтобы
//    почтовые сканеры, открывающие ссылки, не подтверждали и не отписывали за человека).
// Языки — те же, что в приложении (ios/BoxNo/Features/Settings/LanguageView.swift).
// Переменные Worker: SUPABASE_URL, SUPABASE_ANON_KEY, APP_STORE_URL (пусто — «скоро»),
// секрет WAITLIST_SITE_KEY (тот же, что у функции waitlist). Деплой: см. web/README.md.

const TEAM_ID = "2P3PUF975G";
const BUNDLE = "co.boxnumber.app";
const ORIGIN = "https://boxnumber.co";

const LANGS = ["ru", "uk", "en", "de", "fr", "es", "it", "nl", "pl", "pt"];
const NATIVE = { ru: "Русский", uk: "Українська", en: "English", de: "Deutsch", fr: "Français", es: "Español", it: "Italiano", nl: "Nederlands", pl: "Polski", pt: "Português" };
// Страна → язык: только когда браузер не прислал Accept-Language (боты, редкие клиенты).
const COUNTRY_LANG = {
  UA: "uk", RU: "ru", BY: "ru", KZ: "ru", KG: "ru", MD: "ru",
  DE: "de", AT: "de", CH: "de", LI: "de", LU: "de",
  FR: "fr", BE: "fr", MC: "fr",
  ES: "es", MX: "es", AR: "es", CO: "es", CL: "es", PE: "es",
  IT: "it", SM: "it", NL: "nl", PL: "pl", PT: "pt", BR: "pt",
};

const T = {
  ru: {
    title: "Коробки с номером и фото всего, что внутри",
    lead: "Box Nº — приложение для переезда, хранения и отправки посылок: пишете номер маркером на коробке, снимаете вещи, а потом находите любую вещь поиском — в какой она коробке и где коробка.",
    soon: "Скоро в App Store и Google Play.",
    notifyH: "Сообщим о запуске", notifyP: "Оставьте почту — напишем один раз, когда приложение выйдет.",
    email: "Почта", notifyBtn: "Сообщить мне",
    notifyNote: "Пришлём письмо для подтверждения адреса. Отписаться — в один клик.",
    subOk: "Почти готово: проверьте почту и подтвердите адрес по ссылке из письма.",
    subBad: "Похоже, в адресе ошибка. Проверьте и попробуйте ещё раз.",
    subFail: "Не получилось сохранить. Попробуйте чуть позже.",
    lang: "Язык",
    confirmH: "Подтвердите подписку", confirmP: "Нажмите кнопку — и мы сообщим вам о запуске Box Nº.", confirmBtn: "Подтвердить",
    confirmedH: "Готово!", confirmedP: "Напишем, когда Box Nº выйдет в App Store и Google Play.",
    unsubH: "Отписаться от писем Box Nº?", unsubBtn: "Отписаться", unsubbedH: "Вы отписались", unsubbedP: "Больше писем от нас не будет.",
    badLinkH: "Ссылка не работает", badLinkP: "Возможно, она устарела. Оставьте почту на главной ещё раз.",
    home: "На главную", nfH: "Страница не найдена", nfP: "Такой страницы нет.",
    sharedH: "Вам открыли место", sharedP: "{name} делится с вами местом из переезда в Box Nº.",
    open: "Открыть в Box Nº", install: "Установить Box Nº", storeSoon: "Приложение скоро появится в App Store.",
    hint: "Если приложение установлено, эта ссылка открывается в нём сама. Внутри вы увидите фото всего, что лежит в этом месте.",
    linkOffP: "Ссылка выключена или неверна. Попросите того, кто делился местом, прислать новую.",
    noTitle: "Без названия", needPw: "нужен пароль", someone: "Пользователь Box Nº",
    kinds: { box: "Коробка", folder: "Папка", container: "Контейнер", suitcase: "Чемодан или сумка", bag: "Мешок или пакет", wardrobe: "Кофр для одежды", large: "Крупный предмет", custom: "Место" },
    items: { one: "вещь", few: "вещи", many: "вещей", other: "вещи" },
  },
  uk: {
    title: "Коробки з номером і фото всього, що всередині",
    lead: "Box Nº — застосунок для переїзду, зберігання та відправлення посилок: пишете номер маркером на коробці, фотографуєте речі, а потім знаходите будь-яку річ пошуком — у якій вона коробці й де ця коробка.",
    soon: "Незабаром в App Store і Google Play.",
    notifyH: "Повідомимо про запуск", notifyP: "Залиште пошту — напишемо один раз, коли застосунок вийде.",
    email: "Пошта", notifyBtn: "Повідомити мене",
    notifyNote: "Надішлемо лист для підтвердження адреси. Відписатися — в один клік.",
    subOk: "Майже готово: перевірте пошту й підтвердьте адресу за посиланням із листа.",
    subBad: "Схоже, в адресі помилка. Перевірте й спробуйте ще раз.",
    subFail: "Не вдалося зберегти. Спробуйте трохи пізніше.",
    lang: "Мова",
    confirmH: "Підтвердьте підписку", confirmP: "Натисніть кнопку — і ми повідомимо вас про запуск Box Nº.", confirmBtn: "Підтвердити",
    confirmedH: "Готово!", confirmedP: "Напишемо, коли Box Nº вийде в App Store і Google Play.",
    unsubH: "Відписатися від листів Box Nº?", unsubBtn: "Відписатися", unsubbedH: "Ви відписалися", unsubbedP: "Більше листів від нас не буде.",
    badLinkH: "Посилання не працює", badLinkP: "Можливо, воно застаріло. Залиште пошту на головній ще раз.",
    home: "На головну", nfH: "Сторінку не знайдено", nfP: "Такої сторінки немає.",
    sharedH: "Вам відкрили місце", sharedP: "{name} ділиться з вами місцем із переїзду в Box Nº.",
    open: "Відкрити в Box Nº", install: "Встановити Box Nº", storeSoon: "Застосунок незабаром з'явиться в App Store.",
    hint: "Якщо застосунок встановлено, це посилання відкривається в ньому саме. Усередині ви побачите фото всього, що лежить у цьому місці.",
    linkOffP: "Посилання вимкнене або неправильне. Попросіть того, хто ділився місцем, надіслати нове.",
    noTitle: "Без назви", needPw: "потрібен пароль", someone: "Користувач Box Nº",
    kinds: { box: "Коробка", folder: "Тека", container: "Контейнер", suitcase: "Валіза або сумка", bag: "Мішок або пакет", wardrobe: "Кофр для одягу", large: "Великий предмет", custom: "Місце" },
    items: { one: "річ", few: "речі", many: "речей", other: "речі" },
  },
  en: {
    title: "Numbered boxes with photos of everything inside",
    lead: "Box Nº is an app for moving, storage and sending parcels: write a number on the box with a marker, snap the things you pack, and later find anything by search — which box it's in and where that box is.",
    soon: "Coming soon to the App Store and Google Play.",
    notifyH: "Get notified at launch", notifyP: "Leave your email — we'll write once, when the app is out.",
    email: "Email", notifyBtn: "Notify me",
    notifyNote: "We'll send an email to confirm your address. Unsubscribe in one click.",
    subOk: "Almost done: check your inbox and confirm your address with the link in the email.",
    subBad: "That address doesn't look right. Please check it and try again.",
    subFail: "Couldn't save that. Please try again a bit later.",
    lang: "Language",
    confirmH: "Confirm your signup", confirmP: "Press the button and we'll let you know when Box Nº launches.", confirmBtn: "Confirm",
    confirmedH: "You're in!", confirmedP: "We'll email you when Box Nº is out on the App Store and Google Play.",
    unsubH: "Unsubscribe from Box Nº emails?", unsubBtn: "Unsubscribe", unsubbedH: "You're unsubscribed", unsubbedP: "You won't get any more emails from us.",
    badLinkH: "This link doesn't work", badLinkP: "It may have expired. Leave your email on the home page again.",
    home: "Home", nfH: "Page not found", nfP: "There's no such page.",
    sharedH: "A place was shared with you", sharedP: "{name} is sharing a place from their move in Box Nº.",
    open: "Open in Box Nº", install: "Install Box Nº", storeSoon: "The app is coming to the App Store soon.",
    hint: "If the app is installed, this link opens in it automatically. Inside you'll see photos of everything in this place.",
    linkOffP: "The link is turned off or wrong. Ask the person who shared the place to send a new one.",
    noTitle: "Untitled", needPw: "password required", someone: "A Box Nº user",
    kinds: { box: "Box", folder: "Folder", container: "Container", suitcase: "Suitcase or bag", bag: "Sack or bag", wardrobe: "Garment bag", large: "Large item", custom: "Place" },
    items: { one: "item", other: "items" },
  },
  de: {
    title: "Nummerierte Kartons mit Fotos von allem, was drin ist",
    lead: "Box Nº ist eine App für Umzug, Einlagerung und Paketversand: Nummer mit dem Marker auf den Karton schreiben, eingepackte Dinge fotografieren – und später alles per Suche finden: in welchem Karton es ist und wo der Karton steht.",
    soon: "Bald im App Store und bei Google Play.",
    notifyH: "Zum Start benachrichtigen", notifyP: "Hinterlasse deine E-Mail – wir schreiben einmal, wenn die App erscheint.",
    email: "E-Mail", notifyBtn: "Benachrichtige mich",
    notifyNote: "Wir schicken eine E-Mail zur Bestätigung deiner Adresse. Abmelden mit einem Klick.",
    subOk: "Fast geschafft: Schau in dein Postfach und bestätige die Adresse über den Link in der E-Mail.",
    subBad: "Die Adresse scheint fehlerhaft zu sein. Bitte prüfen und erneut versuchen.",
    subFail: "Speichern hat nicht geklappt. Bitte versuche es etwas später noch einmal.",
    lang: "Sprache",
    confirmH: "Anmeldung bestätigen", confirmP: "Klick auf den Button und wir sagen dir Bescheid, sobald Box Nº startet.", confirmBtn: "Bestätigen",
    confirmedH: "Geschafft!", confirmedP: "Wir schreiben dir, sobald Box Nº im App Store und bei Google Play ist.",
    unsubH: "Von E-Mails von Box Nº abmelden?", unsubBtn: "Abmelden", unsubbedH: "Du bist abgemeldet", unsubbedP: "Du bekommst keine E-Mails mehr von uns.",
    badLinkH: "Dieser Link funktioniert nicht", badLinkP: "Vielleicht ist er abgelaufen. Trag deine E-Mail auf der Startseite noch einmal ein.",
    home: "Zur Startseite", nfH: "Seite nicht gefunden", nfP: "Diese Seite gibt es nicht.",
    sharedH: "Mit dir wurde ein Platz geteilt", sharedP: "{name} teilt mit dir einen Platz aus dem Umzug in Box Nº.",
    open: "In Box Nº öffnen", install: "Box Nº installieren", storeSoon: "Die App kommt bald in den App Store.",
    hint: "Ist die App installiert, öffnet sich dieser Link direkt darin. Dort siehst du Fotos von allem, was an diesem Platz liegt.",
    linkOffP: "Der Link ist deaktiviert oder falsch. Bitte die Person, die den Platz geteilt hat, um einen neuen.",
    noTitle: "Ohne Titel", needPw: "Passwort nötig", someone: "Box-Nº-Nutzer",
    kinds: { box: "Karton", folder: "Ordner", container: "Behälter", suitcase: "Koffer oder Tasche", bag: "Sack oder Beutel", wardrobe: "Kleidersack", large: "Großer Gegenstand", custom: "Platz" },
    items: { one: "Gegenstand", other: "Gegenstände" },
  },
  fr: {
    title: "Des cartons numérotés avec la photo de tout ce qu'ils contiennent",
    lead: "Box Nº est une application pour déménager, stocker et envoyer des colis : écrivez un numéro au marqueur sur le carton, photographiez ce que vous emballez, puis retrouvez n'importe quel objet par la recherche — dans quel carton il est et où se trouve ce carton.",
    soon: "Bientôt sur l'App Store et Google Play.",
    notifyH: "Être prévenu du lancement", notifyP: "Laissez votre e-mail : nous vous écrirons une seule fois, à la sortie de l'application.",
    email: "E-mail", notifyBtn: "Me prévenir",
    notifyNote: "Nous vous enverrons un e-mail pour confirmer votre adresse. Désinscription en un clic.",
    subOk: "Presque fini : vérifiez votre boîte mail et confirmez votre adresse via le lien reçu.",
    subBad: "Cette adresse semble incorrecte. Vérifiez-la et réessayez.",
    subFail: "Impossible d'enregistrer. Réessayez un peu plus tard.",
    lang: "Langue",
    confirmH: "Confirmez votre inscription", confirmP: "Appuyez sur le bouton et nous vous préviendrons du lancement de Box Nº.", confirmBtn: "Confirmer",
    confirmedH: "C'est fait !", confirmedP: "Nous vous écrirons dès que Box Nº sera sur l'App Store et Google Play.",
    unsubH: "Se désinscrire des e-mails de Box Nº ?", unsubBtn: "Se désinscrire", unsubbedH: "Vous êtes désinscrit", unsubbedP: "Vous ne recevrez plus d'e-mails de notre part.",
    badLinkH: "Ce lien ne fonctionne pas", badLinkP: "Il a peut-être expiré. Laissez à nouveau votre e-mail sur la page d'accueil.",
    home: "Accueil", nfH: "Page introuvable", nfP: "Cette page n'existe pas.",
    sharedH: "On vous a partagé un emplacement", sharedP: "{name} partage avec vous un emplacement de son déménagement dans Box Nº.",
    open: "Ouvrir dans Box Nº", install: "Installer Box Nº", storeSoon: "L'application arrive bientôt sur l'App Store.",
    hint: "Si l'application est installée, ce lien s'y ouvre automatiquement. Vous y verrez les photos de tout ce qui se trouve à cet emplacement.",
    linkOffP: "Le lien est désactivé ou incorrect. Demandez-en un nouveau à la personne qui l'a partagé.",
    noTitle: "Sans titre", needPw: "mot de passe requis", someone: "Un utilisateur de Box Nº",
    kinds: { box: "Carton", folder: "Dossier", container: "Bac", suitcase: "Valise ou sac", bag: "Sac ou sachet", wardrobe: "Housse à vêtements", large: "Objet volumineux", custom: "Emplacement" },
    items: { one: "objet", other: "objets" },
  },
  es: {
    title: "Cajas numeradas con foto de todo lo que llevan dentro",
    lead: "Box Nº es una app para mudanzas, almacenaje y envío de paquetes: escribe un número con rotulador en la caja, fotografía lo que guardas y luego encuentra cualquier cosa con el buscador: en qué caja está y dónde está esa caja.",
    soon: "Muy pronto en App Store y Google Play.",
    notifyH: "Te avisamos del lanzamiento", notifyP: "Deja tu correo: te escribiremos una sola vez, cuando salga la app.",
    email: "Correo", notifyBtn: "Avisarme",
    notifyNote: "Te enviaremos un correo para confirmar tu dirección. Darte de baja es un clic.",
    subOk: "Casi listo: revisa tu correo y confirma la dirección con el enlace del mensaje.",
    subBad: "Parece que la dirección tiene un error. Revísala e inténtalo de nuevo.",
    subFail: "No se pudo guardar. Inténtalo de nuevo un poco más tarde.",
    lang: "Idioma",
    confirmH: "Confirma tu suscripción", confirmP: "Pulsa el botón y te avisaremos cuando se lance Box Nº.", confirmBtn: "Confirmar",
    confirmedH: "¡Listo!", confirmedP: "Te escribiremos cuando Box Nº esté en App Store y Google Play.",
    unsubH: "¿Darte de baja de los correos de Box Nº?", unsubBtn: "Darme de baja", unsubbedH: "Te has dado de baja", unsubbedP: "No recibirás más correos nuestros.",
    badLinkH: "Este enlace no funciona", badLinkP: "Puede que haya caducado. Deja tu correo de nuevo en la página principal.",
    home: "Inicio", nfH: "Página no encontrada", nfP: "Esta página no existe.",
    sharedH: "Te han compartido un lugar", sharedP: "{name} comparte contigo un lugar de su mudanza en Box Nº.",
    open: "Abrir en Box Nº", install: "Instalar Box Nº", storeSoon: "La app llegará pronto a App Store.",
    hint: "Si tienes la app instalada, este enlace se abre en ella automáticamente. Dentro verás fotos de todo lo que hay en este lugar.",
    linkOffP: "El enlace está desactivado o es incorrecto. Pide uno nuevo a quien compartió el lugar.",
    noTitle: "Sin título", needPw: "requiere contraseña", someone: "Un usuario de Box Nº",
    kinds: { box: "Caja", folder: "Carpeta", container: "Contenedor", suitcase: "Maleta o bolsa", bag: "Saco o bolsa", wardrobe: "Portatrajes", large: "Objeto grande", custom: "Lugar" },
    items: { one: "objeto", other: "objetos" },
  },
  it: {
    title: "Scatole numerate con la foto di tutto ciò che contengono",
    lead: "Box Nº è un'app per traslochi, deposito e spedizione di pacchi: scrivi un numero col pennarello sulla scatola, fotografa ciò che metti dentro e poi trova qualsiasi oggetto con la ricerca: in quale scatola è e dove si trova la scatola.",
    soon: "Presto su App Store e Google Play.",
    notifyH: "Ti avvisiamo al lancio", notifyP: "Lascia la tua e-mail: ti scriveremo una sola volta, quando l'app sarà disponibile.",
    email: "E-mail", notifyBtn: "Avvisami",
    notifyNote: "Ti invieremo un'e-mail per confermare l'indirizzo. Disiscrizione con un clic.",
    subOk: "Quasi fatto: controlla la posta e conferma l'indirizzo con il link nell'e-mail.",
    subBad: "L'indirizzo sembra errato. Controllalo e riprova.",
    subFail: "Salvataggio non riuscito. Riprova tra poco.",
    lang: "Lingua",
    confirmH: "Conferma l'iscrizione", confirmP: "Premi il pulsante e ti avviseremo al lancio di Box Nº.", confirmBtn: "Conferma",
    confirmedH: "Fatto!", confirmedP: "Ti scriveremo quando Box Nº sarà su App Store e Google Play.",
    unsubH: "Annullare l'iscrizione alle e-mail di Box Nº?", unsubBtn: "Annulla iscrizione", unsubbedH: "Iscrizione annullata", unsubbedP: "Non riceverai più e-mail da noi.",
    badLinkH: "Questo link non funziona", badLinkP: "Forse è scaduto. Lascia di nuovo la tua e-mail nella pagina principale.",
    home: "Home", nfH: "Pagina non trovata", nfP: "Questa pagina non esiste.",
    sharedH: "Ti hanno condiviso un posto", sharedP: "{name} condivide con te un posto del suo trasloco in Box Nº.",
    open: "Apri in Box Nº", install: "Installa Box Nº", storeSoon: "L'app arriverà presto su App Store.",
    hint: "Se l'app è installata, questo link si apre direttamente lì. Dentro vedrai le foto di tutto ciò che c'è in questo posto.",
    linkOffP: "Il link è disattivato o errato. Chiedi un nuovo link a chi ha condiviso il posto.",
    noTitle: "Senza titolo", needPw: "serve la password", someone: "Un utente Box Nº",
    kinds: { box: "Scatola", folder: "Cartella", container: "Contenitore", suitcase: "Valigia o borsa", bag: "Sacco o busta", wardrobe: "Porta abiti", large: "Oggetto ingombrante", custom: "Posto" },
    items: { one: "oggetto", other: "oggetti" },
  },
  nl: {
    title: "Genummerde dozen met foto's van alles wat erin zit",
    lead: "Box Nº is een app voor verhuizen, opslag en pakketten versturen: schrijf met een stift een nummer op de doos, fotografeer wat je inpakt en vind later alles terug via zoeken: in welke doos het zit en waar die doos staat.",
    soon: "Binnenkort in de App Store en Google Play.",
    notifyH: "Laat het me weten bij de lancering", notifyP: "Laat je e-mail achter – we mailen één keer, zodra de app er is.",
    email: "E-mail", notifyBtn: "Houd me op de hoogte",
    notifyNote: "We sturen een e-mail om je adres te bevestigen. Afmelden met één klik.",
    subOk: "Bijna klaar: check je inbox en bevestig je adres via de link in de e-mail.",
    subBad: "Dat adres lijkt niet te kloppen. Controleer het en probeer opnieuw.",
    subFail: "Opslaan is niet gelukt. Probeer het later nog eens.",
    lang: "Taal",
    confirmH: "Bevestig je aanmelding", confirmP: "Druk op de knop en we laten het je weten zodra Box Nº live gaat.", confirmBtn: "Bevestigen",
    confirmedH: "Gelukt!", confirmedP: "We mailen je zodra Box Nº in de App Store en Google Play staat.",
    unsubH: "Afmelden voor e-mails van Box Nº?", unsubBtn: "Afmelden", unsubbedH: "Je bent afgemeld", unsubbedP: "Je krijgt geen e-mails meer van ons.",
    badLinkH: "Deze link werkt niet", badLinkP: "Misschien is hij verlopen. Laat je e-mail opnieuw achter op de homepage.",
    home: "Naar home", nfH: "Pagina niet gevonden", nfP: "Deze pagina bestaat niet.",
    sharedH: "Er is een plek met je gedeeld", sharedP: "{name} deelt een plek uit de verhuizing in Box Nº met je.",
    open: "Openen in Box Nº", install: "Box Nº installeren", storeSoon: "De app komt binnenkort in de App Store.",
    hint: "Als de app geïnstalleerd is, opent deze link er vanzelf in. Daar zie je foto's van alles wat op deze plek ligt.",
    linkOffP: "De link is uitgeschakeld of onjuist. Vraag degene die de plek deelde om een nieuwe.",
    noTitle: "Zonder titel", needPw: "wachtwoord nodig", someone: "Een Box Nº-gebruiker",
    kinds: { box: "Doos", folder: "Map", container: "Bak", suitcase: "Koffer of tas", bag: "Zak of tas", wardrobe: "Kledinghoes", large: "Groot voorwerp", custom: "Plek" },
    items: { one: "voorwerp", other: "voorwerpen" },
  },
  pl: {
    title: "Ponumerowane pudła ze zdjęciami wszystkiego, co w środku",
    lead: "Box Nº to aplikacja do przeprowadzek, przechowywania i wysyłki paczek: piszesz numer markerem na pudle, fotografujesz pakowane rzeczy, a potem znajdujesz wszystko wyszukiwarką — w którym pudle jest i gdzie stoi to pudło.",
    soon: "Wkrótce w App Store i Google Play.",
    notifyH: "Damy znać o premierze", notifyP: "Zostaw e-mail — napiszemy raz, gdy aplikacja będzie dostępna.",
    email: "E-mail", notifyBtn: "Powiadom mnie",
    notifyNote: "Wyślemy e-mail z potwierdzeniem adresu. Wypisanie się — jednym kliknięciem.",
    subOk: "Prawie gotowe: sprawdź skrzynkę i potwierdź adres linkiem z wiadomości.",
    subBad: "Wygląda na to, że adres jest błędny. Sprawdź go i spróbuj ponownie.",
    subFail: "Nie udało się zapisać. Spróbuj ponownie za chwilę.",
    lang: "Język",
    confirmH: "Potwierdź zapis", confirmP: "Naciśnij przycisk, a damy Ci znać o premierze Box Nº.", confirmBtn: "Potwierdź",
    confirmedH: "Gotowe!", confirmedP: "Napiszemy, gdy Box Nº pojawi się w App Store i Google Play.",
    unsubH: "Wypisać się z wiadomości Box Nº?", unsubBtn: "Wypisz się", unsubbedH: "Wypisano", unsubbedP: "Nie dostaniesz od nas więcej wiadomości.",
    badLinkH: "Ten link nie działa", badLinkP: "Może wygasł. Zostaw e-mail na stronie głównej jeszcze raz.",
    home: "Strona główna", nfH: "Nie znaleziono strony", nfP: "Taka strona nie istnieje.",
    sharedH: "Udostępniono Ci miejsce", sharedP: "{name} udostępnia Ci miejsce z przeprowadzki w Box Nº.",
    open: "Otwórz w Box Nº", install: "Zainstaluj Box Nº", storeSoon: "Aplikacja wkrótce pojawi się w App Store.",
    hint: "Jeśli aplikacja jest zainstalowana, ten link otworzy się w niej sam. W środku zobaczysz zdjęcia wszystkiego, co jest w tym miejscu.",
    linkOffP: "Link jest wyłączony lub błędny. Poproś osobę, która udostępniła miejsce, o nowy.",
    noTitle: "Bez nazwy", needPw: "wymaga hasła", someone: "Użytkownik Box Nº",
    kinds: { box: "Pudło", folder: "Teczka", container: "Pojemnik", suitcase: "Walizka lub torba", bag: "Worek lub torba", wardrobe: "Pokrowiec na ubrania", large: "Duży przedmiot", custom: "Miejsce" },
    items: { one: "przedmiot", few: "przedmioty", many: "przedmiotów", other: "przedmiotu" },
  },
  pt: {
    title: "Caixas numeradas com fotos de tudo o que está lá dentro",
    lead: "Box Nº é uma app para mudanças, armazenamento e envio de encomendas: escreva um número com marcador na caixa, fotografe o que embala e depois encontre qualquer coisa pela pesquisa — em que caixa está e onde está essa caixa.",
    soon: "Em breve na App Store e no Google Play.",
    notifyH: "Avisamos no lançamento", notifyP: "Deixe o seu e-mail — escrevemos uma vez, quando a app sair.",
    email: "E-mail", notifyBtn: "Avisem-me",
    notifyNote: "Enviaremos um e-mail para confirmar o endereço. Cancelar a inscrição é um clique.",
    subOk: "Quase pronto: veja o seu e-mail e confirme o endereço pelo link da mensagem.",
    subBad: "Parece haver um erro no endereço. Verifique e tente novamente.",
    subFail: "Não foi possível guardar. Tente novamente daqui a pouco.",
    lang: "Idioma",
    confirmH: "Confirme a inscrição", confirmP: "Carregue no botão e avisamos quando o Box Nº for lançado.", confirmBtn: "Confirmar",
    confirmedH: "Feito!", confirmedP: "Escreveremos quando o Box Nº estiver na App Store e no Google Play.",
    unsubH: "Cancelar os e-mails do Box Nº?", unsubBtn: "Cancelar inscrição", unsubbedH: "Inscrição cancelada", unsubbedP: "Não receberá mais e-mails nossos.",
    badLinkH: "Este link não funciona", badLinkP: "Talvez tenha expirado. Deixe o seu e-mail na página inicial novamente.",
    home: "Página inicial", nfH: "Página não encontrada", nfP: "Esta página não existe.",
    sharedH: "Partilharam um lugar consigo", sharedP: "{name} partilha consigo um lugar da mudança no Box Nº.",
    open: "Abrir no Box Nº", install: "Instalar o Box Nº", storeSoon: "A app chega em breve à App Store.",
    hint: "Se a app estiver instalada, este link abre-se nela automaticamente. Lá dentro verá fotos de tudo o que está neste lugar.",
    linkOffP: "O link está desativado ou incorreto. Peça um novo a quem partilhou o lugar.",
    noTitle: "Sem título", needPw: "requer palavra-passe", someone: "Um utilizador do Box Nº",
    kinds: { box: "Caixa", folder: "Pasta", container: "Contentor", suitcase: "Mala ou saco", bag: "Saco", wardrobe: "Capa para roupa", large: "Objeto grande", custom: "Lugar" },
    items: { one: "objeto", other: "objetos" },
  },
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.hostname.startsWith("www.")) {
      return Response.redirect(`${ORIGIN}${url.pathname}${url.search}`, 301);
    }
    const path = url.pathname.replace(/\/+$/, "") || "/";

    if (path === "/.well-known/apple-app-site-association" || path === "/apple-app-site-association") {
      const aasa = { applinks: { apps: [], details: [{ appIDs: [`${TEAM_ID}.${BUNDLE}`], components: [{ "/": "/b/*", comment: "Общее место по ссылке" }] }] } };
      return new Response(JSON.stringify(aasa), { headers: { "content-type": "application/json", "cache-control": "public, max-age=3600" } });
    }
    if (path === "/robots.txt") return text(`User-agent: *\nDisallow: /b/\nDisallow: /w/\nSitemap: ${ORIGIN}/sitemap.xml\n`);
    if (path === "/sitemap.xml") return sitemap();

    // Корень: выбираем язык и отправляем на /<язык>/ (x-default в hreflang).
    if (path === "/") {
      const lang = pickLang(request);
      return new Response(null, { status: 302, headers: { location: `/${lang}/`, vary: "Accept-Language, Cookie", "cache-control": "private, no-store" } });
    }

    const lm = path.match(/^\/([a-z]{2})(\/.*)?$/);
    if (lm && LANGS.includes(lm[1])) {
      const lang = lm[1], rest = lm[2] || "/";
      if (rest === "/" && request.method === "GET") {
        // ?l=1 — пользователь сам выбрал язык в переключателе: запоминаем на год.
        if (url.searchParams.get("l") === "1") {
          return new Response(null, { status: 302, headers: { location: `/${lang}/`, "set-cookie": langCookie(lang) } });
        }
        return html(landing(lang, url.searchParams.get("s")), 200, lang);
      }
      if (rest === "/notify" && request.method === "POST") return notify(request, env, lang);
    }

    const b = path.match(/^\/b\/([A-Za-z0-9_-]{6,32})$/);
    if (b) return sharePage(b[1], env, pickLang(request));

    const w = path.match(/^\/w\/(c|u)\/([0-9a-fA-F-]{36})$/);
    if (w) return waitlistLink(request, env, w[1], w[2]);

    const lang = pickLang(request);
    const t = T[lang];
    return html(page(lang, t.nfH, `<p class="muted">${esc(t.nfP)}</p><p><a class="btn" href="/${lang}/">${esc(t.home)}</a></p>`), 404, lang);
  },
};

// ---------- язык ----------
// Порядок: явный выбор (cookie) → языки браузера/устройства (Accept-Language, по весу q) → страна → en.
function pickLang(request) {
  const cookie = request.headers.get("cookie") || "";
  const c = cookie.match(/(?:^|;\s*)lang=([a-z]{2})/);
  if (c && LANGS.includes(c[1])) return c[1];

  const al = request.headers.get("accept-language");
  if (al) {
    const prefs = al.split(",").map((part, i) => {
      const [tag, ...params] = part.trim().split(";");
      const q = params.map((p) => p.trim()).find((p) => p.startsWith("q="));
      return { base: tag.toLowerCase().split("-")[0], q: q ? parseFloat(q.slice(2)) : 1, i };
    }).filter((p) => p.base && p.q > 0).sort((a, b) => b.q - a.q || a.i - b.i);
    for (const p of prefs) {
      if (LANGS.includes(p.base)) return p.base;
      if (p.base === "be") return "ru"; // белорусский: ближайший из поддерживаемых
    }
    if (prefs.length) return "en"; // браузер сказал свои языки, но ни одного нашего — английский
  }
  const country = request.cf && request.cf.country;
  return (country && COUNTRY_LANG[country]) || "en";
}

function langCookie(lang) {
  return `lang=${lang}; Path=/; Max-Age=31536000; SameSite=Lax; Secure`;
}

// ---------- подписка ----------
async function notify(request, env, lang) {
  let status = "ok";
  try {
    const form = await request.formData();
    if (String(form.get("website") || "")) return seeOther(`/${lang}/?s=ok#notify`); // ловушка для ботов
    const email = String(form.get("email") || "").trim();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email) || email.length > 254) {
      status = "bad";
    } else {
      const r = await callWaitlist(env, {
        action: "join", email, locale: lang,
        country: request.cf && request.cf.country,
        ip: request.headers.get("cf-connecting-ip"),
      });
      status = r.ok ? "ok" : r.error === "email" ? "bad" : "fail";
    }
  } catch (e) {
    console.error("notify:", e);
    status = "fail";
  }
  return seeOther(`/${lang}/?s=${status}#notify`);
}

async function callWaitlist(env, body) {
  const r = await fetch(`${env.SUPABASE_URL}/functions/v1/waitlist`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-site-key": env.WAITLIST_SITE_KEY || "", apikey: env.SUPABASE_ANON_KEY },
    body: JSON.stringify(body),
  });
  const data = await r.json().catch(() => ({}));
  return { ok: r.ok && data.ok === true, ...data };
}

// GET — страница с кнопкой; POST — само действие (почтовые сканеры ходят по ссылкам GET-ом).
async function waitlistLink(request, env, kind, token) {
  let lang = pickLang(request);
  if (request.method === "POST") {
    const r = await callWaitlist(env, { action: kind === "c" ? "confirm" : "unsubscribe", token });
    if (LANGS.includes(r.locale)) lang = r.locale;
    const t = T[lang];
    if (!r.ok) return html(page(lang, t.badLinkH, `<p class="muted">${esc(t.badLinkP)}</p><p><a class="btn" href="/${lang}/">${esc(t.home)}</a></p>`), 404, lang);
    return kind === "c"
      ? html(page(lang, t.confirmedH, `<p class="muted">${esc(t.confirmedP)}</p><p><a class="btn ghost" href="/${lang}/">${esc(t.home)}</a></p>`), 200, lang)
      : html(page(lang, t.unsubbedH, `<p class="muted">${esc(t.unsubbedP)}</p><p><a class="btn ghost" href="/${lang}/">${esc(t.home)}</a></p>`), 200, lang);
  }
  const t = T[lang];
  const [h, p, btn] = kind === "c" ? [t.confirmH, t.confirmP, t.confirmBtn] : [t.unsubH, "", t.unsubBtn];
  return html(page(lang, h, `${p ? `<p class="muted">${esc(p)}</p>` : ""}
    <form method="post"><button class="btn" type="submit">${esc(btn)}</button></form>`), 200, lang);
}

// ---------- страницы ----------
function landing(lang, s) {
  const t = T[lang];
  const msg = s === "ok" ? `<p class="note ok" role="status">${esc(t.subOk)}</p>`
    : s === "bad" ? `<p class="note err" role="alert">${esc(t.subBad)}</p>`
    : s === "fail" ? `<p class="note err" role="alert">${esc(t.subFail)}</p>` : "";
  const form = s === "ok" ? "" : `
    <form class="notify" method="post" action="/${lang}/notify">
      <label for="email">${esc(t.email)}</label>
      <input id="email" name="email" type="email" autocomplete="email" inputmode="email" required maxlength="254" placeholder="you@example.com">
      <input class="hp" name="website" tabindex="-1" autocomplete="off" aria-hidden="true">
      <button class="btn" type="submit">${esc(t.notifyBtn)}</button>
      <p class="muted small">${esc(t.notifyNote)}</p>
    </form>`;
  return page(lang, t.title, `
    <p class="muted">${esc(t.lead)}</p>
    <p class="muted small">${esc(t.soon)}</p>
    <section id="notify" class="box" aria-labelledby="notify-h">
      <h2 id="notify-h">${esc(t.notifyH)}</h2>
      <p class="muted small">${esc(t.notifyP)}</p>
      ${msg}${form}
    </section>`, { home: true, alternates: true });
}

async function sharePage(code, env, lang) {
  const t = T[lang];
  let p = null;
  try {
    const r = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/share_preview`, {
      method: "POST",
      headers: { apikey: env.SUPABASE_ANON_KEY, authorization: `Bearer ${env.SUPABASE_ANON_KEY}`, "content-type": "application/json" },
      body: JSON.stringify({ p_code: code }),
    });
    if (r.ok) { const rows = await r.json(); p = rows[0] ?? null; }
  } catch (_) { // покажем страницу без предпросмотра
  }

  const open = `boxno://b/${code}`;
  const install = env.APP_STORE_URL
    ? `<a class="btn ghost" href="${esc(env.APP_STORE_URL)}">${esc(t.install)}</a>`
    : `<p class="muted small">${esc(t.storeSoon)}</p>`;

  if (!p) {
    return html(page(lang, t.badLinkH, `
      <p class="muted">${esc(t.linkOffP)}</p>
      <p><a class="btn" href="/${lang}/">${esc(t.home)}</a></p>`), 404, lang, true);
  }
  const kind = t.kinds[p.kind] ?? t.kinds.custom;
  const title = p.title && p.title.trim() ? esc(p.title) : esc(t.noTitle);
  const owner = p.owner_name && p.owner_name !== "Пользователь Box Nº" ? p.owner_name : t.someone;
  const items = plural(lang, p.items, t.items);
  return html(page(lang, t.sharedH, `
    <p class="muted">${esc(t.sharedP).replace("{name}", `<b>${esc(owner)}</b>`)}</p>
    <div class="card">
      <div class="num">${esc(p.number)}</div>
      <div>
        <div class="t">${title}</div>
        <div class="muted small">${esc(kind)} · ${esc(items)}${p.password ? " · " + esc(t.needPw) : ""}</div>
      </div>
    </div>
    <a class="btn" href="${open}">${esc(t.open)}</a>
    ${install}
    <p class="muted small">${esc(t.hint)}</p>`), 200, lang, true);
}

function sitemap() {
  const links = LANGS.map((l) => `<xhtml:link rel="alternate" hreflang="${l}" href="${ORIGIN}/${l}/"/>`).join("") +
    `<xhtml:link rel="alternate" hreflang="x-default" href="${ORIGIN}/"/>`;
  const urls = LANGS.map((l) => `<url><loc>${ORIGIN}/${l}/</loc>${links}</url>`).join("");
  return new Response(`<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">${urls}</urlset>`,
    { headers: { "content-type": "application/xml; charset=utf-8", "cache-control": "public, max-age=3600" } });
}

function page(lang, h1, body, opts = {}) {
  const t = T[lang];
  const alt = opts.alternates
    ? LANGS.map((l) => `<link rel="alternate" hreflang="${l}" href="${ORIGIN}/${l}/">`).join("") +
      `<link rel="alternate" hreflang="x-default" href="${ORIGIN}/"><link rel="canonical" href="${ORIGIN}/${lang}/">`
    : "";
  const switcher = LANGS.map((l) => l === lang
    ? `<span aria-current="true" lang="${l}">${NATIVE[l]}</span>`
    : `<a href="/${l}/?l=1" lang="${l}" hreflang="${l}">${NATIVE[l]}</a>`).join("");
  return `<!doctype html><html lang="${lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(h1)} · Box Nº</title>${opts.home ? `<meta name="description" content="${esc(t.lead)}">` : ""}${alt}
<style>
:root{--bg:#F1F0EC;--ink:#16171A;--muted:#5E6066;--accent:#F0561D;--card:#fff;--line:#D9D6CF;--ok:#1E6B3A;--err:#B42318}
@media(prefers-color-scheme:dark){:root{--bg:#121214;--ink:#F2F1EE;--muted:#9EA0A7;--card:#1E1F23;--line:#33343A;--ok:#7BD69A;--err:#FF9A8F}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font-family:-apple-system,"SF Pro Text",Helvetica,Arial,sans-serif;-webkit-font-smoothing:antialiased}
main{max-width:440px;margin:0 auto;padding:48px 20px 40px}
.logo{font-size:28px;font-weight:900;margin:0 0 28px}.logo a{color:inherit;text-decoration:none}.logo span{color:var(--accent)}
h1{font-size:26px;font-weight:900;line-height:1.15;margin:0 0 12px}h2{font-size:20px;font-weight:800;margin:0 0 6px}
p{font-size:16px;line-height:1.45;margin:0 0 14px}.muted{color:var(--muted)}.small{font-size:14px}
.card{display:flex;gap:14px;align-items:center;background:var(--ink);color:#fff;border-radius:18px;padding:16px;margin:18px 0 20px}
@media(prefers-color-scheme:dark){.card{background:#1E1F23}}
.num{min-width:56px;height:56px;border-radius:14px;background:var(--accent);display:flex;align-items:center;justify-content:center;font-size:22px;font-weight:900;color:#fff;padding:0 10px}
.t{font-size:18px;font-weight:800;margin-bottom:2px}.card .muted{color:#B8B9BE}
.btn{display:block;width:100%;text-align:center;background:var(--ink);color:#fff;text-decoration:none;font:inherit;font-weight:700;font-size:17px;border:0;border-radius:28px;padding:16px;margin:0 0 12px;cursor:pointer}
@media(prefers-color-scheme:dark){.btn{background:#F2F1EE;color:#16171A}}
.btn.ghost{background:var(--card);color:var(--ink);border:1px solid var(--line)}
.box{background:var(--card);border:1px solid var(--line);border-radius:20px;padding:20px;margin:28px 0 0}
.notify label{display:block;font-size:14px;font-weight:700;margin:14px 0 6px}
.notify input[type=email]{width:100%;font:inherit;font-size:17px;color:var(--ink);background:var(--bg);border:1px solid var(--line);border-radius:14px;padding:14px 16px;margin:0 0 12px}
.notify input[type=email]:focus{outline:2px solid var(--accent);outline-offset:1px}
.hp{position:absolute;left:-9999px;width:1px;height:1px;opacity:0}
.note{font-size:15px;font-weight:600;border-radius:12px;padding:12px 14px;margin:14px 0 0}
.note.ok{color:var(--ok);background:color-mix(in srgb,var(--ok) 12%,transparent)}
.note.err{color:var(--err);background:color-mix(in srgb,var(--err) 12%,transparent)}
nav.langs{margin:40px 0 0;padding:16px 0 0;border-top:1px solid var(--line);font-size:14px;line-height:2;color:var(--muted)}
nav.langs a,nav.langs span{margin-right:12px;white-space:nowrap}nav.langs a{color:var(--muted)}nav.langs span{color:var(--ink);font-weight:700}
</style></head><body><main>
<p class="logo"><a href="/${lang}/">Box <span>Nº</span></a></p>
<h1>${esc(h1)}</h1>
${body}
<nav class="langs" aria-label="${esc(t.lang)}">${switcher}</nav>
</main></body></html>`;
}

function html(s, status, lang, noindex = false) {
  const headers = { "content-type": "text/html; charset=utf-8", "content-language": lang, vary: "Accept-Language, Cookie" };
  if (noindex) headers["x-robots-tag"] = "noindex";
  return new Response(s, { status, headers });
}
function text(s) { return new Response(s, { headers: { "content-type": "text/plain; charset=utf-8" } }); }
function seeOther(location) { return new Response(null, { status: 303, headers: { location, "cache-control": "no-store" } }); }
function esc(s) { return String(s).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])); }
function plural(lang, n, forms) {
  const cat = new Intl.PluralRules(lang).select(n);
  return `${n} ${forms[cat] ?? forms.other}`;
}
