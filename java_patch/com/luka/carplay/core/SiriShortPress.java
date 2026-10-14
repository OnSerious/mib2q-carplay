/*
 * SiriShortPress - opt-in switch for "Siri on a short press of the steering-wheel voice key".
 *
 * Off by default: the short press starts the car's own voice control as stock, the long press
 * starts Siri as stock.  The marker (GEM "Siri on short voice-key press ON / OFF") turns the
 * short press into a Siri tap while CarPlay is connected (TerminalModeSDSHandler,
 * CarPlaySpeechRequestHandler).  Read on every press, so the toggle applies at once.
 */
package com.luka.carplay.core;

import java.io.File;

public final class SiriShortPress {
    public static final String ON_MARKER = "/mnt/app/carplay_siri_short.on";

    private SiriShortPress() { }

    public static boolean isEnabled() {
        try { return new File(ON_MARKER).exists(); }
        catch (Throwable t) { return false; }
    }
}
