# 1.2-q7n (Q7, privat)

Basis: kamgurgul master 1c3e075 (v1.2 + alle Fixes bis 17.10.). Standard = kamgurgul pur.
Unsere Zusaetze sind alle im Hidden Menue "CarPlay-RGI" schaltbar.

## Installation von der SD-Karte (M.I.B. -> Run Custom Script)

- Schritt 0/2 (neu): die Unit wird erst komplett aufgeraeumt. Alle Original-Dateien zurueck,
  alle CarPlay-Dateien weg, alle Schalter aller q7-Versionen weg (auch die alten 5.1-Schalter),
  Hidden-Menue-Seite weg. Gibt es dabei ein Problem, wird nichts installiert ("STOPP").
  Log: `q7_clean_log.txt` auf der Karte.
- Schritt 1/2: CarPlay (kamgurgul-Installer), Schritt 2/2: Hidden-Menue-Seite.

## Unsere Zusaetze (alle schaltbar)

| Menuepunkt | Standard | Schalter-Datei |
|---|---|---|
| Langdruck linke Walze = Original-Audi-Karte | AN | `/mnt/app/carplay_longpress_map.off` = AUS |
| App-Abbiegekarte im Tacho waehrend Route | AUS (wie kamgurgul) | `/mnt/app/root/mibr-carplay111-rgi-url.disabled` = AN |
| Eigener Kartenbereich im Sport-Layout | AUS (wie kamgurgul) | `/mnt/app/root/mibr-carplay111-viewareas.sport` = AN |
| Status anzeigen | - | zeigt alle Schalter |

- Langdruck AUS: ein Langdruck tut nichts. Ist gerade die Audi-Karte gewaehlt, bringt der
  naechste Langdruck trotzdem noch die CarPlay-Karte zurueck.
- Hardware-Decoder: wieder wie kamgurgul sofort (q7l hatte 2 Min Verzoegerung als Standard).
  "Hardware-Decoder erst 2 Min nach MMI-Start" bleibt im Menue einschaltbar
  (`/mnt/app/root/altscreen_render.hwdecode.delayed`), falls das Einfrieren (#22) wiederkommt.
- Log-Speichern aus q7k bleibt (sloginfo zuerst, 30-s-Waechter).
- Menue und Rueckmeldungen auf Deutsch.

## Nicht mehr drin

- CarPlay 5.1 / APAC (q7m-audio) ist komplett entfernt.
