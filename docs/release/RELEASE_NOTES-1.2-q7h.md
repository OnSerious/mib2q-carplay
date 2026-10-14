# 1.2-q7h (test build, Q7)

Based on kamgurgul release v1.2 (unchanged otherwise).

- Long press of the left roller: phone map <-> stock map. Uses the keypanel's own
  long-press state (LONGPRESSED), no timer. The short press (route-info line) now acts on
  release, so a long press does not toggle the line.
- While the stock map is shown, the roller zooms only the stock map.
- Hidden menu button "Sport own ViewArea ON / OFF" (default OFF = kamgurgul's Sport, using the
  classic ViewArea). ON adds a third ViewArea for the Sport small map (SafeArea 590,88 350x296),
  marker `/mnt/app/root/mibr-carplay111-viewareas.sport`.
