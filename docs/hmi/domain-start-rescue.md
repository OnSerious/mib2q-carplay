---
title: Dropped startDomain(Media) at power-on (native navigation late or dead with a dongle)
tags: [hmi, startup, navigation, dongle]
status: implemented, host-tested against stock DomainHandler; needs the car
sources:
  - code: java_patch/com/luka/carplay/core/DomainStartRescue.java
  - code: java_patch/de/audi/tghu/fwhmi/DisplayManagerMIB2High.java (start point)
  - test: tests/DomainStartRescueTest.java (scripts/test_java_transports.sh)
  - logs: carplay_logs 027, 028, carplay_logs_longstart, carplay_logs_hang; carplay_logs_aa/020 (healthy)
---

# Dropped startDomain(Media) at power-on

## What happens

With CarPlay as the last audio source at switch-off (`Lastmode Audi: 48`), the HMI's
`StartupManager` asks for `startDomain(Media, 0xd00)` at ~7 s. medialauncher is still in its own
run-mode reset (`APP_RUN_MODE 1280` -> `17664` at ~10 s) and drops it; the domain stays at
`0x4500`. Stock `DomainHandler.doStartDomain` then waits out its fixed 20 s timeout
(`startDomain( Media, 0xd00 ) timed out!` at 27 s) and asks again: answered in 6 ms.

Every later domain moves 20 s late. Native navigation starts at ~33 s instead of ~16 s, inside a
CarPlay dongle's session bring-up (the dongle is ready at power-on), with the CPU at 95-100 %. It
misses its start deadline, is relaunched (`navStartup -sm-restart 1/2`) or never comes back:
no `navStartup` in `pidin`, `NavReady: native navigation not up after 600 s`. Direct iPhone sets
never showed a navigation restart; every dongle set with a boot slog shows the timeouts. Issue #10's
trigger (switching off with CarPlay still active) is the same last-mode condition.

| boot | `startDomain(Media)` | answered | `startDomain(Nav)` |
| --- | --- | --- | --- |
| AA 020 (healthy) | 12.8 s, after medialauncher's reset | at once | 15.7 s, up at 23 s |
| dongle 027 | 7.07 s, before the reset | timed out 27.07 s | 32.8 s, timed out 52 s and 80 s, relaunched |

Why a late start ends in a dead navigation (stock behaviour, from upstream's static analysis of
`navStartup`/`servicemgr`, [STOCK_NAV_READINESS.md](https://github.com/luka-dev/mib2q-carplay-rgi/blob/main/docs/cluster-and-rgi/STOCK_NAV_READINESS.md)):
navigation is started only by the HMI's `startDomain(Nav, 0x700)`, never at system start. `navStartup`
then has three handshakes with the engine (startup counter, `INITNAV`, `RUNNAV`), each with a 60 s
timeout, and the launcher's `run` phase has its own 60 s timeout. A failure is restarted at most 3 times
in 600 s, then the process is killed (`on_restart_failed: kill_process`): the "no `navStartup` in
`pidin`" case. Healthy reference: `startDomain` <= 20 s, `APP_RUN_MODE 1796` (0x704, DR+COMM+NAV) at
~26 s. Grep a boot with:

```sh
sloginfo | grep -e startDomain -e APP_RUN_MODE -e updateDomainStatus -e "NAVI: Startup"
```

## The fix

`DomainStartRescue` replaces no stock class. Started once from `DisplayManagerMIB2High`'s constructor
(~5.7 s, before the first `startDomain`), a daemon thread polls the stock domain history every 250 ms
under the stock `DOMAIN_SYNCER` lock, for the **Media** domain only and for 60 s. When the last
request is unanswered, the domain reported a newer, non-failed state after it, the request is at least
2 s old and that state 1 s old, it sends the same `DSIStartup.startDomain(id, state)` stock sends after
its timeout. The request is re-read and sent while holding `DOMAIN_SYNCER`, as stock `doStartDomain`
does, so an answer or a newer stock request that arrived in the meantime is never overtaken. At most 2 re-sends per request, 3 s apart. The stock wait then returns on the answer.

Everything stock is reached by reflection, resolved and type-checked once. Any mismatch logs
`DomainRescue: stock startup layout differs, disabled` and leaves stock behaviour. A re-send logs
`DomainRescue: Media startDomain(0xd00) unanswered ... re-sent #1` (WARN, always in
`/tmp/carplay_java.log`).

## Switching it off / recovery

- **Off switch, no reinstall:** an empty file `carplay_domain_rescue.off` on the **SD card root**
  (`/fs/sda0` or `/fs/sdb0`), or `/mnt/app/root/carplay_domain_rescue.off`. Read at HMI start and before
  every re-send, so a card inserted before the car is started is enough.
- **HMI still starts but something is off:** GEM -> CarPlay-RGI -> Uninstall, or install the previous
  release over it; the jar is only read at boot, so reboot afterwards.
- **HMI does not start (no GEM):** the watcher cannot cause this by itself (it only reads, and its
  start is wrapped in `catch (Throwable)`), but if a new `carplay_hook.jar` breaks the HMI, remove it
  from a root shell (SSH/Telnet over the USB Ethernet adapter, or the serial console) and reboot:
  ```sh
  mount -uw /mnt/app
  mv /mnt/app/eso/hmi/lsd/jars/carplay_hook.jar /mnt/app/eso/hmi/lsd/jars/carplay_hook.jar.bad
  sync; reboot
  ```
  The HMI then starts stock (CarPlay without the mod's Java part); install a working release after.
  Keep the previous release's `carplay_hook.jar` on the card before testing a new one.
