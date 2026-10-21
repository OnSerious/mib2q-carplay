# mib2q-carplay 1.3

CarPlay and Android Auto on the Audi Virtual Cockpit for **MHI2Q** head units: the phone's own
map on the cluster, turn-by-turn guidance on the cluster and head-up display, cover art, calls on
the cluster phone tab, and now **the CarPlay cluster map through the HW301 wireless dongle**, a
**SafeArea for the Sport skin** and **faster native navigation after power-on with a dongle**.

> [!WARNING]
> This modifies firmware processes and system configuration on your head unit. Use it
> only on a unit you own, never install or test while driving, and accept that you do it
> at your own risk. Everything is reversible with **Uninstall** (stock files are backed up
> on the unit).

> [!IMPORTANT]
> **Run the installer again when updating from 1.2.** 1.3 completes the message IDs in
> `dio_manager.json` and adds a new program file (`nav_boost`). See
> [Update from 1.2](#update-from-12).

## What's new in 1.3

### HW301 wireless dongle: CarPlay map on the Virtual Cockpit
- The HW301 is the `smartBox-xxxx` dongle with the setup page at `192.168.5.1`. With its stock
  firmware it shows CarPlay on the MMI only. With the custom app image **v1166**
  (`hw301_v1166.tar`, attached to this release) it keeps the MMI screen and adds the iPhone's
  own cluster view on the Virtual Cockpit. It is not a copy of the MMI screen.
- The roller zooms the map, the phone draws its turn card (without ETA), and switching the
  cockpit between wide, classic and Sport resizes the map.
- The cluster map also starts when the dongle is already plugged in at power-on.
- Needs this release on the head unit with **Cluster video ON**. Flash the dongle on a bench
  USB supply, never in the car. Stock firmware can be restored at any time, and a dead dongle can
  be recovered over USB. Steps: [HW301 guide](https://github.com/kamgurgul/mib2q-carplay/blob/master/docs/deploy/hw301-dongle.md).
- Other `smartBox-xxxx` boards are not the HW301: do not flash this image onto them.

### CarPlay
- **Sport skin small map has its own SafeArea**
  ([#20](https://github.com/kamgurgul/mib2q-carplay/issues/20)). The Sport skin (big central rev
  counter) moves the small map left, and the classic layout put the position arrow too far left.
  Your own values go in `carplay_safearea_sport.conf` on the card root (*Apply SafeArea from SD*).
- **Long press of the left roller** toggles between the phone map and the Audi map on the
  cockpit. The short press still toggles the route-info line; the roller zooms whichever map is
  visible.
- **Favorites without a number** can be dialled from the cluster phone tab.
- **Verbose logging ON / OFF** in the menu. It stays on after a reboot; *Save logs* still turns it
  on only until the next reboot.

### Fixed
- **Native navigation late or dead after power-on with a CarPlay dongle**
  ([#10](https://github.com/kamgurgul/mib2q-carplay/issues/10),
  [#22](https://github.com/kamgurgul/mib2q-carplay/issues/22)). Navigation took 2-4 minutes to
  come up, or never came back, when CarPlay was the last audio source. The dropped start request
  is now re-sent, and navigation's start-up gets priority until it is up (at most 5 minutes).
  Off switches: `carplay_domain_rescue.off` (card root or `/mnt/app/root`) and
  `/mnt/app/root/carplay_nav_boost.off`.
- **Lane guidance only at the start of a route.** Lanes announced ahead of time are kept until
  they become active.
- **CarPlay did not start, or a phone feature was rejected, after another tool trimmed
  `dio_manager.json`** ([#23](https://github.com/kamgurgul/mib2q-carplay/issues/23)). The
  installer now registers every message ID it needs and moves one found in the wrong list.
- **Vehicle data re-sent on every connect** after iOS rejected it. It is offered only when
  `dio_manager.json` declares it.
- **The first cluster picture could be missed**: the cluster video starts with the phone
  session instead of waiting for native navigation.
- **Android Auto dropped when the cluster day/night theme changed during a session**
  ([#19](https://github.com/kamgurgul/mib2q-carplay/issues/19)). The theme is chosen when the
  phone connects.
- **The touchpad D-pad switch** applies from the next touch instead of the next connection.
- **Position arrow pushed left of the turn card** without route guidance (Waze, no route)
  ([#20](https://github.com/kamgurgul/mib2q-carplay/issues/20)).
- **Third-party apps lost their turn card and ETA in the classic small map**: the classic
  SafeArea is now 300 px tall.
- **Removed:** the "Navigation is initializing" takeover from 1.2. It did not clear the message
  in the car.

## Not yet tested in a car

These passed every bench test, but have not been driven yet. Please report how they behave
(with **Save logs**):

- Sport skin small-map SafeArea
- Faster native navigation start after power-on with a dongle
- HW301: the cockpit map when the dongle is already plugged in at power-on

## What works and what does not

Developed on an Audi A5 (F5) with MU1329 (`MHI2Q_ER_AUG22_P5152`); also reported on
`MHI2Q_ER_AUG22_P5092` (MU1329) and `MHI2Q_US_AUG22_P5087` (MU1316).

| | CarPlay | Android Auto |
| --- | --- | --- |
| Phone's map on the Virtual Cockpit | ✅ | ✅ |
| Map follows the cockpit layout (wide / classic / sport) | ✅ (Sport skin: own SafeArea, new) | ✅ |
| Maneuver arrow, distance, lanes, route text on the VC | ✅ (apps with CarPlay route guidance) | ✅ |
| Waze guidance on the VC | ✅ Waze's own card in the cluster map | ✅ |
| Head-up display guidance | ✅ | ✅ |
| Cover art on the VC | ✅ | ✅ |
| Calls on the VC phone tab | ✅ | ✅ (over Bluetooth) |
| Car data to the phone | ✅ | ❌ |
| Steering-wheel roller zooms the cluster map | ✅ | ❌ Android Auto has no zoom command for its cluster map |
| MMI touchpad as D-pad | ✅ (switchable) | stock Android Auto behaviour |
| Wireless adapter | ✅ with tested adapters (see below) | not tested |

**Wireless adapters** reported to work with the cluster map: Baseus Safe Journey (fast),
Carlinkit 5.0 / 2Air (slow to start), AAWireless TWO+ (manufacturer test build) and, new, the
**HW301** with the custom image v1166. Other generic `smartBox-xxxx` dongles do not work.

## Requirements

| | |
| --- | --- |
| Head unit | Audi **MHI2Q** with **Virtual Cockpit**. Update to the latest firmware first. |
| Tools | **M.I.B. (More Incredible Bash)** working on the unit, access to the Green Engineering Menu, a FAT32 SD card |
| Phone | iPhone with CarPlay (USB cable or a tested wireless adapter), or an Android phone with Android Auto. For calls on the phone tab with Android Auto the phone must also be connected over Bluetooth (the normal Android Auto setup). |
| HW301 only | a computer on the dongle's Wi-Fi and a bench USB supply to flash `hw301_v1166.tar` |

**Android Auto cluster map on other firmware:** the map needs a profile for the unit's Android
Auto receiver (`gal`). MU1329 and MU0918 are built in. On other firmware Android Auto stays stock
on the main screen, while turn-by-turn and cover art still work. Send the folder from
**Save logs** to get a profile added.

## What is on the SD card

```text
SD card root/
├─ mod/                     first install: M.I.B. "Run Custom Script"
│  ├─ custom.sh, command.sh   setup (installs everything + the menu in one run)
│  ├─ install/                installer
│  └─ menu/                   Green Engineering Menu installer
├─ carplay/                 the release (also used by the menu's "Install / update")
│  └─ 15 program files + VERSION
└─ (optional) carplay_safearea.conf, carplay_safearea_small.conf, carplay_safearea_sport.conf
```

`extras/MIB-mods/` in the download holds the individual M.I.B. scripts for use without the
menu (copy one `mod/` folder to the card at a time).

## Install (first time)

1. Back up the SD card's current `mod/` folder if it has one.
2. Copy the **contents of `SD-CARD/`** to the root of the M.I.B. SD card: `mod/` and
   `carplay/` must sit directly in the card root.
3. Disconnect the phone. Insert the card.
4. **Green Engineering Menu -> M.I.B. -> Advanced Settings -> Run Custom Script**
   (older M.I.B. release zips: **Run individual script**).
5. Wait for `DONE. mib2q-carplay 1.3 installed.` A `WARN` line names a step that was
   skipped; a `FAILED` line means nothing was changed.
6. Keep the phone disconnected, wait a few seconds, then **reboot the head unit normally**
   (not the forced button combination right after copying files).
7. Connect the phone. The cluster shows the phone's map; the Green Engineering Menu now has
   **CarPlay-RGI**.

For the HW301, flash the dongle afterwards as described in the
[HW301 guide](https://github.com/kamgurgul/mib2q-carplay/blob/master/docs/deploy/hw301-dongle.md).

## Update from 1.2

1. Copy the new `SD-CARD/` contents to the card: `carplay/` **and** `mod/`, because the menu has
   a new button and a renamed one.
2. Run step 4 of *Install* once. This is required for 1.3: besides updating the release and the
   menu, it completes the message IDs in `dio_manager.json`. It only adds what is missing;
   **Uninstall** restores the original file.
3. Reboot the head unit.

## Uninstall

Green Engineering Menu -> CarPlay-RGI -> **Uninstall CarPlay (restore stock)**, then
**Remove this menu**, then reboot. Without the menu: copy `extras/MIB-mods/uninstall/mod/`
to the card as `mod/` and run it from M.I.B. Stock configuration files are restored from
the backups the installer made. The HW301 goes back to stock with `hw301_v129.tar`
(see the HW301 guide).

## Green Engineering Menu: CarPlay-RGI

Settings marked *next connection* apply when the phone is reconnected; no reboot needed.

| Button | What it does |
| --- | --- |
| **Install / update CarPlay (release on SD)** | Installs the release from `carplay/` (or `mod/carplay/`) on the card. Reboot afterwards. |
| **Save logs to SD (+ verbose on)** | Saves all logs to `carplay_logs/NNN/` on the card and switches detailed logging on until the next reboot. For a bug report: press it, reconnect, reproduce, press it again, send the newest folder. |
| **Verbose logging ON / OFF** | **New.** Detailed logging that stays on after a reboot (default OFF). Needed to capture start-up problems. |
| **Cluster video (AltScreen) ON / OFF** | CarPlay: offer the cluster screen to the iPhone (default ON). OFF = no CarPlay map on the cluster; the arrow still works. Also needed for the HW301. *Next connection.* |
| **Route guidance ON / OFF** | Turn-by-turn arrow, route text and HUD guidance, for CarPlay and Android Auto (default ON). |
| **Calibration grid ON / OFF (toggle)** | Draws a coloured ruler over the cluster map (lines every 60 px) to measure the visible area. |
| **Apply SafeArea from SD (carplay_safearea*.conf)** | CarPlay: applies your own layout values from the card root: `carplay_safearea.conf` (wide map), `carplay_safearea_small.conf` (classic small map) and/or `carplay_safearea_sport.conf` (Sport skin small map). Format: four lines `x=`, `y=`, `w=`, `h=`. Not used by the HW301, which has the values built in. *Next connection.* |
| **Reset SafeArea to built-in** | Back to the built-in layout values. *Next connection.* |
| **Small-map SafeAreas ON / OFF (3 ViewAreas)** | **Renamed.** CarPlay: toggles the separate classic and Sport small-map layouts (on by default). *Next connection.* |
| **Re-request cluster map (test app switching)** | CarPlay diagnostic: asks the phone for the cluster map again in the running session. |
| **HW decoder ON / OFF (toggle, default ON)** | Hardware or software decoding of the cluster video. *Next connection.* |
| **HW decoder 2-min delayed start ON / OFF** | CarPlay: software decoding for the first 2 minutes after an MMI start, then hardware (default OFF = hardware at once). Turn on if the MMI freezes when CarPlay connects right after a start. Android Auto always waits. *Next connection.* |
| **Android Auto cluster map ON / OFF** | Offers the second display to Android Auto (default ON). OFF = stock Android Auto; the arrow, HUD and cover art still work. *Next connection.* |
| **Android Auto cluster day/night ON / OFF** | Experimental. Light Android Auto cluster map by day, dark by night (default OFF = always dark). Picked when the phone connects. |
| **Touchpad as D-pad ON / OFF** | CarPlay: finger drags on the MMI touchpad move the selection (default ON). OFF = the touchpad goes to CarPlay as on the stock unit. Applies from the next touch. |
| **Siri on short voice-key press ON / OFF** | CarPlay: a short press of the steering-wheel voice key opens Siri (default OFF = the car's voice control). Applies at once. |
| **HW decoder probe (OMX, logs only)** | Diagnostic: logs the hardware decoder's capabilities; then **Save logs**. |
| **Copy stock lsd.jxe to SD** | Copies the stock HMI file to the card (read-only on the unit; needed only to build from source). |
| **Uninstall CarPlay (restore stock)** | Removes everything (CarPlay and Android Auto parts) and restores the stock configuration. Reboot afterwards. |
| **Remove this menu** | Deletes the CarPlay-RGI page (gone after the next reboot). |

**Settings without a button** (create the file over SSH, delete it to undo):

| File | Effect |
| --- | --- |
| `/mnt/app/root/carplay_vehicle_engine` | engine type sent to the iPhone: `gasoline` (default), `diesel`, `electric` or `cng` |
| `/mnt/app/carplay_aa_phone_tab.off` | Android Auto: keep the stock "Android Auto" note on the phone tab |
| `/mnt/app/root/mibr-carplay111-rgi-url.disabled` | CarPlay cluster map: always the plain map request of 1.1 |
| `/mnt/app/root/mibr-carplay111-fps` | CarPlay cluster frame rate, 5 to 60 (default 30) |
| `/mnt/app/root/mibr-carplay111-physical` | CarPlay cluster size in mm, `width height` (default `290 108`) |
| `/mnt/app/root/carplay_domain_rescue.off` (or `carplay_domain_rescue.off` on the card root) | **New.** No re-send of the dropped Media start request after power-on |
| `/mnt/app/root/carplay_nav_boost.off` | **New.** No priority boost for navigation's start-up after power-on |

## Known limitations

- **No zoom of the Android Auto cluster map.** Android Auto offers no zoom command for its
  cluster display. The roller zooms only the hidden Audi map, so the VC scale bar still moves.
- **Android Auto size and density** are fixed when the phone connects; layouts switch live.
- The CarPlay turn-by-turn **arrow** needs an app that sends CarPlay route guidance (Apple Maps,
  Google Maps, recent AMap). Waze shows its own card inside the cluster map instead.
- The phone decides which navigation app is drawn on the cluster; the car cannot pick one.
- **No caller photo** on the phone tab, and a mute changed on the iPhone during a call shows on the
  cockpit only after the call.
- **HW301:** the cluster map settings (URL, SafeAreas) are built into the dongle image; the
  head unit's SafeArea files and the menu's maneuver settings do not reach it.
- Layout values are the built-in defaults for the B9 cluster. Other clusters may need their
  own values (see *Calibration grid* and *Apply SafeArea from SD*).

## Troubleshooting

| Symptom | Try |
| --- | --- |
| No CarPlay map on the cluster | **Cluster video ON**; reconnect the phone; with a wireless adapter, check the tested list above. |
| HW301: CarPlay on the MMI but no cockpit map | Head unit on 1.3 with **Cluster video ON**? `curl http://192.168.5.1/clbuild.txt` shows `v1166-…`? Reconnect the phone. |
| Native navigation slow after power-on with a dongle | Should be fixed; if not, turn on **Verbose logging**, reboot, reproduce, **Save logs** and report. |
| Cluster map flickers between the Audi map and black | **HW decoder ON / OFF** (software decoding); **Save logs** and report ([#18](https://github.com/kamgurgul/mib2q-carplay/issues/18)). |
| MMI freezes when CarPlay connects right after a start | **HW decoder 2-min delayed start ON**. |
| Phone tab still shows "Apple CarPlay mode" | Run the 1.3 installer again (it registers the phone message IDs), reboot. |
| No Android Auto map on the cluster | **Android Auto cluster map ON**; reconnect; **Save logs** and look for `init enabled` in `aa_cluster_hook.log` (no profile for your firmware yet if it says `unknown_receiver`). |
| No arrow / HUD | **Route guidance ON**; for Android Auto, start navigation in Android Auto itself. |
| Anything else | **Save logs to SD** (twice, as described above) and report with the `carplay_logs/NNN` folder. |

## Credits and license

The biggest thanks go to
[Mr-MIBonk/M.I.B._More-Incredible-Bash](https://github.com/Mr-MIBonk/M.I.B._More-Incredible-Bash),
the base this mod is built on: every install, update and uninstall runs through M.I.B.

Also built on [luka-dev/mib2q-carplay-rgi](https://github.com/luka-dev/mib2q-carplay-rgi) (base
hook, Java patch, maneuver renderer, installer; in 1.3 also the classic and Sport SafeAreas, the
vehicle-status check and the removal of the navigation takeover),
[harman-f/mhi2_altscreen_carplay](https://github.com/harman-f/mhi2_altscreen_carplay) (CarPlay
cluster video hook) and
[wasimlhr/mib2q-android-auto-cluster](https://github.com/wasimlhr/mib2q-android-auto-cluster)
(Android Auto receiver hook, navigation translation, layouts, cover-art converter), whose hook
adapts [chopinwong01/mhi2-android-auto-video-vc](https://github.com/chopinwong01/mhi2-android-auto-video-vc).
Findings from [joeyQuery/MHI2-altScreen](https://github.com/joeyQuery/MHI2-altScreen) and
[yuedizhibo/MHI2Q-CarPlay-AltScreen](https://github.com/yuedizhibo/MHI2Q-CarPlay-AltScreen).
See `LICENSE` and `THIRD_PARTY_NOTICES.md` in this download. `carplay_hook.jar` contains
modified classes of the Audi/e.solutions HMI and is not covered by the GPL (see the notices).
`hw301_v1166.tar` contains the dongle's stock firmware with an added library; it is provided for
owners of that dongle only.
