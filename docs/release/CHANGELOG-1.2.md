# mib2q-carplay 1.2 - changelog (draft)

Changes since [1.1](RELEASE_NOTES-1.1.md). Draft: not released yet, the entries marked
*car test pending* still need a run on the car.

## New

- **Native Audi arrows on the Virtual Cockpit (optional).** With *Native Audi VC arrows ON
  (opt-in)* the VC draws its own Audi maneuver arrows instead of the custom 3D arrow,
  including the roundabout exit number, for CarPlay and Android Auto. The 3D arrow stays the
  default: not every VC supports this. On an Audi Q7 (MU1329) the VC showed an empty box
  instead of an arrow. If yours does that, press *Native Audi VC arrows OFF (3D arrow,
  default)*. Also available as M.I.B. mods `native_arrows_on` / `native_arrows_off`. Both
  apply on the next phone connection.
  ([#3](https://github.com/kamgurgul/mib2q-carplay/issues/3),
  [#9](https://github.com/kamgurgul/mib2q-carplay/issues/9))
- **Android Auto cluster map follows MMI day/night (opt-in, experimental).** With *Android
  Auto cluster day/night ON / OFF* in the menu, the Android Auto map on the VC is light by day
  and dark by night, following the MMI, instead of always dark. It switches live while the
  phone is connected. Off by default: in earlier tests by others, the light theme crashed
  Android Auto on the phone. If that happens, press the button again.
  ([#16](https://github.com/kamgurgul/mib2q-carplay/issues/16)) *Car test pending.*
- **CarPlay cluster frame rate up to 60 fps (opt-in).** `/mnt/app/root/mibr-carplay111-fps`
  now accepts 5 to 60 (before: 20, 25 or 30). The default stays 30. Above 30 is at your own
  risk: some MHI2Q builds crash at 60. ([#9](https://github.com/kamgurgul/mib2q-carplay/issues/9))
- **CarPlay cluster physical size can be overridden.** `/mnt/app/root/mibr-carplay111-physical`
  takes `width height` in mm (or only the width). iOS scales the cluster UI from this size,
  so e.g. `320 120` (the size other packages report) moves the car marker up in apps such as
  Sygic. The default stays 290 x 108 mm, the real 12.3" panel.
  ([#9](https://github.com/kamgurgul/mib2q-carplay/issues/9))

## Fixed

- **MMI froze and rebooted when Android Auto started with a route already running**
  (Android Auto cluster map and hardware decoder ON). If Google Maps navigation was already
  running when the phone connected right after an MMI start, the cluster map's video decoder
  was opened about a minute after boot. That hung the head unit's video hardware. Our cleanup
  then got stuck inside it. The MMI screen and the Audi map on the VC froze, music stopped
  some minutes later, and the unit rebooted. Now:
  - for the first 2 minutes after boot the cluster video is decoded in software, then it
    switches to the hardware decoder by itself (one short reconnect of the cluster stream,
    the cockpit keeps showing the phone's map);
  - a decoder that stops answering is never touched again: hardware decoding is switched off
    and the cluster renderer restarts on software decoding;
  - a watchdog ends the renderer if a call to the decoder ever blocks, so it can no longer
    freeze the MMI.

  ([#14](https://github.com/kamgurgul/mib2q-carplay/issues/14)) *Car test pending.*
- **No turn arrow with some third-party CarPlay apps (e.g. Sygic).** Apps that leave out the
  junction type got no arrow for ordinary turns. The arrow is now chosen from the maneuver
  type, exit angle and driving side only, as in MIBSI. Apple Maps and Google Maps are
  unchanged. ([#9](https://github.com/kamgurgul/mib2q-carplay/issues/9))
- **"Follow road" far from the next turn**, like Audi navigation: the maneuver box shows the
  real turn only from 1.5 km in town, 3 km on the highway.
  ([#9](https://github.com/kamgurgul/mib2q-carplay/issues/9))
- **Route-info toggle (left roller press) did nothing with the native arrows** on cars
  without the VC screen manager (Audi Q7). ([#9](https://github.com/kamgurgul/mib2q-carplay/issues/9))
- **No short Audi-map flash** about 2 minutes after start, when the cluster video switches
  from software to hardware decoding.
  ([#9](https://github.com/kamgurgul/mib2q-carplay/issues/9))

## Documentation and project

- README: **Supported units** (P5152 A5 F5 MU1329, P5092 MU1329) and **Tested wireless
  adapters** (Baseus Safe Journey: works, fast; Carlinkit 5.0 / 2Air: works, slow to start;
  generic `smartBox-xxxx`: does not work).
  ([#5](https://github.com/kamgurgul/mib2q-carplay/issues/5))
- README: a section on the CarPlay-RGI Green Engineering Menu page and all its buttons.
- GitHub bug report template. It asks for firmware, settings and both log saves.

## Updating from 1.1

Copy both `carplay/` **and** `mod/` to the card: the menu has three new buttons. Run
**M.I.B. -> Advanced Settings -> Run Custom Script** once, then reboot.

The 3D arrow is still the default. To try the VC's own Audi arrows, press **Native Audi VC
arrows ON (opt-in)** and reconnect the phone.
