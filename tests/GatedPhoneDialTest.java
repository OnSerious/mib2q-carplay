package com.luka.carplay.telephony;

import de.audi.atip.interapp.combi.bap.phone.CombiBAPServicePhone;
import de.audi.atip.interapp.combi.bap.phone.data.FsgSetup;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;

/** VC dial through the real GatedPhoneService: a favorite's contact-formatted number reaches
 *  CarPlay as a clean tel: body, a recent's plain number is unchanged, a favorite iOS lists
 *  without a number is dialled by AddressBookID (hook InitiateCall), anything else fails. */
public final class GatedPhoneDialTest {
    static String dialed;
    static byte[] telCmd;
    static int lastResult = -1;
    static void check(boolean b, String m) { if (!b) throw new AssertionError(m); }

    static void dial(String number, String want) {
        dialed = null; lastResult = -1;
        check(GatedPhoneService.onVcDial(number, null), "dial not handled: " + number);
        check(want == null ? dialed == null && lastResult == 1 : want.equals(dialed) && lastResult == 0,
            "\"" + number + "\" dialed as \"" + dialed + "\" result " + lastResult + ", want \"" + want + "\"");
    }

    public static void main(String[] args) throws Exception {
        CombiBAPServicePhone real = (CombiBAPServicePhone) Proxy.newProxyInstance(
            GatedPhoneDialTest.class.getClassLoader(), new Class[]{CombiBAPServicePhone.class},
            new InvocationHandler() {
                public Object invoke(Object p, Method m, Object[] a) {
                    if (m.getName().equals("dialNumberResult")) lastResult = ((Integer) a[0]).intValue();
                    return null;
                }
            });
        GatedPhoneService g = new GatedPhoneService(real);
        GatedPhoneService.setCommands(new GatedPhoneService.Commands() {
            public void dial(String number) { dialed = number; }
        });
        g.updateFsgSetup(FsgSetup.builder().setAppleLinkConnectionPossible(true)
            .setMobileConnectionType(5).build());               /* CarPlay: gate on */

        dial("+48600123456", "+48600123456");                    /* recent: unchanged */
        dial("+48 600 123 456", "+48600123456");                 /* favorite with spaces */
        dial("‪+48 600-123-456‬", "+48600123456"); /* NBSP, dashes, bidi marks */
        dial("(555) 123-4567", "5551234567");
        dial("*100#", "*100%23");
        dial("+1 555 123 4567,,1234", "+15551234567,,1234");     /* pause + extension */
        dial("john@example.com", null);                          /* FaceTime-only favorite */
        dial("", null);

        /* Favorites as hook/telephony publishes them: "Mom" has no RemoteID, "Bob" has one. */
        String lists = "r.n:i:0\nf.n:i:2\n"
            + "f.0.a:s:\nf.0.b:s:Mom\nf.0.id:s:7D19170A-959C-4204-AC2A-6BE3864DCCBC\nf.0.svc:i:1\n"
            + "f.1.a:s:+48 600 123 456\nf.1.b:s:Bob\nf.1.id:s:AB-2\nf.1.svc:i:1\n";
        byte[] raw = lists.getBytes("UTF-8");
        java.lang.reflect.Method set = GatedPhoneService.class.getDeclaredMethod("setLists",
            new Class[]{com.luka.carplay.bus.CarplayBus.Data.class});
        set.setAccessible(true);
        set.invoke(g, new Object[]{com.luka.carplay.bus.CarplayBus.parseText(raw, raw.length)});
        GatedPhoneService.telSink = new GatedPhoneService.TelSink() {
            public boolean send(byte[] cmd) { telCmd = cmd; return true; }
        };

        dialed = null; telCmd = null; lastResult = -1;
        check(GatedPhoneService.onVcDial("", "Mom"), "favorite dial not handled");
        check(dialed == null && lastResult == 0 && telCmd != null && telCmd[0] == 6 && telCmd[1] == 1
            && new String(telCmd, 2, telCmd.length - 2, "UTF-8").equals("7D19170A-959C-4204-AC2A-6BE3864DCCBC"),
            "favorite without a number not dialled by AddressBookID");

        dialed = null; telCmd = null;
        check(GatedPhoneService.onVcDial("+48 600 123 456", "Bob"), "favorite with number not handled");
        check("+48600123456".equals(dialed) && telCmd == null, "favorite with a number must use tel:");

        telCmd = null; lastResult = -1;
        check(GatedPhoneService.onVcDial("", "Nobody"), "unknown favorite not handled");
        check(telCmd == null && lastResult == 1, "unknown name must fail, not dial");
        System.out.println("GatedPhoneDialTest: favorite formatting stripped, recent unchanged, "
            + "*/# and pauses kept, number-less favorite via AddressBookID, unknown entry fails PASS");
    }
}
