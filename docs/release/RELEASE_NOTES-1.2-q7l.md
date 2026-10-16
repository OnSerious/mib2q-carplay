# 1.2-q7l (test build, Q7)

Based on kamgurgul master 66f301c (v1.2 + favorites dialing, touchpad switch applies at once,
renderers wait for native navigation after power-on, lane guidance fixes from upstream #23),
otherwise unchanged.

- New in q7l, two defaults switched ON (both GEM buttons still toggle them off):
  - Sport own ViewArea: Apple Maps keeps its turn card inside the Sport small map instead of
    pushing it under the gauges. Off marker `/mnt/app/root/mibr-carplay111-viewareas.sport.off`.
  - HW decoder 2-min delayed start for CarPlay (software decode for the first 2 minutes after
    an MMI start): against the videoCore freeze 2-4 min after boot (kamgurgul #22). Off marker
    `/mnt/app/root/altscreen_render.hwdecode.immediate`.
  The old opt-in markers (`...viewareas.sport`, `...hwdecode.delayed`) are no longer read.
- From q7k, log saving (M.I.B. "logging" and GEM "Save logs to SD"): sloginfo is saved first,
  a command still running after 30 s (120 s for the flash `find`) is written to `hung.txt` with
  its pidin line and stopped, so a frozen unit no longer stops the save at `mount`. `top -d -i 2`
  replaces `hogs -i 3` (this hogs has no -i and only printed "illegal option").

- Long press of the left roller: phone map <-> stock map. Uses the keypanel's own
  long-press state (LONGPRESSED), no timer. The short press (route-info line) now acts on
  release, so a long press does not toggle the line.
- While the stock map is shown, the roller zooms only the stock map.
- From q7j (kamgurgul's review of PR #15): the long press acts only on the VC map tab and only
  while the phone video is live; it no longer sends a long select to the phone. The map tab is
  taken from the VC's own map visibility (log line `VC main map visible=...`); until the VC has
  reported it, the old check (route guidance shown) is used.
- Hidden menu button "Sport own ViewArea ON / OFF" (default ON since q7l; OFF = kamgurgul's
  Sport, using the classic ViewArea). ON adds a third ViewArea for the Sport small map
  (SafeArea 590,88 350x296).
- Hidden menu button "App turn card on cluster during route ON / OFF" (default OFF = v1.2:
  map only while our arrow shows the route). ON keeps the app's own turn card and ETA in the
  cluster video during route guidance, as before 1.2 (e.g. "Start on <street>"). Marker
  `/mnt/app/root/mibr-carplay111-rgi-url.disabled`, applies from the next route start.
