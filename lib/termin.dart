// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

/// Herkunft eines Termins (Feld `source` der API).
enum Quelle {
  /// Termin der STWEG (stweg_events) – nur diese lassen sich bearbeiten
  stweg('STWEG', Icons.event_outlined),

  /// Kooperation (gemeinsamer Google-Kalender aller STWEGs)
  kooperation('Kooperation', Icons.groups_outlined),

  /// Wartung aus einem Handwerker-Vertrag
  wartung('Wartung', Icons.build_outlined),

  /// festgelegte Terminumfrage (Sitzungs-Doodle)
  doodle('Terminumfrage', Icons.how_to_vote_outlined);

  const Quelle(this.text, this.symbol);
  final String text;
  final IconData symbol;

  static Quelle aus(Object? s) => Quelle.values.firstWhere((q) => q.name == s, orElse: () => Quelle.stweg);
}

/// Arten, die die API kennt (lib/termine.js KATEGORIEN), mit Text.
const arten = <String, String>{
  'versammlung': 'Versammlung',
  'sitzung': 'Sitzung',
  'wartung': 'Wartung',
  'reinigung': 'Reinigung',
  'entsorgung': 'Entsorgung',
  'anlass': 'Anlass',
  'sonstiges': 'Sonstiges',
};

String artText(String? a) => arten[a] ?? (a == 'stweg' ? 'STWEG' : 'Sonstiges');

String stwegText(int nr) => nr == 8 ? 'MEG' : 'STWEG $nr';

class Termin {
  const Termin({
    required this.schluessel,
    required this.titel,
    required this.beginn,
    this.id,
    this.ende,
    this.ganztags = false,
    this.ort,
    this.beschreibung,
    this.art,
    this.quelle = Quelle.stweg,
    this.stweg,
    this.stwegs = const [],
  });

  /// Fest je Termin und Quelle, z. B. `stweg-42`, `wartung-7`, `kooperation-…`.
  final String schluessel;

  /// Nummer in stweg_events (nur Quelle stweg), sonst null.
  final int? id;
  final String titel;

  /// Lokale Zeit; ganztags: Mitternacht des Tages.
  final DateTime beginn;
  final DateTime? ende;
  final bool ganztags;
  final String? ort;
  final String? beschreibung;
  final String? art;
  final Quelle quelle;

  /// STWEG des Termins (null = Kooperation, Wartung ohne STWEG).
  final int? stweg;

  /// In welchen der gezeigten STWEGs der Termin vorkommt.
  final List<int> stwegs;

  bool get bearbeitbar => quelle == Quelle.stweg && id != null && stweg != null;

  /// Ganztags-Termine ohne Zeit ("2026-12-03") oder um Mitternacht.
  static DateTime? _zeit(Object? v, {bool ganztags = false}) {
    if (v == null || v == '') return null;
    final s = '$v';
    final nurDatum = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s);
    final d = DateTime.tryParse(s);
    if (d == null) return null;
    final lokal = nurDatum ? d : d.toLocal();
    return ganztags || nurDatum ? DateTime(lokal.year, lokal.month, lokal.day) : lokal;
  }

  static Termin? aus(Map<String, dynamic> j) {
    final quelle = Quelle.aus(j['source']);
    final ganz = j['all_day'] == true || RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch('${j['start']}');
    final beginn = _zeit(j['start'], ganztags: ganz);
    // Wartungen/Umfragen kommen mit Zeichen vorne (🔧, 🗓️); das zeigt hier das Symbol der Quelle
    final titel = '${j['title'] ?? ''}'.trim().replaceFirst(RegExp(r'^[^\p{L}\p{N}]+', unicode: true), '').trim();
    if (beginn == null || titel.isEmpty) return null;
    final roheId = j['id'];
    final id = quelle == Quelle.stweg ? (roheId is int ? roheId : int.tryParse('${roheId ?? ''}')) : null;
    final st = j['stweg'];
    final stwegs = [for (final x in (j['stwegs'] as List? ?? const [])) if (x is int) x];
    return Termin(
      schluessel: switch (quelle) {
        Quelle.stweg => 'stweg-$id',
        Quelle.kooperation => 'kooperation-${beginn.toIso8601String()}-$titel',
        _ => '${roheId ?? '${quelle.name}-$titel-${beginn.toIso8601String()}'}',
      },
      id: id,
      titel: titel,
      beginn: beginn,
      ende: _zeit(j['end'], ganztags: ganz),
      ganztags: ganz,
      ort: _text(j['location']),
      beschreibung: _text(j['description']),
      art: _text(j['category']),
      quelle: quelle,
      stweg: st is int ? st : int.tryParse('${st ?? ''}'),
      stwegs: stwegs.isEmpty && st is int ? [st] : stwegs,
    );
  }

  static String? _text(Object? v) {
    final s = v == null ? '' : '$v'.trim();
    return s.isEmpty ? null : s;
  }

  /// Vorbei: Ende (ohne Ende: Beginn + 1 h) liegt zurueck; ganztags: der letzte Tag ist vorbei.
  bool vorbei(DateTime jetzt) {
    final e = ende ?? beginn;
    if (ganztags) return !jetzt.isBefore(DateTime(e.year, e.month, e.day + 1));
    return (ende ?? beginn.add(Kalenderdatei.standardDauer)).isBefore(jetzt);
  }

  /// "Donnerstag, 3.12.2026 · 19:00–21:00" bzw. "… · ganztags".
  String get wannText {
    final tag = tagLangText(beginn);
    if (ganztags) {
      final e = ende;
      if (e != null && !_gleicherTag(e, beginn)) return '$tag – ${tagLangText(e)}';
      return '$tag · ganztags';
    }
    final e = ende;
    if (e == null) return '$tag · ${uhrText(beginn)}';
    if (_gleicherTag(e, beginn)) return '$tag · ${uhrText(beginn)}–${uhrText(e)}';
    return '$tag ${uhrText(beginn)} – ${tagLangText(e)} ${uhrText(e)}';
  }

  /// Fuer die Kalenderdatei; [erinnerung] = VALARM.
  KalenderTermin alsKalender({Duration? erinnerung}) => KalenderTermin(
        uid: '${schluessel.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-')}@termine.rosenweg4303.ch',
        titel: titel,
        beginn: beginn,
        ende: ende,
        ganztags: ganztags,
        ort: ort,
        beschreibung: [
          ?beschreibung,
          if (stwegs.isNotEmpty) stwegs.map(stwegText).join(', ') else if (quelle == Quelle.kooperation) 'Kooperation Rosenweg',
        ].join('\n\n'),
        erinnerung: erinnerung,
      );

  /// Formularwerte fuer POST/PUT /api/stweg/:nr/events.
  static Map<String, Object?> formular({
    required String titel,
    required DateTime beginn,
    DateTime? ende,
    required bool ganztags,
    String? ort,
    String? beschreibung,
    required String art,
  }) =>
      {
        'title': titel.trim(),
        // ganztags: Mittag, damit die Zeitzone den Tag nie verschiebt
        'start_date': (ganztags ? DateTime(beginn.year, beginn.month, beginn.day, 12) : beginn).toUtc().toIso8601String(),
        'end_date': ende == null ? null : (ganztags ? DateTime(ende.year, ende.month, ende.day, 12) : ende).toUtc().toIso8601String(),
        'all_day': ganztags,
        'location': ort?.trim() ?? '',
        'description': beschreibung?.trim() ?? '',
        'category': art,
      };
}

