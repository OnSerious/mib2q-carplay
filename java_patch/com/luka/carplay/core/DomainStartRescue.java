/*
 * DomainStartRescue - re-sends an HMI startDomain request that the target app dropped.
 *
 * After power-on with CarPlay as the last audio source ("Lastmode Audi: 48") the HMI's
 * StartupManager asks for startDomain(Media, 0xd00) at ~7 s, while medialauncher is still in its
 * own run-mode reset (APP_RUN_MODE 1280 -> 17664 at ~10 s).  The request is lost, the domain
 * stays at 0x4500 and stock DomainHandler.doStartDomain waits out its fixed 20 s timeout before
 * asking again (answered in 6 ms).  Every later domain moves 20 s late, so native navigation
 * starts at ~33 s, right inside a CarPlay dongle's session bring-up, misses its start deadline
 * and is relaunched or never comes back (carplay_logs 027/028/longstart/hang).
 *
 * This watcher changes no stock class.  For the domains in WATCHED it reads the stock domain
 * history (under the stock DOMAIN_SYNCER lock) and, when a request is still unanswered although
 * the domain has reported a newer state since, re-sends the same DSIStartup.startDomain the
 * stock code would send after its timeout.  At most MAX_RESENDS per request, only in the first
 * WINDOW_MS (60 s) after HMI start.  Any mismatch in the stock layout disables it (stock behaviour).
 *
 * Off switch, no rebuild: a file named carplay_domain_rescue.off on the SD card root (checked
 * before every re-send) or /mnt/app/root/carplay_domain_rescue.off.  Java 1.4 / Foundation 1.1.
 *
 * Copyright (c) 2026 LuKa (@LuKa_dev)
 */
package com.luka.carplay.core;

import com.luka.carplay.framework.Log;
import java.io.File;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.List;

public final class DomainStartRescue implements Runnable {
    private static final String TAG = "DomainRescue";
    static final String[] OFF_MARKERS = {
        "/mnt/app/root/carplay_domain_rescue.off",
        "/fs/sda0/carplay_domain_rescue.off", "/fs/sdb0/carplay_domain_rescue.off",
        "/net/mmx/fs/sda0/carplay_domain_rescue.off", "/net/mmx/fs/sdb0/carplay_domain_rescue.off"
    };
    /* Only the domain whose dropped request the logs prove; Nav is slow, not dropped. */
    static final String[] WATCHED = { "Media" };

    static final long POLL_MS = 250L;
    static final long MIN_AGE_MS = 2000L;      /* the request itself is at least this old */
    static final long SETTLE_MS = 1000L;       /* the newer, non-matching state is at least this old */
    static final long RESEND_GAP_MS = 3000L;
    static final long WINDOW_MS = 60000L;          /* the Media request is at ~7 s */
    static final int MAX_RESENDS = 2;

    /* DomainHandler$DomainHistoryElement action codes and the stock failed bit. */
    static final int ACTION_REQUESTED = 0;
    static final int ACTION_UPDATED = 2;
    static final int STATE_FAILED = 0x10;

    private static boolean started;

    /* Resolved once; null anywhere = disabled. */
    private final Object framework;
    private final String[] offMarkers;
    private final long pollMs;
    private Object handler;
    private Field fDomains, fSyncer, fDsi, fFramework, fUpdated, fHistory, fTs, fAction, fStatus;
    private Method mMonotonic, mStartDomain;
    private int[] ids;
    private long[] trackedReq;
    private int[] resends;
    private long[] lastResend;

    DomainStartRescue(Object framework, String[] offMarkers, long pollMs) {
        this.framework = framework;
        this.offMarkers = offMarkers;
        this.pollMs = pollMs;
    }

    /** Called once from the HMI's display-manager construction; never throws. */
    public static synchronized void start(Object framework) {
        if (started) return;
        started = true;
        try {
            if (offMarkerPresent(OFF_MARKERS)) {
                Log.w(TAG, "disabled by carplay_domain_rescue.off");
                return;
            }
            Thread t = new Thread(new DomainStartRescue(framework, OFF_MARKERS, POLL_MS),
                                  "carplay-domain-rescue");
            t.setDaemon(true);
            t.start();
        } catch (Throwable t) {
            Log.w(TAG, "not started: " + t);
        }
    }

    public void run() {
        try {
            long giveUp = System.currentTimeMillis() + WINDOW_MS;
            while ((handler = findHandler()) == null) {     /* normally there before we start */
                if (System.currentTimeMillis() > giveUp || !pause()) return;
            }
            if (!resolve()) return;
            long until = now() + WINDOW_MS;
            for (long now = now(); now <= until; now = now()) {
                poll(now);
                if (!pause()) return;
            }
            Log.i(TAG, "startup window over");
        } catch (Throwable t) {
            Log.w(TAG, "stopped: " + t);
        }
    }

    private boolean pause() {
        try { Thread.sleep(pollMs); return true; } catch (InterruptedException e) { return false; }
    }

