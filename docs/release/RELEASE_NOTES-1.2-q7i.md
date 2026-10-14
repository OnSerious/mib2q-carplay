# 1.2-q7i (test build, Q7)

Based on kamgurgul release v1.2 (unchanged otherwise).

- Long press of the left roller: phone map <-> stock map. Uses the keypanel's own
  long-press state (LONGPRESSED), no timer. The short press (route-info line) now acts on
  release, so a long press does not toggle the line.
- While the stock map is shown, the roller zooms only the stock map.
- Hidden menu button "Sport own ViewArea ON / OFF" (default OFF = kamgurgul's Sport, using the
  classic ViewArea). ON adds a third ViewArea for the Sport small map (SafeArea 590,88 350x296),
  marker `/mnt/app/root/mibr-carplay111-viewareas.sport`.
- Hidden menu button "App turn card on cluster during route ON / OFF" (default OFF = v1.2:
  map only while our arrow shows the route). ON keeps the app's own turn card and ETA in the
  cluster video during route guidance, as before 1.2 (e.g. "Start on <street>"). Marker
  `/mnt/app/root/mibr-carplay111-rgi-url.disabled`, applies from the next route start.