bool _gleicherTag(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Eine STWEG, deren Termine die Person sehen darf (GET /api/termine `stwegs`).
class TermineStweg {
  const TermineStweg({required this.nr, required this.name, this.eigene = false, this.schreiben = false, this.gezeigt = false, this.kalender, this.kalenderUrl});
  final int nr;
  final String name;
  final bool eigene;
  final bool schreiben;
  final bool gezeigt;

  /// Nextcloud-Kalender, in dem die Termine schon stehen (sonst null).
  final String? kalender;
  final Uri? kalenderUrl;

  factory TermineStweg.aus(Map<String, dynamic> j) {
    final k = j['kalender'];
    final nr = j['nr'] as int;
    return TermineStweg(
      nr: nr,
      name: '${j['name'] ?? stwegText(nr)}',
      eigene: j['eigene'] == true,
      schreiben: j['schreiben'] == true,
      gezeigt: j['gezeigt'] == true,
      kalender: k is Map && k['name'] is String ? k['name'] as String : null,
      kalenderUrl: k is Map && k['url'] is String ? Uri.tryParse(k['url'] as String) : null,
    );
  }
}

class TermineStand {
  const TermineStand({required this.stwegs, required this.termine});
  final List<TermineStweg> stwegs;
  final List<Termin> termine;

  factory TermineStand.aus(Map<String, dynamic> j) => TermineStand(
        stwegs: [for (final s in (j['stwegs'] as List? ?? const [])) if (s is Map<String, dynamic>) TermineStweg.aus(s)],
        termine: [
          for (final t in (j['termine'] as List? ?? const []))
            if (t is Map<String, dynamic>) ?Termin.aus(t),
        ],
      );

  List<TermineStweg> get schreibbar => [for (final s in stwegs) if (s.schreiben) s];
  bool darfBearbeiten(Termin t) => t.bearbeitbar && stwegs.any((s) => s.nr == t.stweg && s.schreiben);
  TermineStweg? stweg(int? nr) => nr == null ? null : stwegs.where((s) => s.nr == nr).firstOrNull;

  /// Nextcloud-Kalender, in dem dieser Termin schon steht (falls einer bekannt ist).
  TermineStweg? kalenderFuer(Termin t) {
    for (final nr in t.stweg != null ? [t.stweg!] : t.stwegs) {
      final s = stweg(nr);
      if (s?.kalender != null) return s;
    }
    return null;
  }
}

/// Zugriff auf die Haupt-API.
class TermineApi {
  TermineApi(this.api);
  final RosenwegApi api;

  /// [stwegs] null = die eigenen (Vorgabe der API), sonst genau diese.
  Future<TermineStand> laden({Set<int>? stwegs}) async {
    final q = stwegs == null || stwegs.isEmpty ? '' : '?stweg=${(stwegs.toList()..sort()).join(',')}';
    return TermineStand.aus(await api.objekt('/api/termine$q'));
  }

  Future<void> anlegen(int stweg, Map<String, Object?> werte) => api.post('/api/stweg/$stweg/events', werte);
  Future<void> aendern(Termin t, Map<String, Object?> werte) => api.put('/api/stweg/${t.stweg}/events/${t.id}', werte);
  Future<void> loeschen(Termin t) => api.delete('/api/stweg/${t.stweg}/events/${t.id}');
}
