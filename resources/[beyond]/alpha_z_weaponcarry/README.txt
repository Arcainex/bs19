ALPHA-Z WEAPON CARRY V1.10 – KAMERA AUF AUSGEWÄHLTE WAFFE
==========================================================

NEU
- Die Editor-Kamera richtet sich auf die ausgewählte, sichtbar am Körper
  getragene Waffe, nicht mehr auf die Körpermitte des Charakters.
- Der Mittelpunkt wird aus den Modellabmessungen der Waffe berechnet.
  Dadurch wird die sichtbare Waffe auch bei versetztem Modellursprung
  mittig dargestellt.
- ALT + Maus umkreist die Waffe; ALT + Mausrad zoomt auf die Waffe.
- Bei einem Wechsel des Trageplatzes / der Einzelwaffe wird das Ziel
  automatisch gewechselt und die Kamera sinnvoll ausgerichtet.
- Beim Öffnen wird nach Möglichkeit ein Trageplatz mit sichtbarer Waffe
  automatisch ausgewählt. Waffen am Rücken sieht man von hinten,
  Hüftwaffen von der passenden Seite.
- Während der 3D-Gizmo-Bewegung folgt die Kamera dem Objektmittelpunkt.
- Ist die ausgewählte Waffe nicht sichtbar, fällt die Kamera auf den
  Charakter zurück. Die Waffe muss in der Hotbar liegen und weggesteckt sein.

UNVERÄNDERT
- Hotbar-Bedingung, vier Trageplätze, funktionierende Rotation und Gizmo
- Serverseitiges Speichern der Positionen in positions.json
- Knochen-Auswahl, Alpha-Z-Design, Waffenbezeichnungen aus V1.9
- Kein Eingriff in bs_inventory oder andere Serverressourcen

INSTALLATION
1. Bisherige alpha_z_weaponcarry/positions.json sichern.
2. Nur die Ressource alpha_z_weaponcarry durch diese Version ersetzen.
3. Eigene positions.json unverändert übernehmen.
4. In der Serverkonsole: refresh; restart alpha_z_weaponcarry.
5. /weaponcarry öffnen und eine sichtbare Waffe auswählen.

TESTSTATUS
Lua- und JavaScript-Syntax und ZIP-Struktur geprüft. Die Kamera muss
im laufenden FiveM-Client abschließend getestet werden.
