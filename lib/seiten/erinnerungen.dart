// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

import '../daten.dart';
import '../erinnerung.dart';
import '../termin.dart';

/// Wie die App erinnert: Vorlauf fuer alle Termine (einzelne lassen sich
/// beim Termin ausschalten), Hinweis bei neuen Terminen, und alle
/// kommenden Termine auf einmal in den eigenen Kalender.
class ErinnerungenSeite extends StatelessWidget {
  const ErinnerungenSeite({super.key, required this.daten});
  final TermineDaten daten;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: daten,
        builder: (context, _) {
          final e = daten.einstellungenJetzt;
          if (e == null) return const LadeAnzeige();
          final kommend = daten.gezeigt(DateTime.now()).where((t) => !t.vorbei(DateTime.now())).toList();
          return RosenwegInhalt(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (daten.geteilt)
                  const Hinweis('Auf geteilten Telefonen erinnert die App nicht – die Person am Telefon wechselt. '
                      'Übernimm Termine in deinen Kalender; der erinnert dich auf deinen eigenen Geräten.')
                else ...[
                  Abschnitt(
                    titel: 'Erinnerung vor Terminen',
                    symbol: Icons.notifications_outlined,
                    erklaerung: 'Gilt für alle Termine; einzelne schaltest du beim Termin aus. Ganztägige: um 8 Uhr.',
                    kind: RadioGroup<Vorlauf>(
                      groupValue: e.vorlauf,
                      onChanged: (v) async {
                        if (v == null) return;
                        if (v.dauer != null) await Benachrichtigung.erlaubnisFragen();
                        await daten.einstellungAendern((e) => e.vorlauf = v);
                      },
                      child: Column(children: [
                        for (final v in Vorlauf.values) RadioListTile<Vorlauf>(value: v, title: Text(v.text)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Bei neuen Terminen benachrichtigen'),
                    subtitle: Text(RosenwegPlattform.istDesktop
                        ? 'Solange die App läuft, schaut sie alle 15 Minuten nach.'
                        : 'Die App schaut etwa alle 15 Minuten nach (mit Netz).'),
                    value: e.neueMelden,
                    onChanged: (v) => daten.einstellungAendern((e) => e.neueMelden = v),
                  ),
                ],
                const SizedBox(height: 16),
                Abschnitt(
                  titel: 'Alle kommenden Termine',
                  symbol: Icons.calendar_month_outlined,
                  erklaerung: kommend.isEmpty
                      ? 'Zurzeit keine.'
                      : '${kommend.length} Termine als eine Kalenderdatei – dein Kalender übernimmt sie auf einmal. '
                          'Nochmals übernehmen aktualisiert sie, statt sie zu verdoppeln.',
                  kind: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(spacing: 12, runSpacing: 8, children: [
                      FilledButton.tonalIcon(
                        onPressed: kommend.isEmpty ? null : () => dateiOeffnen(context, _alle(kommend, e)),
                        icon: const Icon(Icons.event_available),
                        label: const Text('Alle in Kalender übernehmen'),
                      ),
                      Builder(
                        builder: (c) => OutlinedButton.icon(
                          onPressed: kommend.isEmpty ? null : () => dateiTeilen(c, _alle(kommend, e)),
                          icon: const Icon(Icons.share_outlined),
                          label: const Text('Teilen (.ics)'),
                        ),
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          );
        },
      );

  DateiDaten _alle(List<Termin> termine, TermineEinstellungen e) {
    final namen = {
      for (final s in daten.stand?.stwegs ?? const <TermineStweg>[])
        if (s.gezeigt) s.name,
    };
    return Kalenderdatei.datei(
      [for (final t in termine) t.alsKalender(erinnerung: e.erinnert(t) ? e.vorlauf.dauer : null)],
      dateiname: Kalenderdatei.dateinameAus('Termine ${namen.join(' ')}'),
      name: 'Rosenweg Termine (${namen.join(', ')})',
    );
  }
}
