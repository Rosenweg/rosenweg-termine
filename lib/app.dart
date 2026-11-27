// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/painting.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

/// Angaben der App fuer rosenweg_basis.
///
/// kennung = applicationId (Android) = Bundle-ID (iOS/macOS) = GTK-ID (Linux)
/// = Schema des Ruecksprungs (ch.rosenweg4303.termine:/anmeldung, in Authentik
/// bei rosenweg-apps eintragen) = Paket im App-Katalog (/apps, Updater).
const appAngaben = RosenwegApp(
  kennung: 'ch.rosenweg4303.termine',
  name: 'Rosenweg Termine',
  ordner: 'rosenweg-termine',
  beschreibung: 'Termine und Versammlungen deiner STWEG: ansehen, in den Kalender übernehmen, erinnern lassen.',
  quelle: 'https://github.com/Rosenweg/rosenweg-termine',
  logo: AssetImage('assets/logo/rosenweg-termine-512.png'),
  // Farbe des Anmeldeschirms wie der Logo-Grund (assets/logo/erzeugen.sh GRUPPE);
  // neue-app.sh setzt sie aus werkzeug/logo/flutter-apps.txt
  gruppe: RosenwegGruppe.bewohner,
  // Farbe nach dem, was die App freischaltet (rosenweg_basis docs/gruppenfarbe.md):
  // rot alle, blau wer Termine schreiben darf (Recht stweg-termine: Ausschuss und
  // Verwaltung ihrer STWEG), gruen Technik und Praesident
  farbGruppen: {RosenwegGruppe.verwaltung, RosenwegGruppe.technik},
  farbRechte: {'stweg-termine'},
);

/// --dart-define=RW_ATTRAPPE=1: ohne Anmeldung und ohne Server, mit
/// erfundenen Vorfuehrdaten (Entwicklung, Bildschirmfotos, Tests).
const attrappe = bool.fromEnvironment('RW_ATTRAPPE');
