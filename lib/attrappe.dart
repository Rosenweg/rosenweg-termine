// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:rosenweg_basis/rosenweg_basis.dart';

/// Antwortet wie die Haupt-API (GET /api/termine, Termine der STWEG anlegen,
/// aendern, loeschen), mit erfundenen Daten – keine echten Personen oder
/// Termine. Fuer Tests, Bildschirmfotos und Entwicklung ohne Server
/// (--dart-define=RW_ATTRAPPE=1).
///
/// Vorgabe: Erika Muster, Eigentuemerin in STWEG 3 und im Ausschuss der
/// STWEG 3 (darf dort schreiben), Bewohnerin der MEG (nur lesen).
class Attrappe implements Transport {
  Attrappe({
    this.gruppen = const ['r9-eigentuemer', 'stweg3-ausschuss', 'meg-bewohner'],
    this.schreiben = const {3},
    DateTime? heute,
    this.kalender = const {},
  }) : heute = heute ?? DateTime.now() {
    _termineAnlegen();
  }

  final List<String> gruppen;

  /// STWEGs mit Schreibrecht.
  final Set<int> schreiben;
  final DateTime heute;

  /// Nextcloud-Kalender je STWEG (Name), wie TERMINE_NEXTCLOUD_KALENDER.
  final Map<int, String> kalender;

  final anfragen = <({String methode, String pfad, Object? koerper})>[];
  final erzwungen = <String, ApiAntwort>{};

  final _eigene = <Map<String, dynamic>>[];
  var _naechsteId = 100;

  static const _sichtbar = [3, 8];

  DateTime _tag(int plus, [int stunde = 0, int minute = 0]) => DateTime(heute.year, heute.month, heute.day + plus, stunde, minute);

  void _termineAnlegen() {
    void neu(int stweg, String titel, DateTime start, {DateTime? ende, bool ganz = false, String? ort, String? text, String art = 'sonstiges'}) {
      _eigene.add({
        'id': _naechsteId++, 'stweg': stweg, 'title': titel,
        'start': (ganz ? DateTime(start.year, start.month, start.day, 12) : start).toUtc().toIso8601String(),
        'end': ende?.toUtc().toIso8601String(), 'all_day': ganz, 'location': ort, 'description': text, 'category': art,
      });
    }

    neu(3, 'Ausschusssitzung STWEG 3', _tag(2, 19, 30), ende: _tag(2, 21), ort: 'Sitzungszimmer Haus 9', art: 'sitzung');
    neu(3, 'Treppenhausreinigung', _tag(6), ganz: true, text: 'Bitte Velos und Schuhe aus dem Treppenhaus nehmen.', art: 'reinigung');
    neu(3, 'Eigentümerversammlung 2027', _tag(19, 19), ende: _tag(19, 21, 30), ort: 'Gemeinschaftsraum Haus 9',
        text: 'Traktanden: Jahresrechnung, Budget, Erneuerungsfonds, Wahlen.', art: 'versammlung');
    neu(8, 'Reinigung Tiefgarage', _tag(11, 7), ende: _tag(11, 12), ort: 'Einstellhalle', text: 'Fahrzeuge bitte bis 7 Uhr wegstellen.', art: 'reinigung');
    neu(3, 'Grillabend im Hof', _tag(-3, 18), ort: 'Innenhof', art: 'anlass');
  }

  Map<String, dynamic> _alsTermin(Map<String, dynamic> e) => {
        'id': e['id'], 'title': e['title'], 'description': e['description'], 'start': e['start'], 'end': e['end'],
        'location': e['location'], 'category': e['category'], 'all_day': e['all_day'], 'source': 'stweg',
        'stweg': e['stweg'], 'stwegs': [e['stweg']],
      };

  List<Map<String, dynamic>> _termine(List<int> stwegs) {
    final virtuell = <Map<String, dynamic>>[
      {
        'title': 'Hauptversammlung Kooperation', 'start': _tag(26, 19).toUtc().toIso8601String(), 'location': 'Gemeindesaal',
        'description': 'Gemeinsame Versammlung aller STWEGs.', 'source': 'kooperation', 'stweg': null, 'stwegs': stwegs,
      },
      {
        'id': 'wartung-7', 'title': '🔧 Service Lift', 'start': _tag(9).toIso8601String().substring(0, 10), 'all_day': true,
        'description': 'Musterlift AG (Lift)', 'category': 'wartung', 'source': 'wartung', 'stweg': null, 'stwegs': stwegs,
      },
      if (stwegs.contains(3))
        {
          'id': 'doodle-4', 'title': '🗓️ Begehung Dach', 'start': _tag(14, 17).toUtc().toIso8601String(), 'location': 'Haus 9',
          'description': 'Sitzungstermin (aus Terminumfrage)', 'category': 'sitzung', 'source': 'doodle', 'stweg': 3, 'stwegs': [3],
        },
    ];
    return [
      for (final e in _eigene)
        if (stwegs.contains(e['stweg'])) _alsTermin(e),
      ...virtuell,
    ]..sort((a, b) => DateTime.parse('${a['start']}').compareTo(DateTime.parse('${b['start']}')));
  }

