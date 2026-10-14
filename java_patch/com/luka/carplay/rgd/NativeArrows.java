/*
 * NativeArrows - switch between the custom maneuver_render 3D arrow (default) and the
 * Virtual Cockpit's own Audi arrows (opt-in, issue #3).
 *
 * The VC draws its native maneuver icon from BAP ManeuverDescriptor (FctID 23) whenever
 * the HU-rendered KDK slot is not shown.  BAPBridge publishes the full CarPlay BAP stream
 * in both modes; in native mode it skips maneuver_render and context 80 and keeps the KDK
 * hidden (ClusterService.setKDKVisibility(false)), the same way MIBSI does it.
 *
 * Opt-in, not the default: on an Audi Q7 (MU1329, issue #9) the VC kept opening the KDK box
 * (Fct44 visible=true) after setKDKVisibility(false) and drew neither its own arrow nor
 * anything into the box, so the box stayed empty.
 *
 * The native-arrows marker is read at every CarPlay session start (RgdModule), so toggling
 * it takes effect on the next phone reconnect.  The persistent marker survives a reboot;
 * the /tmp one does not.  The earlier ".off" opt-out marker is no longer read; native_arrows_off removes it.
 */
package com.luka.carplay.rgd;

import com.luka.carplay.framework.Log;

import java.io.File;

public final class NativeArrows {

    private static final String TAG = "NativeArrows";
    /* Present => native VC arrows instead of the custom 3D arrow (maneuver_render). */
    public static final String[] ON_MARKERS = {
        "/mnt/app/carplay_native_arrows.on", "/tmp/carplay_native_arrows.on"
    };

    private static volatile boolean enabled = false;
    /* True only while a CarPlay/AA route owns BAP in native mode: ClusterService then
     * answers the VC's KDK open requests with "not visible". */
    private static volatile boolean kdkSuppressed = false;

    private NativeArrows() { }

    /** Re-read the marker; called once per session start. */
    public static void refresh() {
        boolean on = false;
        for (int i = 0; i < ON_MARKERS.length && !on; i++) {
            try { on = new File(ON_MARKERS[i]).exists(); }
            catch (Throwable t) { /* never let a marker probe break startup */ }
        }
        if (on != enabled) Log.i(TAG, on ? "native VC arrows ON (no maneuver_render overlay)"
                                         : "native VC arrows OFF (maneuver_render overlay)");
        enabled = on;
    }

    public static boolean isEnabled() { return enabled; }

    static void setKdkSuppressed(boolean suppressed) { kdkSuppressed = suppressed; }

    /** Read by the patched ClusterService before it forwards a VC KDK visibility request. */
    public static boolean isKdkSuppressed() { return kdkSuppressed; }
}
