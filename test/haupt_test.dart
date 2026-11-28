// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';
import 'package:rosenweg_termine/app.dart';
import 'package:rosenweg_termine/attrappe.dart';
import 'package:rosenweg_termine/erinnerung.dart';
import 'package:rosenweg_termine/seiten/haupt.dart';
import 'package:rosenweg_termine/termin.dart';

void main() {
  setUpAll(() => Protokoll.nurKonsole = true);
  setUp(() {
    Benachrichtigung.attrappe = [];
    TermineEinstellungen.attrappe = {};
  });

  Future<(Attrappe, RosenwegSitzung)> zeigen(WidgetTester t, {Size groesse = const Size(412, 860), Attrappe? a, bool geteilt = false}) async {
    t.view.physicalSize = groesse;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final at = a ?? Attrappe();
    final s = RosenwegSitzung(appAngaben, transport: at);
    await s.starten();
    s.geteiltesTelefon = geteilt;
    await t.pumpWidget(RosenwegRahmen(sitzung: s, inhalt: (_) => Haupt(sitzung: s)));
    await t.pumpAndSettle();
    return (at, s);
  }

  Future<void> oeffnen(WidgetTester t, String titel) async {
    final liste = find.byType(Scrollable).first;
    await t.scrollUntilVisible(find.text(titel), 200, scrollable: liste);
    // nicht unter dem Knopf "Neuer Termin" tippen
    if (t.getCenter(find.text(titel)).dy > t.view.physicalSize.height / t.view.devicePixelRatio - 180) {
      await t.drag(liste, const Offset(0, -160));
      await t.pumpAndSettle();
    }
    await t.tap(find.text(titel));
    await t.pumpAndSettle();
  }

  final formListe = find.descendant(of: find.byType(RosenwegFormular), matching: find.byType(Scrollable)).first;

  Future<void> speichern(WidgetTester t) async {
    final k = find.byKey(const Key('formular-speichern'));
    await t.scrollUntilVisible(k, 300, scrollable: formListe);
    await t.pumpAndSettle();
    await t.tap(k);
    await t.pumpAndSettle();
  }

  testWidgets('Handy: kommende Termine nach Monat, vergangene nur auf Wunsch', (t) async {
    final (a, _) = await zeigen(t);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Ausschusssitzung STWEG 3'), findsOneWidget);
    expect(find.text('Grillabend im Hof'), findsNothing);
    expect(a.anfragen.any((r) => r.pfad == '/api/termine'), isTrue);
    await t.tap(find.text('Vergangene'));
    await t.pumpAndSettle();
    expect(find.text('Grillabend im Hof'), findsOneWidget);
  });

  testWidgets('STWEG wählen: MEG ausblenden lädt ?stweg=3 und merkt es sich', (t) async {
    final (a, _) = await zeigen(t);
    await t.scrollUntilVisible(find.text('Reinigung Tiefgarage'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('MEG'), findsWidgets, reason: 'STWEG steht in der Zeile, wenn mehrere gezeigt sind');
    await t.scrollUntilVisible(find.widgetWithText(FilterChip, 'MEG'), -200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.widgetWithText(FilterChip, 'MEG'));
    await t.pumpAndSettle();
    expect(a.anfragen.last.pfad, '/api/termine?stweg=3');
    expect(find.text('Reinigung Tiefgarage'), findsNothing);
    expect(TermineEinstellungen.attrappe!['stwegs'], [3]);
    // die letzte gezeigte bleibt
    await t.tap(find.widgetWithText(FilterChip, 'STWEG 3'));
    await t.pumpAndSettle();
    expect(a.anfragen.last.pfad, '/api/termine?stweg=3');
  });

  testWidgets('Termin: Angaben, Kalender-Knöpfe, Bearbeiten nur für STWEG-Termine mit Recht', (t) async {
    await zeigen(t);
    await oeffnen(t, 'Eigentümerversammlung 2027');
    expect(find.text('Gemeinschaftsraum Haus 9'), findsOneWidget);
    expect(find.textContaining('Traktanden'), findsOneWidget);
    expect(find.text('In Kalender übernehmen'), findsOneWidget);
    expect(find.text('Teilen (.ics)'), findsOneWidget);
    expect(find.byTooltip('Bearbeiten'), findsOneWidget);
    expect(find.textContaining('Nextcloud-Kalender'), findsNothing);
    await t.tap(find.byTooltip('Zurück'));
    await t.pumpAndSettle();
    await oeffnen(t, 'Service Lift');
    expect(find.byTooltip('Bearbeiten'), findsNothing, reason: 'Wartung pflegt man beim Handwerker');
  });

  testWidgets('Nextcloud-Kalender bekannt: Hinweis vor dem Übernehmen', (t) async {
    await zeigen(t, a: Attrappe(kalender: {3: 'STWEG 3 – Termine'}));
    await oeffnen(t, 'Eigentümerversammlung 2027');
    expect(find.textContaining('Nextcloud-Kalender „STWEG 3 – Termine“'), findsOneWidget);
    expect(find.text('Nextcloud-Kalender öffnen'), findsOneWidget);
  });

  testWidgets('Neuer Termin: Pflichtfelder, Fehler am Feld, POST mit API-Feldern', (t) async {
    final (a, _) = await zeigen(t);
    await t.tap(find.text('Neuer Termin'));
    await t.pumpAndSettle();
    // zwei STWEGs sichtbar, aber nur in STWEG 3 schreiben: kein Auswahlfeld
    expect(find.text('Für die STWEG 3'), findsOneWidget);
    await speichern(t);
    expect(find.text('Bitte die markierten Felder prüfen.'), findsWidgets);
    expect(a.anfragen.where((r) => r.methode == 'POST'), isEmpty);
    // Meldung unten verschwinden lassen (deckt sonst den Knopf)
    await t.pump(const Duration(seconds: 6));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField).first, 'Velokeller räumen');
    await t.tap(find.text('Ganztags'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.textContaining(RegExp(r'^Tag')), -300, scrollable: formListe);
    await t.pumpAndSettle();
    await t.tap(find.textContaining(RegExp(r'^Tag')));
    await t.pumpAndSettle();
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    await speichern(t);
    final post = a.anfragen.singleWhere((r) => r.methode == 'POST');
    expect(post.pfad, '/api/stweg/3/events');
    final k = post.koerper! as Map;
    expect(k['title'], 'Velokeller räumen');
    expect(k['all_day'], true);
    expect(k['category'], 'sonstiges');
    expect(DateTime.parse('${k['start_date']}').toLocal().hour, 12, reason: 'ganztags: Mittag, Tag sicher');
    expect(find.text('Neuer Termin'), findsOneWidget, reason: 'zurück in der Liste (Knopf)');
    expect(find.text('Velokeller räumen'), findsOneWidget);
  });

  testWidgets('Bearbeiten (PUT) und Löschen (DELETE) mit Rückfrage', (t) async {
    final (a, _) = await zeigen(t);
    await oeffnen(t, 'Ausschusssitzung STWEG 3');
    await t.tap(find.byTooltip('Bearbeiten'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField).first, 'Ausschusssitzung (verschoben)');
    await speichern(t);
    expect(a.anfragen.singleWhere((r) => r.methode == 'PUT').pfad, '/api/stweg/3/events/100');
    expect(find.text('Ausschusssitzung (verschoben)'), findsWidgets);
    await t.tap(find.byTooltip('Löschen'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Löschen'));
    await t.pumpAndSettle();
    expect(a.anfragen.singleWhere((r) => r.methode == 'DELETE').pfad, '/api/stweg/3/events/100');
    expect(find.text('Ausschusssitzung (verschoben)'), findsNothing);
  });

  testWidgets('Ohne Schreibrecht: kein „Neuer Termin“, kein Bearbeiten', (t) async {
    await zeigen(t, a: Attrappe(gruppen: const ['r9-bewohner', 'meg-bewohner'], schreiben: const {}));
    expect(find.text('Neuer Termin'), findsNothing);
    await oeffnen(t, 'Eigentümerversammlung 2027');
    expect(find.byTooltip('Bearbeiten'), findsNothing);
    expect(find.byTooltip('Löschen'), findsNothing);
  });

  testWidgets('Erinnerungen: 1 h vorher geplant; „aus“ entfernt, einzelner Termin aus', (t) async {
    await zeigen(t);
    final geplant = Benachrichtigung.attrappe!.where((x) => x.wann != null).toList();
    expect(geplant, isNotEmpty);
    final vers = geplant.where((x) => x.titel == 'Eigentümerversammlung 2027').single;
    expect(vers.ziel, startsWith('termin/stweg-'));
    expect(vers.text, contains('Gemeinschaftsraum Haus 9'));
    // einzeln ausschalten
    await oeffnen(t, 'Eigentümerversammlung 2027');
    await t.tap(find.text('Erinnern'));
    await t.pumpAndSettle();
    expect(Benachrichtigung.attrappe!.where((x) => x.titel == 'Eigentümerversammlung 2027'), isEmpty);
    await t.tap(find.byTooltip('Zurück'));
    await t.pumpAndSettle();
    // alle aus
    await t.tap(find.text('Erinnerungen').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Keine Erinnerung'));
    await t.pumpAndSettle();
    expect(Benachrichtigung.attrappe!.where((x) => x.wann != null), isEmpty);
    expect(TermineEinstellungen.attrappe!['vorlauf'], 'aus');
  });

  testWidgets('Geteiltes Telefon: keine Erinnerungen, Hinweis', (t) async {
    await zeigen(t, geteilt: true);
    expect(Benachrichtigung.attrappe!.where((x) => x.wann != null), isEmpty);
    await t.tap(find.text('Erinnerungen').last);
    await t.pumpAndSettle();
    expect(find.textContaining('Auf geteilten Telefonen erinnert die App nicht'), findsOneWidget);
    expect(find.text('Alle in Kalender übernehmen'), findsOneWidget);
  });

  testWidgets('Desktop (Station): Leiste links', (t) async {
    await zeigen(t, groesse: const Size(1280, 800));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('Fehler beim Laden: Nochmals', (t) async {
    final a = Attrappe()..erzwungen['GET /api/termine'] = (status: 503, json: {'error': 'Wartung'});
    // nur einmal: danach antwortet die Attrappe wieder
    await zeigen(t, a: a);
    expect(find.text('Nochmals'), findsOneWidget);
    await t.tap(find.text('Nochmals'));
    await t.pumpAndSettle();
    expect(find.text('Ausschusssitzung STWEG 3'), findsOneWidget);
  });

  group('Modell', () {
    test('Termin.aus: nur Datum = ganztags, UTC → lokal, Schlüssel je Quelle', () {
      expect(Termin.aus({'title': '🗓️ Begehung', 'start': '2026-12-03'})!.titel, 'Begehung');
      final w = Termin.aus({'id': 'wartung-7', 'title': 'Lift', 'start': '2026-12-10', 'source': 'wartung', 'stwegs': [3, 5]})!;
      expect(w.ganztags, isTrue);
      expect(w.beginn, DateTime(2026, 12, 10));
      expect(w.schluessel, 'wartung-7');
      expect(w.bearbeitbar, isFalse);
      final s = Termin.aus({'id': 42, 'title': 'Sitzung', 'start': '2026-12-03T18:00:00.000Z', 'source': 'stweg', 'stweg': 3})!;
      expect(s.beginn, DateTime.utc(2026, 12, 3, 18).toLocal());
      expect(s.schluessel, 'stweg-42');
      expect(s.stwegs, [3]);
      expect(s.bearbeitbar, isTrue);
      expect(Termin.aus({'title': '', 'start': '2026-12-03'}), isNull);
    });

    test('Kalenderdatei des Termins: UID fest, STWEG in der Beschreibung', () {
      final s = Termin.aus({'id': 42, 'title': 'Sitzung', 'start': '2026-12-03T18:00:00.000Z', 'source': 'stweg', 'stweg': 3, 'location': 'Raum'})!;
      final ics = utf8.decode(Kalenderdatei.datei([s.alsKalender(erinnerung: const Duration(hours: 1))]).bytes);
      expect(ics, contains('UID:stweg-42@termine.rosenweg4303.ch'));
      expect(ics, contains('DTSTART:20261203T180000Z'));
      expect(ics, contains('LOCATION:Raum'));
      expect(ics, contains('STWEG 3'));
      expect(ics, contains('TRIGGER:-PT1H'));
    });

    test('Erinnerungszeit: Vorlauf; ganztags 8 Uhr (1 Tag: am Vortag)', () {
      final t = Termin(schluessel: 'a', titel: 'A', beginn: DateTime(2027, 1, 5, 19));
      expect(erinnerungsZeit(t, Vorlauf.stunde), DateTime(2027, 1, 5, 18));
      expect(erinnerungsZeit(t, Vorlauf.aus), isNull);
      final g = Termin(schluessel: 'b', titel: 'B', beginn: DateTime(2027, 1, 5), ganztags: true);
      expect(erinnerungsZeit(g, Vorlauf.stunde), DateTime(2027, 1, 5, 8));
      expect(erinnerungsZeit(g, Vorlauf.tag), DateTime(2027, 1, 4, 8));
      expect(erinnerungsText(t, DateTime(2027, 1, 5, 18)), 'Heute 19:00');
    });
  });

  test('Abfrage im Hintergrund: erstes Mal still, danach neue Termine melden', () async {
    final a = Attrappe();
    final s = RosenwegSitzung(appAngaben, transport: a);
    await s.hintergrundStarten();
    final k = HintergrundKontext(sitzung: s, speicher: AppSpeicher.imSpeicher(), imHintergrund: true);
    await termineAbfrage(k);
    expect(Benachrichtigung.attrappe!.where((x) => x.wann == null), isEmpty);
    expect(Benachrichtigung.attrappe!.where((x) => x.wann != null), isNotEmpty, reason: 'Erinnerungen geplant');
    await a.senden('POST', '/api/stweg/3/events', koerper: {
      'title': 'Neue Sitzung', 'start_date': DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String(),
    });
    await termineAbfrage(k);
    final neu = Benachrichtigung.attrappe!.where((x) => x.wann == null).single;
    expect(neu.titel, 'Termin: Neue Sitzung');
    expect(neu.ziel, startsWith('termin/stweg-'));
  });

  testWidgets('Farbe nach Freischaltung: rot Bewohner, blau mit Schreibrecht, grün Technik', (t) async {
    Future<RosenwegGruppe> farbe(Attrappe a) async {
      await t.pumpWidget(const SizedBox());
      final s = RosenwegSitzung(appAngaben, transport: a);
      // wie in der Basis: Rahmen zuerst, dann anmelden (die Farbe folgt der Anmeldung)
      await t.pumpWidget(RosenwegRahmen(sitzung: s, inhalt: (_) => Haupt(sitzung: s)));
      await t.runAsync(s.starten);
      await t.pumpAndSettle();
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pumpAndSettle();
      return s.farbe.value;
    }

    expect(await farbe(Attrappe(gruppen: const ['r9-bewohner'], schreiben: const {})), RosenwegGruppe.bewohner);
    expect(await farbe(Attrappe()), RosenwegGruppe.verwaltung);
    expect(await farbe(Attrappe(gruppen: const ['technik'], schreiben: const {3, 8})), RosenwegGruppe.technik);
  });

  test('Kennung, Ordner und Logo passen zusammen', () {
    expect(appAngaben.kennung, 'ch.rosenweg4303.termine');
    expect(appAngaben.gruppe, RosenwegGruppe.bewohner);
    expect(File('assets/logo/${appAngaben.ordner}-512.png').existsSync(), isTrue);
    expect(File('assets/logo/${appAngaben.ordner}-klein.png').existsSync(), isTrue);
  });
}
