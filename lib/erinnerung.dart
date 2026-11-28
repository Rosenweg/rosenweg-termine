// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

import 'termin.dart';

/// Wie lange vor einem Termin erinnert wird.
enum Vorlauf {
  aus('Keine Erinnerung', null),
  viertelstunde('15 Minuten vorher', Duration(minutes: 15)),
  stunde('1 Stunde vorher', Duration(hours: 1)),
  dreiStunden('3 Stunden vorher', Duration(hours: 3)),
  tag('1 Tag vorher', Duration(days: 1));

  const Vorlauf(this.text, this.dauer);
  final String text;
  final Duration? dauer;

  static Vorlauf aus_(Object? s) => Vorlauf.values.firstWhere((v) => v.name == s, orElse: () => Vorlauf.stunde);
}

/// Einstellungen der Person auf diesem Geraet. Eigene kleine Datei (nicht
/// [AppSpeicher]): die Abfrage im Hintergrund laeuft in einem eigenen Isolate
/// und muss jedes Mal den aktuellen Stand lesen.
class TermineEinstellungen {
  TermineEinstellungen({this.vorlauf = Vorlauf.stunde, this.neueMelden = true, Set<String>? ohneErinnerung, this.stwegs})
      : ohneErinnerung = ohneErinnerung ?? {};

  Vorlauf vorlauf;

  /// Benachrichtigung, wenn ein neuer Termin dazukommt.
  bool neueMelden;

  /// Termine (Schluessel), fuer die die Person die Erinnerung ausgeschaltet hat.
  final Set<String> ohneErinnerung;

  /// Gewaehlte STWEGs (null = die eigenen, wie die API vorgibt).
  Set<int>? stwegs;

  /// Fuer Tests: statt der Datei.
  @visibleForTesting
  static Map<String, Object?>? attrappe;

  static Future<File> _datei() async {
    final d = await getApplicationSupportDirectory();
    await d.create(recursive: true);
    return File('${d.path}${Platform.pathSeparator}termine-einstellungen.json');
  }

  static Future<TermineEinstellungen> laden() async {
    Map<String, Object?> j = attrappe ?? {};
    if (attrappe == null) {
      try {
        final f = await _datei();
        if (await f.exists()) {
          final roh = jsonDecode(await f.readAsString());
          if (roh is Map) j = roh.cast<String, Object?>();
        }
      } catch (e) {
        Protokoll.schreiben('Einstellungen lesen', e);
      }
    }
    final st = j['stwegs'];
    return TermineEinstellungen(
      vorlauf: Vorlauf.aus_(j['vorlauf']),
      neueMelden: j['neue_melden'] != false,
      ohneErinnerung: {for (final x in (j['ohne_erinnerung'] as List? ?? const [])) '$x'},
      stwegs: st is List ? {for (final x in st) if (x is int) x} : null,
    );
  }

  Map<String, Object?> get _json => {
        'vorlauf': vorlauf.name,
        'neue_melden': neueMelden,
        'ohne_erinnerung': ohneErinnerung.toList(),
        if (stwegs != null) 'stwegs': stwegs!.toList(),
      };

  Future<void> speichern() async {
    if (attrappe != null) {
      attrappe = _json;
      return;
    }
    try {
      await (await _datei()).writeAsString(jsonEncode(_json), flush: true);
    } catch (e) {
      Protokoll.schreiben('Einstellungen speichern', e);
    }
  }

  bool erinnert(Termin t) => vorlauf.dauer != null && !ohneErinnerung.contains(t.schluessel);
}

/// Wann erinnert wird: [Vorlauf] vor dem Beginn; ganztags um 8 Uhr am Tag
/// (bzw. am Vortag bei "1 Tag vorher").
DateTime? erinnerungsZeit(Termin t, Vorlauf v) {
  final d = v.dauer;
  if (d == null) return null;
  if (t.ganztags) {
    final tag = t.beginn.subtract(d >= const Duration(days: 1) ? const Duration(days: 1) : Duration.zero);
    return DateTime(tag.year, tag.month, tag.day, 8);
  }
  return t.beginn.subtract(d);
}

/// Text der Erinnerung: "Heute 19:00 · Gemeinschaftsraum".
String erinnerungsText(Termin t, DateTime wann) {
  final heute = wann.year == t.beginn.year && wann.month == t.beginn.month && wann.day == t.beginn.day;
  final tag = heute ? 'Heute' : (t.beginn.difference(DateTime(wann.year, wann.month, wann.day)).inDays == 1 ? 'Morgen' : tagLangText(t.beginn));
  return [
    t.ganztags ? '$tag (ganztags)' : '$tag ${uhrText(t.beginn)}',
    ?t.ort,
  ].join(' · ');
}

/// Soll-Stand der Erinnerungen fuer [Erinnerungen.abgleichen].
List<Erinnerung> erinnerungenFuer(Iterable<Termin> termine, TermineEinstellungen e) => [
      for (final t in termine)
        if (e.erinnert(t))
          if (erinnerungsZeit(t, e.vorlauf) case final wann?)
            Erinnerung(
              schluessel: t.schluessel,
              wann: wann,
              titel: t.titel,
              text: erinnerungsText(t, wann),
              ziel: 'termin/${t.schluessel}',
            ),
    ];

/// Laedt die Termine und gleicht die Erinnerungen ab; meldet neue Termine
/// (seit dem letzten Mal, beim ersten Mal still). Im Hintergrund
/// (Android WorkManager, iOS) und am Computer alle 15 Minuten, solange die
/// App laeuft. Nie auf geteilten Telefonen (Basis).
Future<void> termineAbfrage(HintergrundKontext k) async {
  final e = await TermineEinstellungen.laden();
  final stand = await TermineApi(k.sitzung.api).laden(stwegs: e.stwegs);
  await Erinnerungen.abgleichen(k.sitzung, erinnerungenFuer(stand.termine, e));
  final jetzt = DateTime.now();
  final kommend = [for (final t in stand.termine) if (!t.vorbei(jetzt)) t];
  final neu = await Neuigkeiten(k.speicher, 'termine').vergleichen({
    for (final t in kommend) t.schluessel: '${t.beginn.toIso8601String()}|${t.titel}',
  });
  if (!e.neueMelden) return;
  for (final t in kommend) {
    if (!neu.contains(t.schluessel)) continue;
    await Benachrichtigung.zeigen(
      id: Benachrichtigung.idFuer('neu-${t.schluessel}'),
      titel: 'Termin: ${t.titel}',
      text: [t.wannText, ?t.ort].join(' · '),
      ziel: 'termin/${t.schluessel}',
      kanal: 'termine',
    );
  }
}
