// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/foundation.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

import 'erinnerung.dart';
import 'termin.dart';

/// Gemeinsamer Stand der App: Termine, gewaehlte STWEGs, Einstellungen.
/// Jedes Laden gleicht auch die Erinnerungen ab (geplant im System; auf
/// geteilten Telefonen nie – das regelt die Basis).
class TermineDaten extends ChangeNotifier {
  TermineDaten(this.sitzung, {this._einstellungen});

  final RosenwegSitzung sitzung;
  late final api = TermineApi(sitzung.api);

  TermineEinstellungen? _einstellungen;
  TermineStand? stand;
  Object? fehler;
  bool laedt = false;

  /// Vergangene Termine (bis 7 Tage zurueck, so liefert die API) zeigen.
  bool vergangene = false;

  Future<TermineEinstellungen> einstellungen() async => _einstellungen ??= await TermineEinstellungen.laden();
  TermineEinstellungen? get einstellungenJetzt => _einstellungen;

  bool get geteilt => sitzung.geteiltesTelefon;

  Future<void> laden() async {
    laedt = true;
    fehler = null;
    notifyListeners();
    try {
      final e = await einstellungen();
      TermineStand s;
      try {
        s = await api.laden(stwegs: e.stwegs);
      } on ApiFehler catch (f) {
        // gemerkte Auswahl gilt nicht mehr (z. B. ausgezogen): wieder die eigenen
        if (e.stwegs == null || f.status != 403) rethrow;
        e.stwegs = null;
        await e.speichern();
        s = await api.laden();
      }
      stand = s;
      await erinnerungenAbgleichen();
    } catch (e) {
      fehler = e;
      Protokoll.schreiben('Termine laden', e);
    } finally {
      laedt = false;
      notifyListeners();
    }
  }

  Future<void> erinnerungenAbgleichen() async {
    final s = stand;
    final e = _einstellungen;
    if (s == null || e == null) return;
    try {
      await Erinnerungen.abgleichen(sitzung, erinnerungenFuer(s.termine, e));
    } catch (f) {
      Protokoll.schreiben('Erinnerungen', f);
    }
  }

  /// STWEG ein- oder ausblenden (mindestens eine bleibt).
  Future<void> stwegUmschalten(int nr) async {
    final s = stand;
    if (s == null) return;
    final gezeigt = {for (final x in s.stwegs) if (x.gezeigt) x.nr};
    if (gezeigt.contains(nr)) {
      if (gezeigt.length == 1) return;
      gezeigt.remove(nr);
    } else {
      gezeigt.add(nr);
    }
    final e = await einstellungen();
    final eigene = {for (final x in s.stwegs) if (x.eigene) x.nr};
    e.stwegs = setEquals(gezeigt, eigene) ? null : gezeigt;
    await e.speichern();
    await laden();
  }

  void vergangeneUmschalten() {
    vergangene = !vergangene;
    notifyListeners();
  }

  /// Einstellung geaendert: speichern, Erinnerungen neu abgleichen.
  Future<void> einstellungAendern(void Function(TermineEinstellungen e) aendern) async {
    final e = await einstellungen();
    aendern(e);
    await e.speichern();
    notifyListeners();
    await erinnerungenAbgleichen();
  }

  /// Gezeigte Termine (ohne vergangene, ausser [vergangene]).
  List<Termin> gezeigt(DateTime jetzt) {
    final s = stand;
    if (s == null) return const [];
    return [for (final t in s.termine) if (vergangene || !t.vorbei(jetzt)) t];
  }

  Termin? termin(String schluessel) => stand?.termine.where((t) => t.schluessel == schluessel).firstOrNull;
}
