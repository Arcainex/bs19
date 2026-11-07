ALPHA-Z KLEIDUNGS-EDITOR V4 - TORSO FIX

NEU IN V3
- Einzelne Texturen/Farbvarianten können deaktiviert und wieder aktiviert werden.
- Normale Spieler überspringen deaktivierte Modelle UND deaktivierte Texturen automatisch.
- Wenn alle Texturen eines Modells deaktiviert sind, wird das ganze Modell beim Blättern übersprungen.
- Editor zeigt gesperrte Inhalte weiterhin an, damit sie wieder aktiviert werden können.
- Überarbeitetes Alpha-Z Survival UI.

INSTALLATION
1. Alten bs_clothing-Ordner sichern.
2. Falls du V2 bereits benutzt hast: data/clothing_rules.json sichern. V3 kann alte V2-Regeln weiter lesen.
3. Diesen Ordner als bs_clothing einsetzen.
4. Bei vorhandenen Regeln die alte clothing_rules.json zurückkopieren. Beim ersten Speichern ergänzt V3 disabledTextures automatisch.
5. Server komplett neu starten.
6. Ingame /clothingeditor.

EDITOR
- MODELL DEAKTIVIEREN = komplettes Kleidungsmodell sperren.
- TEXTUR DEAKTIVIEREN = nur die aktuell sichtbare Farbe/Variante sperren.
- FAVORIT = Modell markieren.
- Regeln werden in data/clothing_rules.json gespeichert.

ADMIN ONLY (optional)
In config/config.lua:
  restricted = true
server.cfg:
  add_ace group.admin bs.clothing.admin allow

HINWEIS
Die Sperrungen werden mit Collection + Local-ID gespeichert. Dadurch bleiben Custom-Kleidungszuordnungen bei GTA Title Updates stabiler als reine globale Drawable-IDs.


V4 - FESTER TORSO / ARME PRO OBERTEIL
- Im Editor die Kategorie OBERTEIL öffnen.
- Unter FESTER TORSO / ARME den passenden Component-3 Drawable + Textur live einstellen.
- TORSO FÜR DIESES OBERTEIL SPEICHERN drücken.
- Die Zuordnung wird serverseitig in data/clothing_rules.json -> torsoMappings gespeichert.
- Die Zuordnung gilt für alle Texturen/Farben dieses Oberteil-Modells.
- Beim Wechsel auf das Oberteil wird Component 3 sofort automatisch gesetzt.
- Zusätzlich wird die Zuordnung regelmäßig kontrolliert, damit Spawn/Outfit-Scripts sie nicht dauerhaft überschreiben.
- In der normalen Spieler-Umkleide ist Component 3 bei einem gemappten Oberteil fest und kann nicht separat verstellt werden.
- ZUORDNUNG LÖSCHEN entfernt den Fix wieder.

UPGRADE VON V3:
Wenn du bereits Modelle/Texturen deaktiviert oder Favoriten gesetzt hast, kopiere deine bisherige
data/clothing_rules.json in diese V4. Fehlende torsoMappings werden automatisch als leer behandelt.


V4.2 - PERSISTENTES OUTFIT
- Beim Klick auf SPEICHERN wird CaptureOutfit() zusätzlich serverseitig in MySQL gespeichert.
- Tabelle wird automatisch erstellt: bs_clothing_outfits
- Nach Join, Respawn und Ped-/Charakterwechsel wird das gespeicherte Outfit wieder geladen.
- Wenn ein Character-State vorhanden ist (charId/characterId/citizenid/cid), wird pro Charakter gespeichert.
- Ohne Character-State wird als Fallback pro FiveM-License gespeichert.
- Feste Torso/Arme-Zuordnungen werden nach dem Laden erneut angewendet.
- oxmysql muss vor bs_clothing laufen (ist jetzt Manifest-Abhängigkeit).


