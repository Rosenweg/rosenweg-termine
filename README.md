<p align="center"><img src="assets/logo/rosenweg-termine-512.png" width="96" alt="Logo"></p>
<h1 align="center">Rosenweg Termine</h1>
<p align="center">Termine und Versammlungen deiner STWEG: ansehen, in den Kalender übernehmen, erinnern lassen.</p>
<p align="center"><a href="docs/anleitung.md">Anleitung</a> · <a href="https://www.rosenweg4303.ch/apps">Herunterladen</a></p>

Angelegt mit `werkzeug/neue-app.sh` aus der App-Vorlage von
[rosenweg-basis](https://github.com/Rosenweg/rosenweg-basis). Anmeldung, API,
Gerüst, Updater und Logo kommen aus der Basis; hier steht nur, was diese App
eigen macht.

## Läuft auf

| Plattform | Datei | Grenzen |
|---|---|---|
| Linux (Debian 13, Stationen und eigene Rechner) | `rosenweg-termine_<version>_amd64.deb` | Stationen bekommen das Paket vom PXE-Server (os-stationen), dort ist der Updater aus |
| Android 8 und neuer | `rosenweg-termine-<version>.apk` (Rosenweg-Schlüssel) | auf geteilten Telefonen meldet Rosenweg Gerät an und ab |
| Windows 10/11 | `Rosenweg-Termine-<version>-Setup.exe` | unsigniert, solange kein Code-Signing-Zertifikat da ist (SmartScreen fragt einmal) |
| macOS 11 und neuer | `Rosenweg-Termine-<version>.dmg` | ohne Apple Developer ID ad hoc signiert (Gatekeeper fragt beim ersten Start) |
| iOS/iPadOS | – | baut in CI ohne Signatur, verteilt wird erst mit dem Apple Developer Program |

Herunterladen: [www.rosenweg4303.ch/apps](https://www.rosenweg4303.ch/apps).

## Bedienung

Siehe [docs/anleitung.md](docs/anleitung.md). Kurz: Termine der eigenen STWEG(s)
(Bewohner, Eigentümer, Ausschuss, Verwaltung), Kooperation, Wartungen und
festgelegte Terminumfragen; „In Kalender übernehmen“ (.ics öffnen/teilen);
Erinnerungen vor Terminen und Meldung neuer Termine; Eintragen nur mit dem
Recht „STWEG-Termine“ und nur für die eigene STWEG (Technik, Präsident: alle).

## API (Haupt-API, Rosenweg/Website)

| Aufruf | Wofür |
|---|---|
| `GET /api/termine[?stweg=3,8\|alle]` | Termine der gewählten STWEGs (ohne = die eigenen), `stwegs` mit `schreiben` und `kalender` (Nextcloud-Kalender, falls eingerichtet) |
| `POST /api/stweg/:nr/events` | Termin anlegen (`title`, `start_date`, `end_date`, `all_day`, `location`, `description`, `category`) |
| `PUT /api/stweg/:nr/events/:id`, `DELETE …/:id` | ändern, löschen |

Schreiben: Technik/Präsident oder Recht `stweg-termine` schreiben und Ausschuss bzw.
`stwegN-verwaltung` dieser STWEG (`api/lib/termine.js`). Fehler am Feld kommen als
`{error, feld}` und stehen im Formular am Feld.

## Erinnerungen und Benachrichtigungen

- Erinnerungen plant die App selbst (Basis `Erinnerungen.abgleichen`): bei jedem
  Laden, im Hintergrund (Android WorkManager ~15 min, iOS BGAppRefreshTask
  `ch.rosenweg4303.termine.abfrage`) und am Computer alle 15 Minuten, solange die
  App läuft. Kein Push, kein ntfy.
- Neue Termine meldet die Abfrage (beim ersten Lauf still).
- Einstellungen (Vorlauf, neue melden, gewählte STWEGs, ausgeschaltete Termine)
  liegen in `termine-einstellungen.json` im App-Ordner – eine eigene Datei, weil
  die Abfrage im Hintergrund in einem eigenen Isolate liest.
- **Geteilte Telefone:** keine Erinnerungen, keine Abfrage (Basis).
- Abmelden entfernt die geplanten Erinnerungen.

## Farbe

Nach der freigeschalteten Funktion (Basis `docs/gruppenfarbe.md`): rot alle,
blau mit Recht `stweg-termine` (Ausschuss, Verwaltung), grün Technik/Präsident.
Logos in drei Farben aus `assets/logo/erzeugen.sh` (`FARBEN="verwaltung technik"`).

## Basis-Stand

`pubspec.yaml` zeigt bis zum nächsten Tag der Basis auf den Zweig
`termine-integration` (Rosenweg/rosenweg-basis#33 Kalenderdatei/Erinnerungen auf
#31, plus #36 Gruppenfarbe). Nach dem Tag auf `ref: v…` umstellen.

## Entwickeln

```sh
# rosenweg-basis daneben auschecken, dann lokal gegen sie bauen:
printf 'dependency_overrides:\n  rosenweg_basis:\n    path: ../rosenweg-basis\n' > pubspec_overrides.yaml
flutter pub get
flutter run -d macos                       # oder linux, windows, ein Handy
flutter run -d macos --dart-define=RW_ATTRAPPE=1   # ohne Server, mit Vorführdaten (lib/attrappe.dart)
flutter analyze && flutter test
RW_FOTO=$HOME/Downloads flutter test test/bildschirmfoto_test.dart   # Bildschirmfotos
```

Vor dem Commit `pubspec_overrides.yaml` entfernen und `flutter pub get` laufen lassen –
`pubspec.lock` darf nicht auf `../rosenweg-basis` zeigen (die CI bricht sonst ab).

| Ordner | Inhalt |
|---|---|
| `lib/app.dart` | `RosenwegApp`: Kennung `ch.rosenweg4303.termine`, Name, Logo |
| `lib/seiten/` | die Seiten der App (`RosenwegGeruest`: Handy unten, Desktop links) |
| `lib/attrappe.dart` | Vorführdaten statt der API (Tests, Bildschirmfotos) |
| `assets/logo/` | Logo aus dem Baukasten der Basis: `sh assets/logo/erzeugen.sh ../rosenweg-basis` |
| `linux/paket/` | Debian-Paket (`bauen.sh`, im Bau-Container `im-container.sh`), `paket.conf` = Vorlage für os-stationen |
| `macos/installer/` | DMG (`bauen.sh`) |
| `windows/installer/` | Inno-Setup-Installer |
| `.github/workflows/` | `app.yml` (Bau, Release) und `apps.yml` (an /apps) – die Arbeit macht rosenweg-basis |

## Veröffentlichen

1. Version in `pubspec.yaml` erhöhen (`version: x.y.z+n`, Baunummer immer mit).
2. Pull Request, CI grün (Linux und Android), Merge auf main.
3. Die CI baut alle fünf Plattformen, legt das Release `vx.y.z` an und schickt
   APK, `.deb`, DMG und Installer an `/apps`. Ohne neue Version passiert nach dem
   Merge nur die CI.
4. Stationen: `linux/paket/paket.conf` in os-stationen (`pakete/rosenweg-termine/`)
   mit Version und Prüfsumme nachführen.

## Lizenz

GPL-3.0-or-later, siehe [LICENSE](LICENSE). Logo-Zeichen: siehe rosenweg-basis
`werkzeug/logo/zeichen/LIZENZEN.md`.
