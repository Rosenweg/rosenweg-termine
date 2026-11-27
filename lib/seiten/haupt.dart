// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

import '../daten.dart';
import '../erinnerung.dart';
import 'erinnerungen.dart';
import 'termin.dart';
import 'termine.dart';

/// Die App nach der Anmeldung. Zwei Bereiche – auf dem Handy unten, am
/// Computer links:
///
///  * Termine: Versammlungen, Sitzungen, Wartungen, Reinigungen der eigenen
///    STWEG(s) samt Kooperation; in den Kalender uebernehmen; Ausschuss und
///    Verwaltung (Recht „STWEG-Termine“, nur ihre STWEG), Technik und
///    Praesident tragen ein, aendern, loeschen
///  * Erinnerungen: wie lange vorher, neue Termine melden, alle auf einmal
///    in den Kalender
///
/// Ohne Push: beim Oeffnen, bei der Rueckkehr und alle 15 Minuten laedt die
/// App neu und plant die Erinnerungen; Android/iOS zusaetzlich im
/// Hintergrund (nie auf geteilten Telefonen; nach einem Personenwechsel
/// baut RosenwegRahmen die App neu auf).
class Haupt extends StatefulWidget {
  const Haupt({super.key, required this.sitzung, this.hintergrund, this.einstellungen});
  final RosenwegSitzung sitzung;

  /// Abfrage im Hintergrund beim System anmelden (main.dart); null = nicht.
  final Future<void> Function()? hintergrund;

  /// Fuer Tests.
  final TermineEinstellungen? einstellungen;

  @override
  State<Haupt> createState() => _HauptState();
}

class _HauptState extends State<Haupt> {
  late final daten = TermineDaten(widget.sitzung, einstellungen: widget.einstellungen);
  StreamSubscription<String>? _abo;

  @override
  void initState() {
    super.initState();
    // Laden macht BeimOeffnen (beim Start, bei der Rueckkehr, alle 15 Minuten)
    WidgetsBinding.instance.addPostFrameCallback((_) => _benachrichtigungen());
  }

  Future<void> _benachrichtigungen() async {
    try {
      await Benachrichtigung.einrichten(widget.sitzung.app);
      _abo = Benachrichtigung.angetippt.listen(_ziel);
      final z = await Benachrichtigung.startZiel();
      if (z != null) _ziel(z);
      if (widget.sitzung.geteiltesTelefon) return;
      await widget.hintergrund?.call();
      final e = await daten.einstellungen();
      if (e.vorlauf.dauer != null || e.neueMelden) await Benachrichtigung.erlaubnisFragen();
    } catch (e) {
      Protokoll.schreiben('Benachrichtigungen', e);
    }
  }

  /// Ziel einer Benachrichtigung: `termin/<schluessel>` → den Termin zeigen.
  void _ziel(String ziel) {
    if (!ziel.startsWith('termin/') || !mounted) return;
    final schluessel = ziel.substring('termin/'.length);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TerminSeite(daten: daten, schluessel: schluessel)));
  }

  Future<void> _nachfragen() async {
    await daten.laden();
    // Am Computer gibt es keine Abfrage des Systems: neue Termine melden,
    // solange die App laeuft (Android/iOS macht das der Hintergrund)
    if (!HintergrundAbfrage.vomSystem && !widget.sitzung.geteiltesTelefon) {
      await HintergrundAbfrage.einmal(widget.sitzung.app, termineAbfrage, sitzung: widget.sitzung);
    }
  }

  @override
  void dispose() {
    _abo?.cancel();
    daten.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sitzung;
    return BeimOeffnen(
      pruefen: _nachfragen,
      alle: const Duration(minutes: 15),
      child: RosenwegGeruest(
        titel: Text(s.app.name),
        logo: Padding(
          padding: const EdgeInsets.all(10),
          // Farbe nach der Person (rot, blau fuer Ausschuss/Verwaltung, gruen Technik)
          child: FarbLogo(sitzung: s, klein: true),
        ),
        aktionen: [
          IconButton(tooltip: 'Neu laden', icon: const Icon(Icons.refresh), onPressed: daten.laden),
          _Menue(sitzung: s),
        ],
        ziele: [
          GeruestZiel(
            titel: 'Termine',
            symbol: Icons.event_outlined,
            gewaehltSymbol: Icons.event,
            seite: (_) => TermineSeite(daten: daten),
          ),
          GeruestZiel(
            titel: 'Erinnerungen',
            symbol: Icons.notifications_outlined,
            gewaehltSymbol: Icons.notifications,
            seite: (_) => ErinnerungenSeite(daten: daten),
          ),
        ],
      ),
    );
  }
}

/// Menue oben rechts: Anmeldung, Ueber, Abmelden (nicht auf geteilten
/// Telefonen – dort meldet Rosenweg Geraet ab). Abmelden entfernt auch die
/// geplanten Erinnerungen und meldet die Abfrage im Hintergrund ab.
class _Menue extends StatelessWidget {
  const _Menue({required this.sitzung});
  final RosenwegSitzung sitzung;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Mehr',
        onSelected: (w) async {
          switch (w) {
            case 'anmeldung':
              await zeigeAnmeldung(context, sitzung);
            case 'ueber':
              await zeigeUeber(context, sitzung.app);
            case 'abmelden':
              if (await frage(context, 'Abmelden?', 'Danach musst du dich neu anmelden. Geplante Erinnerungen werden entfernt.',
                  ja: 'Abmelden')) {
                await Erinnerungen.alleEntfernen();
                await HintergrundAbfrage.abmelden(sitzung.app);
                await sitzung.abmelden();
              }
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'anmeldung', child: Text('Anmeldung: ${sitzung.name ?? 'angemeldet'}')),
          PopupMenuItem(value: 'ueber', child: Text('Über ${sitzung.app.name}')),
          if (!sitzung.geteiltesTelefon) const PopupMenuItem(value: 'abmelden', child: Text('Abmelden')),
        ],
      );
}
