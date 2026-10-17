/*
 * LongPressMap - switch for "long press of the left roller toggles phone map / stock map".
 *
 * On by default.  The marker (GEM "Long press: stock Audi map ON / OFF") turns the toggle off:
 * a long press then does nothing, except bringing the phone map back if the stock map was
 * chosen before the switch, so the cluster never stays on the stock map.  Read on every long
 * press, so the toggle applies at once.
 */
package com.luka.carplay.core;

import java.io.File;

public final class LongPressMap {
    public static final String OFF_MARKER = "/mnt/app/carplay_longpress_map.off";

    private LongPressMap() { }

    public static boolean isEnabled() {
        try { return !new File(OFF_MARKER).exists(); }
        catch (Throwable t) { return true; }
    }
}