V4.3 - ALT FREIMODUS
- Solange linkes ALT gehalten wird, verliert das NUI Tastatur-/Mausfokus.
- Script-Kamera wird ausgeschaltet und der Charakter wird entsperrt.
- Laufen, Umsehen und normale Game-Steuerung sind während ALT möglich.
- Beim Loslassen von ALT wird der Charakter an der aktuellen Position wieder fixiert und die Editor-Kamera/NUI-Steuerung kehrt zurück.
- Tastatureingaben werden während ALT nicht in Modell-/Texturfelder geschrieben.
- H im ALT-Freimodus: Hände hoch.
- X im ALT-Freimodus: Hände-hoch bzw. laufende Animation abbrechen.
- UI zeigt den Freimodus sichtbar an.
- Optional abschaltbar über Config.Clothing.editor.freeMoveWithAlt / freeMoveHandsUp.


V4.3.1 HOTFIX:
- Keine oxmysql/MySQL-Abhaengigkeit mehr.
- Behebt: attempt to index a nil value (global 'MySQL').


V4.3.2 ALT FIX:
- ALT schaltet Kamera und Editor NICHT mehr aus/ein.
- Script-Kamera bleibt dauerhaft aktiv und folgt dem Charakter.
- NUI bleibt dauerhaft sichtbar.
- Nur Keyboard-/Maus-Fokus wird waehrend ALT ans Spiel abgegeben.
- ALT nutzt + / - Keymapping statt Frame-Polling, um Fokus-Flackern zu vermeiden.


V4.3.3 ALT ORBIT:
- ALT halten: NUI-Fokus frei, Fenster + Kleidungskamera bleiben aktiv.
- WASD bewegt den Charakter.
- Maus links/rechts dreht die Kamera um den Charakter.
- Maus hoch/runter kippt den Blickwinkel.
- H Hände hoch, X Animation abbrechen.


V4.3.4 RECONNECT PERSISTENCE FIX
- Outfit-Key-Fallback repariert.
- Wenn beim Speichern noch keine Char-ID vorhanden war, wird unter License gespeichert.
- Sobald beim Reconnect die Char-ID vorhanden ist, wird der alte License-Eintrag automatisch auf Char-ID migriert.
- Server-Konsole protokolliert Speichern, Migration und fehlende Outfits.


V4.3.5 - TEXTURZAEHLER + CORE-PERSISTENZ
- Normale Umkleide zeigt bei Textur/Farbe nur freigegebene Varianten.
  Beispiel: 16 GTA-Texturen (0..15), davon 2 deaktiviert => Anzeige 0..13 (/13).
- Editor zeigt weiterhin echte GTA-Texture-IDs, damit Sperren bearbeitbar bleiben.
- Eigene player_outfits.json entfernt.
- Speichern nutzt ausschließlich `bs:outfit:push` aus bs_core.
- bs_core besitzt Charakterzustand/Datenbank; dadurch dieselbe gespeicherte Kleidung
  fuer Spawn/Reconnect und die bs_multichar-Charakterauswahl.
- WICHTIG: Beim Update keine alte player_outfits.json mehr zur Laufzeit verwenden.


V4.3.6 SAVE/SPAWN FIX
- SPEICHERN schreibt direkt ueber bs_core:SetCharacterOutfit in metadata.outfit.
- Umgeht absichtlich die bs_traders-Kaufpruefung, weil diese freie Alpha-Z-Umkleide GTA/DLC/Custom Kleidung verwaltet.
- bs_multichar liest metadata.outfit bereits fuer die Charaktervorschau.
- Beim Spawn und nach Regel-Aenderungen werden deaktivierte Modelle/Texturen automatisch ersetzt und wieder gespeichert.
- Spieler-Texturzaehler zeigt nur aktive Varianten (z.B. zwei gesperrt: /13 statt /15).

V4.3.7 START BEI MODELL 1
- Normale Umkleide startet bei Oberteil Modell 1, egal was getragen wird.
- /clothingeditor startet ebenfalls bei Oberteil Modell 1.
- Beim Wechsel jeder Kategorie startet diese bei Modell 1.
- Spieler-Umkleide überspringt dabei deaktivierte Modelle/Texturen.
- Editor zeigt Modell 1 auch dann, wenn es deaktiviert ist, damit es bearbeitbar bleibt.
- ABBRECHEN stellt das Outfit vom Zeitpunkt des Öffnens wieder her.
- SPEICHERN übernimmt die aktuell zusammengestellte Kleidung.

