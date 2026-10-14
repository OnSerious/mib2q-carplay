---
title: Native VC arrows - KDK hidden, VC draws FctID 23
tags: [cluster, kdk, bap, switch]
status: verified-decompile
sources:
  - code: java_patch/com/luka/carplay/rgd/NativeArrows.java
  - code: java_patch/com/luka/carplay/rgd/BAPBridge.java
  - code: java_patch/de/audi/tghu/navi/app/cluster/ClusterService.java
  - firmware: lsd.jxe ClusterKDKHandlerImpl (refreshState / notifyKombi / setKDKVisibility)
  - binary: MIBSI mhi2q-aa-navigation-proxy.jar (Mhi2qAaNavProxy, TurnCardPolicy), MHI2Q_ER_AUG22_P5092
---

# Native VC arrows - KDK hidden, VC draws FctID 23

Opt-in mode (issue #3): the Virtual Cockpit shows its **own Audi maneuver arrows** instead of
the `maneuver_render` 3D arrow. The 3D arrow is the default: on an Audi Q7 (MU1329, issue #9)
the VC kept the KDK box open and drew nothing (see *Open points*).

## 📋 Context

> [bap-fctids](../rgd/bap-fctids.md) - FctID 23 descriptor -> **native-arrows** - KDK hidden ->
> the VC draws the icon. With the switch off: [compositing](compositing.md) / [kdk-geometry](kdk-geometry.md).

This is **not** the blocked Class 46 AIO-arrow path ([vc-aio-arrow](../re/firmware/vc-aio-arrow.md)).
It uses the same BAP stream that already drives the HUD. The only difference is that the HU stops
offering the KDK (junction box) slot.

## 🔍 Why hiding the KDK is enough

> `status: verified-decompile` (stock `ClusterKDKHandlerImpl` in lsd.jxe): `setKDKVisibility(v)` ->
> `refreshState(v)` -> `notifyKombi()` -> `CombiBAPListener.setSupplementaryMapVisibility(v, true)`
> (+ `setSupplementaryMapView(available ? 1 : 0)`). KDK *available* = KOMO view enabled+visible &&
> rgActive && !standby (&& clamp 15 on FPK). *Visible* is the last value passed in.

With supplementary-map visibility false, the VC shows no KDK box and draws its native icon from
`ManeuverDescriptor`, including the roundabout exit number. MIBSI does exactly this: at session
start it forces rgActive + RGI valid, then calls `ClusterService.setKDKVisibility(false)`
(`forceClusterCardUnavailable`), and it keeps publishing FctIDs 17/39/23/18/49/55.

## ⚙️ What the switch changes

Native arrows are on only while the marker `/mnt/app/carplay_native_arrows.on` (or `/tmp/...`)
exists. It is read by `RgdModule` at every session start and latched by `BAPBridge.onStart()` per
route. Toggle: `native_arrows_on` (creates the marker) / `native_arrows_off` (removes it), as M.I.B.
mods and GEM buttons. Both also delete the `.off` marker of earlier builds, which is no longer read.

| | 3D arrow (default) | native arrows (`.on` marker) |
|---|---|---|
| `maneuver_render` / displayable 98 | started, primed | never started |
| cluster context | ctx 80 (or 82 with AltScreen) | stays ctx 74 (or 81) |
| `isPresentationReady()` | BAP + renderer FRAME_READY | BAP start only |
| `ScreenModule` | `navActive` + `routeGuidanceActive` | `routeGuidanceActive` only (no overlay ctx); the roller route-info toggle reads either |
| KDK | VC opens it (Fct44) | `setKDKVisibility(false)` at start; VC open requests answered "hidden" (`ClusterService.setSupplementaryMap`) until route end |
| FctID 23 / maneuver box far from the turn | `FOLLOW_STREET` (box: approach arrow) beyond prepare (1.5 km city / 3 km highway), ManeuverState 1 | `FOLLOW_STREET` beyond prepare (1.5 km city / 3 km highway), ManeuverState 1 |
| FctID 18/19/21/22/24/46/55 | unchanged | unchanged |

The suppression (`NativeArrows.isKdkSuppressed`) is released in `shutdown()` and in the failed-start
rollback, so stock navigation's KDK works normally after the route or the phone session ends.

## ⚠️ Open points

- **Audi Q7, MU1329 (issue #9): does not work.** After `native VC arrows: KDK hidden` the VC kept
  sending Fct44 `KDK visible=true`, opened the box on the right and drew nothing into it (black, or
  the map through it), and drew no arrow of its own either. Hence opt-in. Not yet known whether
  that VC needs a different BAP signal (MIBSI's exact sequence) or its skin always reserves the box.
- Other cars: the MIBSI user reports on issue #3, same firmware family.
- If a VC skin re-requests the KDK in a loop, it gets "hidden" each time (the stock answer when no
  KDK is possible). Check the log for repeated `KDK kept hidden for native VC arrows`.