    /** One scan of the watched domains; package-private for the test. */
    void poll(long now) throws Exception {
        Object syncer = fSyncer.get(handler);
        Object[] domains = (Object[]) fDomains.get(handler);
        for (int i = 0; i < ids.length; i++) {
            Object d = domains[ids[i]];
            if (d == null) continue;
            int updated;
            Object[] history;
            synchronized (syncer) {                     /* the lock stock mutates the history under */
                updated = fUpdated.getInt(d);
                history = ((List) fHistory.get(d)).toArray();
            }
            long reqTs = -1L, updTs = -1L;
            int reqState = 0;
            for (int h = 0; h < history.length; h++) {
                int action = fAction.getInt(history[h]);
                if (action == ACTION_REQUESTED) {
                    reqTs = fTs.getLong(history[h]);
                    reqState = fStatus.getInt(history[h]);
                    updTs = -1L;
                } else if (action == ACTION_UPDATED && reqTs >= 0L) {
                    updTs = fTs.getLong(history[h]);
                }
            }
            if (reqTs != trackedReq[i]) {
                trackedReq[i] = reqTs;
                resends[i] = 0;
            }
            if (!shouldResend(now, reqTs, reqState, updTs, updated, resends[i], lastResend[i])) continue;
            if (offMarkerPresent(offMarkers)) {
                Log.w(TAG, "carplay_domain_rescue.off present; not re-sending");
                continue;
            }
            Object dsi = fDsi.get(handler);
            if (dsi == null) continue;
            resends[i]++;
            lastResend[i] = now;
            Log.w(TAG, WATCHED[i] + " startDomain(0x" + Integer.toHexString(reqState)
                + ") unanswered " + (now - reqTs) + " ms, state 0x" + Integer.toHexString(updated)
                + " since " + (now - updTs) + " ms: re-sending #" + resends[i]);
            mStartDomain.invoke(dsi, new Object[] { new Integer(ids[i]), new Integer(reqState) });
        }
    }

    /**
     * The dropped-request signature: the last request is unanswered, the domain reported a newer
     * state after it (so its app is alive and has moved on) and that state has settled.
     */
    static boolean shouldResend(long now, long reqTs, int reqState, long updTs, int updated,
                                int resends, long lastResend) {
        if (reqTs < 0L || updTs < 0L || reqState == 0) return false;
        if ((reqState & ~updated) == 0) return false;              /* answered (stock isIncluded) */
        if ((updated & STATE_FAILED) != 0) return false;           /* stock isFailed: not ours */
        if (now - reqTs < MIN_AGE_MS || now - updTs < SETTLE_MS) return false;
        if (resends >= MAX_RESENDS) return false;
        return resends == 0 || now - lastResend >= RESEND_GAP_MS;
    }

    static boolean offMarkerPresent(String[] markers) {
        for (int i = 0; i < markers.length; i++) {
            try {
                if (new File(markers[i]).exists()) return true;
            } catch (Throwable t) { /* unreadable mount: not present */ }
        }
        return false;
    }

    /** The stock DomainHandler's own clock: the one its history timestamps come from. */
    private long now() throws Exception {
        return ((Long) mMonotonic.invoke(fFramework.get(handler), new Object[0])).longValue();
    }

    /** framework.getFwServices().getDomainHandler(), all by reflection (FrameworkAccess or Framework). */
    private Object findHandler() {
        try {
            Method gfs = method(framework.getClass(), "getFwServices", new Class[0]);
            Object fws = gfs.invoke(framework, new Object[0]);
            if (fws == null) return null;
            Method gdh = method(fws.getClass(), "getDomainHandler", new Class[0]);
            return gdh.invoke(fws, new Object[0]);
        } catch (Throwable t) {
            return null;
        }
    }

    /** Resolve and check every stock member once; false = stock layout differs, stay off. */
    boolean resolve() {
        try {
            Class h = handler.getClass();
            fDomains = field(h, "domains");
            fSyncer = field(h, "DOMAIN_SYNCER");
            fDsi = field(h, "dsiProvider");
            fFramework = field(h, "framework");
            Class dc = Class.forName("de.audi.atip.startup.DomainHandler$Domain");
            fUpdated = field(dc, "updated");
            fHistory = field(dc, "actionHistory");
            Class ec = Class.forName("de.audi.atip.startup.DomainHandler$DomainHistoryElement");
            fTs = field(ec, "timestamp");
            fAction = field(ec, "action");
            fStatus = field(ec, "status");
            String[] names = (String[]) field(h, "DOMAIN_NAMES").get(null);
            mMonotonic = Class.forName("de.audi.atip.base.IFrameworkAccess")
                .getMethod("getMonotonicTime", new Class[0]);
            mStartDomain = Class.forName("org.dsi.ifc.startup.DSIStartup")
                .getMethod("startDomain", new Class[] { Integer.TYPE, Integer.TYPE });
            Object[] domains = (Object[]) fDomains.get(handler);
            ids = new int[WATCHED.length];
            for (int i = 0; i < WATCHED.length; i++) {
                ids[i] = -1;
                for (int n = 0; n < names.length && n < domains.length; n++) {
                    if (WATCHED[i].equals(names[n])) ids[i] = n;
                }
                if (ids[i] < 0) throw new IllegalStateException("no domain " + WATCHED[i]);
            }
            if (fTs.getType() != Long.TYPE || fUpdated.getType() != Integer.TYPE)
                throw new IllegalStateException("history field types");
            trackedReq = new long[ids.length];
            resends = new int[ids.length];
            lastResend = new long[ids.length];
            for (int i = 0; i < ids.length; i++) trackedReq[i] = -1L;
            now();
            Log.i(TAG, "watching startDomain for Media (id " + ids[0] + ")");
            return true;
        } catch (Throwable t) {
            Log.w(TAG, "stock startup layout differs, disabled: " + t);
            return false;
        }
    }

    private static Field field(Class c, String name) throws Exception {
        Field f = c.getDeclaredField(name);
        f.setAccessible(true);
        return f;
    }

    private static Method method(Class c, String name, Class[] args) throws Exception {
        for (Class k = c; k != null; k = k.getSuperclass()) {
            try {
                Method m = k.getDeclaredMethod(name, args);
                m.setAccessible(true);
                return m;
            } catch (NoSuchMethodException e) { /* try the superclass */ }
        }
        throw new NoSuchMethodException(name);
    }
}
