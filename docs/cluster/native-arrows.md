---
title: Native VC arrows - abandoned (KDK hidden does not give the VC's own arrows)
tags: [cluster, kdk, bap]
status: abandoned
sources:
  - firmware: lsd.jxe ClusterKDKHandlerImpl (refreshState / notifyKombi / setKDKVisibility)
  - binary: MIBSI mhi2q-aa-navigation-proxy.jar (Mhi2qAaNavProxy, TurnCardPolicy), MHI2Q_ER_AUG22_P5092
  - car: issue #9 (Audi Q7 MU1329), carplay_logs/022
---

# Native VC arrows - abandoned

An opt-in mode (issue #3, d873312) tried to let the Virtual Cockpit draw its **own Audi maneuver
arrows** instead of the `maneuver_render` 3D arrow. It was removed: the toggles
(`native_arrows_on` / `native_arrows_off`, GEM buttons, M.I.B. mods), the marker
`/mnt/app/carplay_native_arrows.on` (no longer read; a leftover file is harmless) and the
`ClusterService.setSupplementaryMap` KDK suppression are gone. The 3D arrow is the only mode.

## What it did

During a phone route: publish the full BAP stream (RGStatus 1, FctIDs 39/23/18/49/55), skip
`maneuver_render` and ctx 80, call `ClusterService.setKDKVisibility(false)` and answer every
VC KDK open request (Fct44) with "hidden".

## Why it does not work

- **On the car** (Audi Q7 MU1329, issue #9; a second car in `carplay_logs/022`): the VC kept
  requesting the KDK, opened the box on the right and drew nothing into it (black, or the map
  through it). It never fell back to an arrow of its own.
- **The MIBSI premise was wrong.** MIBSI does not hide the KDK to get native arrows. It renders
  its **own turn card** (`mhi2q-aa-turn-card-renderer`) into the KDK box and opens it only near
  a turn (`TurnCardPolicy.shouldOpen`, 450-1500 m with hysteresis) via `updateRGIString([1])`.
  It publishes **RGStatus = 1 only while that card is open**
  (`rgStatusForPresentation(cardOpen, routeData)`), otherwise 0, and calls
  `setKDKVisibility(false)` when it closes the card. It never sends RGStatus 1 with the KDK
  hidden, which is exactly the state in which these VCs reserve an empty box.
- Stock `ClusterKDKHandlerImpl`: `kdkAvailable = komoViewEnabled && komoViewVisible && rgActive
  && !standby` -> `setSupplementaryMapView(available ? 1 : 0)`; visibility is only the last
  requested value. Nothing in the HU path tells the VC "draw your own icon".

If this is retried, the MIBSI model (own card near the turn, RGStatus tied to the card) is the
documented working sequence; a VC drawing its native icon from FctID 23 during active RG has
not been observed on MU1329.