V4.3.8 COLLECTION-NAVIGATION
- Modellanzeige ist jetzt fortlaufend 1..N und zählt nur tatsächlich belegte Modelle.
- Leere Global-ID-Slots werden vollständig übersprungen.
- Navigation läuft automatisch von einer GTA/DLC/Custom-Collection in die nächste.
- Im Editor bleiben Collection, Local ID und echte Global ID sichtbar.
- Spieler-Modellzahl zählt nur freigegebene belegte Modelle.
- Editor-Modellzahl zählt alle belegten Modelle, damit deaktivierte Teile reaktiviert werden können.
- Props: Modell 0 bedeutet weiterhin KEINS; /N zählt nur echte Modelle.

V4.3.9 DISABLED RED
- Im Clothing Editor ist die Modellnummer rot, wenn das aktuelle Modell deaktiviert ist.
- Die Textur-/Farbenummer ist rot, wenn die aktuelle Textur deaktiviert ist.
- In der normalen Spieler-Umkleide bleibt die Anzeige normal, weil deaktivierte Einträge dort übersprungen werden.

V4.4.0 COLLECTION APPLY FIX
- Modellwechsel werden mit Collection + Local ID gesetzt.
- Wechsel am Ende einer Collection springt direkt in die nächste Collection.
- Leere/ungültige Slots werden übersprungen.
- Texturanzahl wird collection-basiert ermittelt.
- Diagnose: /clothingcollections zeigt Collection-Grenzen in F8.

V4.4.1 COLLECTION VALIDATION FIX
- IsPedCollectionComponentVariationValid bekommt jetzt den erforderlichen Palette-Parameter.
- Wenn Textur 0 ungueltig ist, wird automatisch die erste gueltige Textur des Modells versucht.
- Nach dem Setzen wird kontrolliert, ob GTA wirklich Collection + Local ID uebernommen hat.
- /clothingcollections zeigt jetzt Start UND Ende jeder Collection.
- /clothingnexttest testet das naechste belegte Modell direkt und meldet OK/ABGELEHNT in F8.

V4.4.2 CHAR-EDITOR TORSO PREVIEW FIX
- bs_clothing erkennt den bs_multichar Preview-Ped im Charaktereditor.
- Beim Wechsel des Oberteils wird dieselbe serverseitig gespeicherte
  Oberteil->Torso-Zuordnung wie ingame auf den Preview-Ped angewendet.
- Dadurch stimmen Charaktereditor und Ingame-Torso ueberein.
- Export ApplyTorsoForPed(ped) fuer spaetere direkte Integrationen hinzugefuegt.

V4.4.3 ACTIVE MODEL COUNT FIX
- In der normalen Spieler-Umkleide werden deaktivierte Modelle nicht mehr in /N mitgezaehlt.
- Modelle ohne aktive Textur werden ebenfalls nicht mitgezaehlt.
- Die fortlaufende Modellnummer wird dadurch automatisch neu komprimiert.
- Im Clothing Editor bleiben deaktivierte Modelle weiterhin sichtbar und zaehlen dort mit, damit sie reaktiviert werden koennen.

V4.4.4 - LUECKENLOSE AKTIVMODELL-NUMMERIERUNG
- Spieler-Umkleide: sichtbare Nummern steigen immer um exakt 1, auch wenn GTA-IDs fehlen oder Modelle deaktiviert sind.
- Gesamtzahl /N wird ausschliesslich aus aktiven, tatsaechlich auswaehlbaren Modellen berechnet.
- Modelle ohne gueltige, aktive Textur und ungueltige Collection-Varianten werden nicht mitgezaehlt.
- Nach Sperren/Entsperren im Editor wird die Liste neu berechnet.
- Clothing-Editor zeigt weiterhin alle Modelle einschliesslich deaktivierter, um sie bearbeiten zu koennen.
- Reale GTA Global-ID bleibt unveraendert und im Editor sichtbar; Speichern/Charakterkleidung bleiben unangetastet.
