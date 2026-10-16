/*
 * NavReadyMarker - tells carplay_monitor.sh that native navigation is up.
 *
 * With a phone connected at power-on, the CarPlay / Android Auto session starts in the same
 * window as native navigation.  Navigation then sometimes misses the service manager's ~60 s
 * initialisation deadline and is relaunched (carplay_logs 024, 027), or never comes back (022).
 * The monitor holds our two cluster renderers back after power-on until this marker exists
 * (capped), so they stay out of that window.  Nothing uses them before Navigation exists:
 * route guidance waits for it anyway.
 *
 * One daemon thread per boot polls the Navigation singleton (a plain static field) once a
 * second, writes the marker and exits.  /tmp is RAM, so the marker is gone after a reboot.
 *
 * Copyright (c) 2026 LuKa (@LuKa_dev)
 */
package com.luka.carplay.core;

import com.luka.carplay.framework.Log;

public final class NavReadyMarker {
    private static final String TAG = "NavReady";
    public static final String MARKER = "/tmp/carplay_nav_ready";
    private static final long POLL_MS = 1000L;
    private static final int MAX_POLLS = 600;           /* 10 min: the monitor has long given up */
    private static boolean started;

    private NavReadyMarker() { }

    /** Starts the watcher once per process (HMI = per boot); later calls do nothing. */
    public static synchronized void watch() {
        if (started) return;
        started = true;
        Thread t = new Thread(new Runnable() {
            public void run() {
                for (int i = 0; i < MAX_POLLS; i++) {
                    if (navigationUp()) { publish(i); return; }
                    try { Thread.sleep(POLL_MS); } catch (InterruptedException e) { return; }
                }
                Log.w(TAG, "native navigation not up after " + MAX_POLLS + " s; marker not written");
            }
        }, "carplay-nav-ready");
        t.setDaemon(true);
        t.start();
    }

    private static boolean navigationUp() {
        try { return de.audi.tghu.navi.app.Navigation.getInstance() != null; }
        catch (Throwable t) { return false; }
    }

    private static void publish(int polls) {
        try {
            new java.io.FileOutputStream(MARKER).close();
            Log.i(TAG, "native navigation up after " + polls + " s of watching: cluster renderers released");
        } catch (Throwable t) {
            Log.w(TAG, "marker " + MARKER + " not written: " + t);
        }
    }
}