  ApiAntwort _fehler(int status, String text, [String? feld]) => (status: status, json: {'error': text, 'feld': ?feld});

  ApiAntwort? _pruefen(Object? k, {bool teilweise = false}) {
    final b = k is Map ? k : const {};
    if ((!teilweise || b.containsKey('title')) && '${b['title'] ?? ''}'.trim().isEmpty) return _fehler(400, 'Titel fehlt', 'title');
    if (!teilweise && b['start_date'] == null) return _fehler(400, 'Beginn fehlt', 'start_date');
    final s = DateTime.tryParse('${b['start_date']}');
    final e = DateTime.tryParse('${b['end_date']}');
    if (s != null && e != null && e.isBefore(s)) return _fehler(400, 'Ende liegt vor dem Beginn', 'end_date');
    return null;
  }

  @override
  Future<ApiAntwort> senden(String methode, String pfad, {Object? koerper}) async {
    anfragen.add((methode: methode, pfad: pfad, koerper: koerper));
    final z = erzwungen.remove('$methode $pfad');
    if (z != null) return z;
    final uri = Uri.parse(pfad);
    if (methode == 'GET' && uri.path == '/api/auth/me') {
      return (status: 200, json: {
        'user': {
          'id': 7, 'username': 'erika.muster', 'name': 'Erika Muster', 'email': 'erika.muster@example.org',
          'role': 'user', 'groups': gruppen, 'permissions': {if (schreiben.isNotEmpty) 'stweg-termine': 'write'},
        },
      });
    }
    if (methode == 'GET' && uri.path == '/api/termine') {
      final q = uri.queryParameters['stweg'];
      final List<int> gezeigt;
      if (q == null || q.isEmpty) {
        gezeigt = _sichtbar; // wie die API: alle eigenen
      } else if (q == 'alle') {
        gezeigt = _sichtbar;
      } else {
        gezeigt = [for (final x in q.split(',')) int.parse(x)];
        if (gezeigt.any((n) => !_sichtbar.contains(n))) return _fehler(403, 'Kein Zugriff auf diese STWEG');
      }
      return (status: 200, json: {
        'stwegs': [
          for (final n in _sichtbar)
            {
              'nr': n, 'name': n == 8 ? 'MEG' : 'STWEG $n', 'eigene': true, 'schreiben': schreiben.contains(n), 'gezeigt': gezeigt.contains(n),
              'kalender': kalender[n] == null ? null : {'name': kalender[n], 'url': 'https://cloud.example.org/kalender/$n'},
            },
        ],
        'kategorien': ['versammlung', 'sitzung', 'wartung', 'reinigung', 'entsorgung', 'anlass', 'stweg', 'sonstiges'],
        'termine': _termine(gezeigt),
      });
    }
    final m = RegExp(r'^/api/stweg/(\d+)/events(?:/(\d+))?$').firstMatch(uri.path);
    if (m != null) {
      final nr = int.parse(m[1]!);
      final id = m[2] == null ? null : int.parse(m[2]!);
      if (!schreiben.contains(nr)) {
        return _fehler(403, 'Termine der ${nr == 8 ? 'MEG' : 'STWEG $nr'} bearbeiten nur Ausschuss und Verwaltung dieser STWEG');
      }
      final b = koerper is Map ? koerper : const {};
      Map<String, dynamic> werte() => {
            for (final k in ['title', 'description', 'location', 'category', 'all_day'])
              if (b.containsKey(k)) k: b[k],
            if (b.containsKey('start_date')) 'start': b['start_date'],
            if (b.containsKey('end_date')) 'end': b['end_date'],
          };
      if (methode == 'POST' && id == null) {
        final f = _pruefen(koerper);
        if (f != null) return f;
        final e = {'id': _naechsteId++, 'stweg': nr, ...werte()};
        _eigene.add(e);
        return (status: 200, json: e);
      }
      final i = _eigene.indexWhere((e) => e['id'] == id && e['stweg'] == nr);
      if (i < 0) return _fehler(404, 'Termin nicht gefunden');
      if (methode == 'PUT') {
        final f = _pruefen(koerper, teilweise: true);
        if (f != null) return f;
        _eigene[i] = {..._eigene[i], ...werte()};
        return (status: 200, json: _eigene[i]);
      }
      if (methode == 'DELETE') {
        _eigene.removeAt(i);
        return (status: 200, json: {'success': true});
      }
    }
    return (status: 404, json: {'error': 'Nicht gefunden: $methode $pfad'});
  }
}
