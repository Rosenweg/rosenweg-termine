// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';
import 'package:url_launcher/url_launcher.dart';

import '../daten.dart';
import '../erinnerung.dart';
import '../termin.dart';
import 'termin_formular.dart';

/// Ein Termin: wann, wo, worum. Darunter das, was man damit tut:
/// "In Kalender übernehmen" (Kalenderdatei mit der Kalender-App oeffnen),
/// "Teilen" (.ics), die Erinnerung ein/aus. Wer in der STWEG schreiben
/// darf, sieht "Bearbeiten" und "Löschen" (nur Termine der STWEG; Wartungen,
/// Kooperation und Terminumfragen pflegt man dort, wo sie herkommen).
class TerminSeite extends StatelessWidget {
  const TerminSeite({super.key, required this.daten, required this.schluessel});
  final TermineDaten daten;
  final String schluessel;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: daten,
        builder: (context, _) {
          final t = daten.termin(schluessel);
          final s = daten.stand;
          if (t == null || s == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Termin')),
              body: daten.laedt
                  ? const LadeAnzeige()
                  : const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Diesen Termin gibt es nicht mehr.'))),
            );
          }
          final darf = s.darfBearbeiten(t);
          return Scaffold(
            appBar: AppBar(
              title: Text(artText(t.art)),
              actions: [
                if (darf)
                  IconButton(
                    tooltip: 'Bearbeiten',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _bearbeiten(context, t, s),
                  ),
                if (darf)
                  IconButton(
                    tooltip: 'Löschen',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _loeschen(context, t),
                  ),
              ],
            ),
            body: RosenwegInhalt(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(t.titel, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  _Zeile(symbol: Icons.schedule, text: t.wannText),
                  if (t.ort != null) _Zeile(symbol: Icons.place_outlined, text: t.ort!),
                  _Zeile(
                    symbol: t.quelle.symbol,
                    text: [
                      if (t.stweg != null) stwegText(t.stweg!) else if (t.quelle == Quelle.kooperation) 'Kooperation (alle STWEGs)',
                      if (t.quelle != Quelle.stweg) t.quelle.text,
                    ].join(' · '),
                  ),
                  if (t.beschreibung != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(t.beschreibung!),
                  ],
                  const SizedBox(height: 24),
                  _Kalender(daten: daten, termin: t),
                  const SizedBox(height: 16),
                  _Erinnerung(daten: daten, termin: t),
                ],
              ),
            ),
          );
        },
      );

  Future<void> _bearbeiten(BuildContext context, Termin t, TermineStand s) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => TerminFormular(daten: daten, stwegs: s.schreibbar, termin: t),
    ));
    if (ok == true) await daten.laden();
  }

  Future<void> _loeschen(BuildContext context, Termin t) async {
    if (!await loeschenBestaetigen(context, 'Termin',
        text: '„${t.titel}“ verschwindet für alle in der ${stwegText(t.stweg!)}. Wer ihn schon im eigenen Kalender hat, behält ihn dort.')) {
      return;
    }
    try {
      await daten.api.loeschen(t);
      if (context.mounted) {
        zeigeMeldung(context, 'Termin gelöscht.');
        Navigator.of(context).pop();
      }
      await daten.laden();
    } catch (e) {
      if (context.mounted) zeigeMeldung(context, fehlerText(e), fehler: true);
    }
  }
}

class _Zeile extends StatelessWidget {
  const _Zeile({required this.symbol, required this.text});
  final IconData symbol;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(symbol, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ]),
      );
}

/// "In Kalender übernehmen" und "Teilen". Steht der Termin schon in einem
/// Nextcloud-Kalender (Rosenweg Kalender gleicht ihn ab), sagt die App das
/// zuerst – sonst hat man ihn doppelt.
class _Kalender extends StatelessWidget {
  const _Kalender({required this.daten, required this.termin});
  final TermineDaten daten;
  final Termin termin;

  DateiDaten _datei() {
    final e = daten.einstellungenJetzt;
    return Kalenderdatei.datei(
      [termin.alsKalender(erinnerung: e != null && e.erinnert(termin) ? e.vorlauf.dauer : null)],
      dateiname: Kalenderdatei.dateinameAus(termin.titel),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nc = daten.stand?.kalenderFuer(termin);
    return Abschnitt(
      titel: 'Im eigenen Kalender',
      symbol: Icons.calendar_month_outlined,
      kind: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (nc != null) ...[
          Hinweis('Dieser Termin steht schon im Nextcloud-Kalender „${nc.kalender}“. '
              'Hast du ihn in Rosenweg Kalender (oder einem anderen Kalender) abonniert, '
              'ist er dort bereits – übernimm ihn dann nicht noch einmal.'),
          if (nc.kalenderUrl != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => launchUrl(nc.kalenderUrl!, mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Nextcloud-Kalender öffnen'),
              ),
            ),
          const SizedBox(height: 8),
        ],
        Wrap(spacing: 12, runSpacing: 8, children: [
          FilledButton.icon(
            key: const Key('in-kalender'),
            onPressed: () => dateiOeffnen(context, _datei()),
            icon: const Icon(Icons.event_available),
            label: const Text('In Kalender übernehmen'),
          ),
          Builder(
            builder: (c) => OutlinedButton.icon(
              onPressed: () => dateiTeilen(c, _datei()),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Teilen (.ics)'),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _Erinnerung extends StatelessWidget {
  const _Erinnerung({required this.daten, required this.termin});
  final TermineDaten daten;
  final Termin termin;

  @override
  Widget build(BuildContext context) {
    if (daten.geteilt) {
      return const Hinweis('Auf geteilten Telefonen erinnert die App nicht (die Person am Telefon wechselt). '
          'Übernimm den Termin in deinen Kalender.');
    }
    final e = daten.einstellungenJetzt;
    if (e == null) return const SizedBox.shrink();
    if (termin.vorbei(DateTime.now())) return const SizedBox.shrink();
    if (e.vorlauf.dauer == null) {
      return const Hinweis('Erinnerungen sind ausgeschaltet (Bereich „Erinnerungen“).');
    }
    final wann = erinnerungsZeit(termin, e.vorlauf);
    final ein = e.erinnert(termin);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(ein ? Icons.notifications_active_outlined : Icons.notifications_off_outlined),
      title: const Text('Erinnern'),
      subtitle: Text(wann != null && wann.isBefore(DateTime.now())
          ? 'Zeit für die Erinnerung ist schon vorbei'
          : '${e.vorlauf.text}${wann != null ? ' (${tagLangText(wann)}, ${uhrText(wann)})' : ''}'),
      value: ein,
      onChanged: (an) => daten.einstellungAendern((e) {
        if (an) {
          e.ohneErinnerung.remove(termin.schluessel);
        } else {
          e.ohneErinnerung.add(termin.schluessel);
        }
      }),
    );
  }
}
