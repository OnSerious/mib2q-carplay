# 1.2-q7o (Q7, privat)

Basis: kamgurgul master 7d51a8c (v1.2 + alle Fixes bis 19.10.). Standard = kamgurgul pur.
Unsere Zusaetze sind alle im Hidden Menue "CarPlay-RGI" schaltbar.

## Installation von der SD-Karte (M.I.B. -> Run Custom Script)

- Schritt 0/2 (neu): die Unit wird erst komplett aufgeraeumt. Alle Original-Dateien zurueck,
  alle CarPlay-Dateien weg, alle Schalter aller q7-Versionen weg (auch die alten 5.1-Schalter),
  Hidden-Menue-Seite weg. Gibt es dabei ein Problem, wird nichts installiert ("STOPP").
  Log: `q7_clean_log.txt` auf der Karte.
- Schritt 1/2: CarPlay (kamgurgul-Installer), Schritt 2/2: Hidden-Menue-Seite.

## Neu von kamgurgul seit q7n (19.10.)

- Audi-Navigation startet nach dem Einschalten nicht mehr 2-4 Min zu spaet (#25): verlorene
  Startanfrage wird nach ~11 s erneut gesendet (aus: `/mnt/app/root/carplay_domain_rescue.off`),
  Navigation bekommt beim ersten Start mehr Vorrang (aus: `/mnt/app/root/carplay_nav_boost.off`),
  Tachokarte wartet bis 300 s auf die Navigation.
- Fahrzeugdaten an das iPhone nur noch, wenn sie richtig angemeldet sind (sonst lehnt iOS
  die Verbindung ab, "Geraet nicht unterstuetzt", Luka #53).
- Der Umweg fuer "Navigation wird initialisiert" ist entfernt (hat im Auto nicht gewirkt).
- Neuer Menuepunkt "Ausfuehrliches Log AN / AUS" (bleibt nach Neustart, Standard AUS).
- "Logs speichern" sichert auch Absturzprotokolle des Video-Chips und das Navi-Startprotokoll.
- Status zeigt die zwei neuen Navi-Schalter; das Aufraeumen (Schritt 0) entfernt auch nav_boost.

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
