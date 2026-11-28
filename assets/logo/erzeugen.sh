#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Logo "Rosenweg Termine" aus dem Logo-Baukasten von rosenweg-basis: Wappen
# (Turm, Weg, Rose) und rechts unten die Plakette mit dem Zeichen der App
# (assets/logo/zeichen/termine.svg), Farbe des Zeichens nach Zielgruppe; dazu
# Fassungen in Blau und Gruen (FARBEN) samt Startsymbol-Wechsel.
# Schreibt alle Symbole: Android (adaptive, monochrom), iOS, macOS (+ .icns),
# Windows (.ico), Linux (SVG; die hicolor-PNGs rechnet linux/paket/bauen.sh),
# /apps (assets/logo/rosenweg-termine-192.png) und den DMG-Hintergrund.
# Aufruf aus dem Repo-Wurzelverzeichnis:
#   sh assets/logo/erzeugen.sh [pfad/zu/rosenweg-basis]
set -eu
BASIS="${1:-../rosenweg-basis}"
GRUPPE=bewohner
# weitere Farben je nach freigeschalteter Funktion (docs/gruppenfarbe.md der Basis):
# blau = Ausschuss/Verwaltung (duerfen Termine schreiben), gruen = Technik/Praesident
FARBEN="verwaltung technik"
FARBEN="$FARBEN" sh "$BASIS/werkzeug/logo/app-symbole.sh" . rosenweg-termine "Rosenweg Termine" assets/logo/zeichen/termine.svg "$GRUPPE"
# shellcheck disable=SC2086
python3 "$BASIS/werkzeug/logo/farben-einbauen.py" . --standard "$GRUPPE" --farben $FARBEN
