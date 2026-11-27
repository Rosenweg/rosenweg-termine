// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

import '../daten.dart';
import '../termin.dart';
import 'termin.dart';
import 'termin_formular.dart';

const monateKurz = ['Jan.', 'Feb.', 'März', 'Apr.', 'Mai', 'Juni', 'Juli', 'Aug.', 'Sept.', 'Okt.', 'Nov.', 'Dez.'];
const monateLang = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];

/// Alle Termine der gezeigten STWEG(s), nach Monaten, die naechsten zuerst.
/// Oben: STWEG waehlen (nur wenn es mehrere gibt), vergangene ein/aus.
/// Antippen = Termin mit "In Kalender übernehmen"; "Neuer Termin" nur,
/// wer in einer STWEG schreiben darf.
class TermineSeite extends StatelessWidget {
  const TermineSeite({super.key, required this.daten});
  final TermineDaten daten;

  Future<void> _neu(BuildContext context) async {
    final s = daten.stand;
    if (s == null) return;
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => TerminFormular(daten: daten, stwegs: s.schreibbar),
    ));
    if (ok == true) await daten.laden();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: daten,
        builder: (context, _) {
          final s = daten.stand;
          if (s == null) {
            if (daten.fehler != null) return FehlerAnzeige(text: fehlerText(daten.fehler!), nochmals: daten.laden);
            return const LadeAnzeige();
          }
          final jetzt = DateTime.now();
          final liste = daten.gezeigt(jetzt);
          return Scaffold(
            body: RefreshIndicator(
              onRefresh: daten.laden,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _Kopf(daten: daten, stand: s)),
                  if (daten.fehler != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Hinweis('Nicht aktuell: ${fehlerText(daten.fehler!)}', art: HinweisArt.warnung),
                      ),
                    ),
                  if (s.stwegs.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: _Leer(
                        symbol: Icons.apartment_outlined,
                        text: 'Dein Konto gehört zu keiner STWEG. Termine sehen Bewohner, Eigentümer, '
                            'Ausschuss und Verwaltung ihrer STWEG.',
                      ),
                    )
                  else if (liste.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _Leer(
                        symbol: Icons.event_available_outlined,
                        text: daten.vergangene ? 'Keine Termine.' : 'Keine anstehenden Termine.',
                      ),
                    )
                  else
                    SliverList.list(children: _gruppiert(context, liste, s, jetzt)),
                  const SliverToBoxAdapter(child: SizedBox(height: 96)),
                ],
              ),
            ),
            floatingActionButton: s.schreibbar.isEmpty
                ? null
                : FloatingActionButton.extended(
                    onPressed: () => _neu(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Neuer Termin'),
                  ),
          );
        },
      );

  List<Widget> _gruppiert(BuildContext context, List<Termin> liste, TermineStand s, DateTime jetzt) {
    final w = <Widget>[];
    String? monat;
    for (final t in liste) {
      final m = '${monateLang[t.beginn.month - 1]} ${t.beginn.year}';
      if (m != monat) {
        monat = m;
        w.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(m, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
        ));
      }
      w.add(TerminKachel(
        termin: t,
        mitStweg: s.stwegs.where((x) => x.gezeigt).length > 1,
        vorbei: t.vorbei(jetzt),
        antippen: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TerminSeite(daten: daten, schluessel: t.schluessel),
        )),
      ));
    }
    return w;
  }
}

class _Kopf extends StatelessWidget {
  const _Kopf({required this.daten, required this.stand});
  final TermineDaten daten;
  final TermineStand stand;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (stand.stwegs.length > 1)
              for (final st in stand.stwegs)
                FilterChip(
                  label: Text(st.name),
                  selected: st.gezeigt,
                  tooltip: st.gezeigt ? '${st.name} ausblenden' : '${st.name} zeigen',
                  onSelected: daten.laedt ? null : (_) => daten.stwegUmschalten(st.nr),
                ),
            FilterChip(
              label: const Text('Vergangene'),
              selected: daten.vergangene,
              tooltip: 'Termine der letzten 7 Tage zeigen',
              onSelected: (_) => daten.vergangeneUmschalten(),
            ),
          ],
        ),
      );
}

class _Leer extends StatelessWidget {
  const _Leer({required this.symbol, required this.text});
  final IconData symbol;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(symbol, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ]),
        ),
      );
}

/// Ein Termin in der Liste: Datum links, Titel, Zeit und Ort, Herkunft.
class TerminKachel extends StatelessWidget {
  const TerminKachel({super.key, required this.termin, required this.antippen, this.mitStweg = false, this.vorbei = false});
  final Termin termin;
  final VoidCallback antippen;
  final bool mitStweg;
  final bool vorbei;

  @override
  Widget build(BuildContext context) {
    final f = Theme.of(context).colorScheme;
    final t = termin;
    final zeit = t.ganztags ? 'ganztags' : uhrText(t.beginn);
    final unten = [
      zeit,
      ?t.ort,
      if (mitStweg && t.stweg != null) stwegText(t.stweg!),
      if (t.quelle != Quelle.stweg) t.quelle.text,
    ].join(' · ');
    final datum = Semantics(
      excludeSemantics: true,
      child: Container(
        width: 52,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(color: f.primaryContainer, borderRadius: BorderRadius.circular(10)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(wochentageLang[t.beginn.weekday - 1].substring(0, 2), style: TextStyle(fontSize: 11, color: f.onPrimaryContainer)),
          Text('${t.beginn.day}',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: f.onPrimaryContainer, height: 1.15)),
          Text(monateKurz[t.beginn.month - 1], style: TextStyle(fontSize: 11, color: f.onPrimaryContainer)),
        ]),
      ),
    );
    return Opacity(
      opacity: vorbei ? 0.55 : 1,
      child: InkWell(
        onTap: antippen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            datum,
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.titel, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(unten, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: f.onSurfaceVariant)),
              ]),
            ),
            const SizedBox(width: 8),
            Icon(t.quelle.symbol, color: f.outline, semanticLabel: t.quelle.text),
          ]),
        ),
      ),
    );
  }
}
