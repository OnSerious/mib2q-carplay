import com.luka.carplay.core.SiriShortPress;
import de.audi.app.sdsmanager.apps.terminalmode.TerminalModeSDSHandler;
import java.lang.reflect.Field;
import sun.misc.Unsafe;

/** Siri on a short voice-key press is opt-in: without the marker the patched handler gives the
 *  stock answer (speech active only while the phone's speech app runs), CarPlay or not. */
public final class SiriShortPressTest {
    static void check(boolean b, String m) { if (!b) throw new AssertionError(m); }
    static void set(Object o, String n, boolean v) throws Exception {
        Field f = TerminalModeSDSHandler.class.getDeclaredField(n); f.setAccessible(true); f.setBoolean(o, v);
    }
    public static void main(String[] args) throws Exception {
        check(!SiriShortPress.isEnabled(), "marker present on the test host: " + SiriShortPress.ON_MARKER);
        Field uf = Unsafe.class.getDeclaredField("theUnsafe"); uf.setAccessible(true);
        TerminalModeSDSHandler h = (TerminalModeSDSHandler) ((Unsafe) uf.get(null))
            .allocateInstance(TerminalModeSDSHandler.class);
        set(h, "terminalModeDeviceActive", true);
        set(h, "carPlayActive", true);
        set(h, "terminalModeSpeechActive", false);
        check(!h.isTerminalModeSpeechActive(), "short press taken from the car voice control without opt-in");
        set(h, "terminalModeSpeechActive", true);
        check(h.isTerminalModeSpeechActive(), "stock: a running phone speech app must stay active");
        System.out.println("SiriShortPressTest: default off (stock car voice control), stock speech-app case kept PASS");
    }
}
