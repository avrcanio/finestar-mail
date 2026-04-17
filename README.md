# FS Mail

<p align="center">
  <img src="assets/images/fs_mail_logo.png" alt="FS Mail Logo" width="300" />
</p>

FS Mail je mail aplikacija za Fine Star ekosustav. Projekt se sastoji od mobilnog klijenta i backend sloja koji preuzima autentikaciju, pristup mailboxu, dohvat poruka, slanje mailova i dodatne mailbox operacije.

Cilj projekta je imati moderni mail sustav u kojem klijent ne radi direktno IMAP/SMTP kao primarni runtime put, nego koristi backend API kao glavni izvor istine.

## Što projekt sadrži

Projekt trenutno obuhvaća dvije glavne cjeline:

- **Flutter / Android klijent** za rad s mailboxom
- **Django backend** koji radi autentikaciju, IMAP read, SMTP send i mail API sloj

Uz aplikacijski repo, projekt koristi i zaseban `mailserver` repo za mail infrastrukturu, deploy i server-side operativne dijelove.

## Glavne mogućnosti projekta

### Mobilna aplikacija

Flutter klijent pokriva ili aktivno razvija ove funkcionalnosti:

- login korisnika preko backenda
- prikaz foldera i mailbox navigaciju
- prikaz liste poruka
- prikaz detalja poruke
- compose i slanje maila preko backend API-ja
- prikaz HTML email poruka
- rad s attachmentima
- FCM push notifikacije
- multi-account smjer razvoja
- threaded i unified conversation prikaz

### Backend

Django backend pokriva ili definira ove capabilityje:

- auth/session endpointi
- IMAP čitanje mailboxa
- SMTP slanje poruka
- API za foldere, message list i message detail
- attachment metadata i download/send support
- move-to-trash i restore API smjer
- push registration i push delivery
- OpenAPI schema i docs generiranje
- normalizirani mail integration layer za Android klijent

## Arhitektura

FS Mail prati backend-first pristup.

### Klijent

Mobilna aplikacija je odgovorna za:

- prijavu korisnika
- prikaz mailbox UI-a
- lokalni cache i UI state
- navigaciju kroz foldere i poruke
- compose ekran i korisničke akcije
- prikaz notifikacija i account-aware ponašanje na uređaju

### Backend

Backend je odgovoran za:

- autentikaciju i session/token model
- komunikaciju s IMAP i SMTP serverima
- dohvat foldera i poruka
- parsiranje plain text i HTML mail sadržaja
- attachment metadata i attachment operacije
- push registraciju i dostavu push događaja
- dokumentirani API sloj za mobilni klijent

## Backend API

Projekt koristi backend API kao primarni sloj za mobilnu aplikaciju.

Osnovni MVP endpointi uključuju:

- `POST /api/auth/login`
- `GET /api/auth/me`
- `GET /api/mail/folders`
- `GET /api/mail/messages?folder=INBOX&limit=50`
- `GET /api/mail/messages/{uid}?folder=INBOX`
- `POST /api/mail/send`

Daljnji API smjer uključuje i:

- attachment metadata i attachment download
- move-to-trash i restore akcije
- threaded conversation API
- unified conversations across inbox and sent
- account summaries endpoint
- device registration i push delivery endpoint
- index status i periodic sync capability

## Što je već pokriveno na razini projekta

Na temelju strukture repoa i issue planova, FS Mail već ima jasno definirane ili implementirane cjeline za:

- backend mail integration foundation
- IMAP mailbox read service
- SMTP send service
- DRF mail API MVP
- Android/backend API client migration
- push notification arhitekturu
- attachment support
- HTML email rendering
- CID inline image handling
- nested folder support
- mailbox pagination
- delete kao move-to-trash
- multi-account push i summaries smjer
- conversation/threading smjer

## Mailserver repo

Uz ovaj repo postoji i povezani `mailserver` repo koji pokriva infrastrukturni sloj sustava, uključujući mailserver operacije i dio backend-side capabilityja vezanih uz indeksiranje, sync i operativni deploy.

Ovaj repo (`finestar-mail`) primarno opisuje aplikacijski i API sloj, dok `mailserver` pokriva mail infrastrukturu.

## Razvoj i provjere

### Flutter / Android

```bash
flutter pub get
dart analyze
flutter test
flutter build apk --debug
```

### Backend

```bash
docker compose build mailadmin
docker compose run --rm mailadmin python manage.py test
docker compose run --rm mailadmin python manage.py spectacular --file /tmp/schema.yaml
```

## Smjernice za razvoj

Kod promjena u projektu korisno je držati odvojene sliceove rada, npr.:

- backend API promjene
- Flutter / Android UI promjene
- attachment i mail parsing promjene
- push / sync promjene
- asset-only promjene
- issue-scoped feature rad

Takav pristup olakšava review i održavanje projekta.

## Vlasništvo

FS Mail je projekt tvrtke **Fine Star**.

- Website: [www.finestar.hr](https://www.finestar.hr)

## License

Add the project license information here.
