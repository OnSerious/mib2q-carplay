/*
 * AaClusterTheme — tells the Android Auto gal hook whether the MMI shows its day or night
 * design, so the opt-in cluster day/night theme (marker /mnt/app/root/aa_cluster.daynight,
 * aa_uiconfig.c) can send the phone Light by day and Dark by night.
 *
 * /tmp/aa_cluster_theme is one fixed 6-byte record rewritten in place ("day  \n" or
 * "night\n"), for the same reason as AaClusterView: /tmp is /dev/shmem, no truncate-safe
 * rename, and a fixed length means a concurrent reader never sees a short record.  Always
 * written (the hook alone checks the marker), so turning the option on needs no restart.
 * Fed by the stock day/night listener (de.audi.app.terminalmode.NightDayModeHandler).
 *
 * Java 1.4.  SPDX-License-Identifier: GPL-3.0-or-later
 */
package com.luka.carplay.aa;

import com.luka.carplay.framework.Log;

import java.io.RandomAccessFile;

public final class AaClusterTheme {
    public static final String PATH = "/tmp/aa_cluster_theme";

    private static int last = -1;   /* -1 unknown, 0 day, 1 night */

    private AaClusterTheme() {}

    public static String record(boolean night) {
        return night ? "night\n" : "day  \n";
    }

    /** NightDayModeHandler, on every MMI day/night update. Never throws. */
    public static synchronized void publish(boolean night) {
        int v = night ? 1 : 0;
        if (v == last) return;
        RandomAccessFile f = null;
        try {
            f = new RandomAccessFile(PATH, "rw");
            f.seek(0);
            f.write(record(night).getBytes());
            last = v;
            Log.i("AA", "cluster theme -> " + record(night).trim());
        } catch (Throwable t) {
            /* retried on the next day/night update */
        } finally {
            if (f != null) try { f.close(); } catch (Throwable t) { /* ignore */ }
        }
    }
}
