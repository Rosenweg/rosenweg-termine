// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

import '../daten.dart';
import '../termin.dart';

/// Termin anlegen oder aendern. Nur fuer STWEGs, in denen die Person
/// schreiben darf ([stwegs]; die API prueft es nochmals). Ganztags: Datum
/// und optional "bis"; sonst Datum, Beginn und optional Ende (gleicher Tag).
class TerminFormular extends StatefulWidget {
  const TerminFormular({super.key, required this.daten, required this.stwegs, this.termin});
  final TermineDaten daten;
  final List<TermineStweg> stwegs;

  /// null = neuer Termin.
  final Termin? termin;

  @override
  State<TerminFormular> createState() => _TerminFormularState();
}

class _TerminFormularState extends State<TerminFormular> {
  late final Termin? _t = widget.termin;
  late int? _stweg = _t?.stweg ?? (widget.stwegs.length == 1 ? widget.stwegs.first.nr : null);
  late final _titel = TextEditingController(text: _t?.titel ?? '');
  late final _ort = TextEditingController(text: _t?.ort ?? '');
  late final _text = TextEditingController(text: _t?.beschreibung ?? '');
  late String _art = arten.containsKey(_t?.art) ? _t!.art! : 'sonstiges';
  late bool _ganztags = _t?.ganztags ?? false;
  late DateTime? _datum = _t?.beginn;
  late TimeOfDay? _von = _t == null || _t.ganztags ? null : TimeOfDay.fromDateTime(_t.beginn);
  late TimeOfDay? _bis = _t?.ende == null || _t!.ganztags ? null : TimeOfDay.fromDateTime(_t.ende!);
  late DateTime? _bisTag = _t != null && _t.ganztags && _t.ende != null ? _t.ende : null;

  @override
  void dispose() {
    _titel.dispose();
    _ort.dispose();
    _text.dispose();
    super.dispose();
  }

  DateTime _mit(DateTime tag, TimeOfDay z) => DateTime(tag.year, tag.month, tag.day, z.hour, z.minute);

  Future<void> _speichern() async {
    final tag = _datum!;
    final DateTime beginn;
    DateTime? ende;
    if (_ganztags) {
      beginn = DateTime(tag.year, tag.month, tag.day);
      ende = _bisTag;
    } else {
      beginn = _mit(tag, _von!);
      if (_bis != null) {
        // Termin ueber Mitternacht (frueher gespeichert): Abstand der Tage behalten
        final alt = _t?.ende;
        final tage = alt == null || _t!.ganztags ? 0 : DateTime(alt.year, alt.month, alt.day).difference(DateTime(_t.beginn.year, _t.beginn.month, _t.beginn.day)).inDays;
        ende = _mit(DateTime(tag.year, tag.month, tag.day + tage), _bis!);
      }
    }
    final werte = Termin.formular(
      titel: _titel.text,
      beginn: beginn,
      ende: ende,
      ganztags: _ganztags,
      ort: _ort.text,
      beschreibung: _text.text,
      art: _art,
    );
    final t = _t;
    if (t == null) {
      await widget.daten.api.anlegen(_stweg!, werte);
    } else {
      await widget.daten.api.aendern(t, werte);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_t == null ? 'Neuer Termin' : 'Termin bearbeiten')),
        body: RosenwegInhalt(
          child: RosenwegFormular(
            speichern: _speichern,
            gespeichertText: _t == null ? 'Termin eingetragen.' : 'Termin gespeichert.',
            gespeichert: () => Navigator.of(context).pop(true),
            felder: [
              if (_t == null && widget.stwegs.length > 1)
                AuswahlFeld<int>(
                  name: 'stweg',
                  titel: 'Für',
                  optionen: {for (final s in widget.stwegs) s.nr: s.name},
                  wert: _stweg,
                  pflicht: true,
                  geaendert: (v) => setState(() => _stweg = v),
                )
              else if (_stweg != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.apartment_outlined),
                  title: Text('Für die ${stwegText(_stweg!)}'),
                  subtitle: const Text('Alle Bewohner, Eigentümer, Ausschuss und Verwaltung dieser STWEG sehen den Termin.'),
                ),
              TextFeld(name: 'title', titel: 'Titel', controller: _titel, pflicht: true, hinweis: 'z. B. Eigentümerversammlung'),
              AuswahlFeld<String>(
                name: 'category',
                titel: 'Art',
                optionen: arten,
                wert: _art,
                pflicht: true,
                geaendert: (v) => setState(() => _art = v ?? 'sonstiges'),
              ),
              SchalterFeld(
                titel: 'Ganztags',
                erklaerung: 'ohne Uhrzeit, z. B. Reinigung, Sperrung',
                wert: _ganztags,
                geaendert: (v) => setState(() => _ganztags = v),
              ),
              DatumFeld(
                name: 'start_date',
                titel: _ganztags ? 'Tag' : 'Datum',
                wert: _datum,
                pflicht: true,
                geaendert: (v) => setState(() => _datum = v),
              ),
              if (_ganztags)
                DatumFeld(
                  name: 'end_date',
                  titel: 'Bis (letzter Tag, falls mehrere Tage)',
                  wert: _bisTag,
                  erstes: _datum,
                  geaendert: (v) => setState(() => _bisTag = v),
                )
              else ...[
                ZeitFeld(name: 'start_zeit', titel: 'Beginn', wert: _von, pflicht: true, geaendert: (v) => setState(() => _von = v)),
                ZeitFeld(name: 'end_date', titel: 'Ende (freiwillig)', wert: _bis, geaendert: (v) => setState(() => _bis = v)),
              ],
              TextFeld(name: 'location', titel: 'Ort', controller: _ort, hinweis: 'z. B. Gemeinschaftsraum Haus 9'),
              TextFeld(name: 'description', titel: 'Beschreibung', controller: _text, zeilen: 4),
            ],
          ),
        ),
      );
}
