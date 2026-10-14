package com.luka.carplay.telephony;

import de.audi.atip.interapp.combi.bap.phone.CombiBAPServicePhone;
import de.audi.atip.interapp.combi.bap.phone.data.FsgSetup;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;

/** FctID 14 through the real GatedPhoneService: Android Auto (6) reaches the VC as HFP (3),
 *  CarPlay (5) is gated, a plain Bluetooth phone and the replay after CarPlay stay stock. */
public final class GatedPhoneAndroidAutoTest {
    static int lastMct = -1, setups;
    static void check(boolean b, String m) { if (!b) throw new AssertionError(m); }
    static FsgSetup fsg(int mct) {
        return FsgSetup.builder().setHfpConnectionPossible(true).setGoogleLinkConnectionPossible(true)
            .setAppleLinkConnectionPossible(true).setMobileConnectionType(mct).build();
    }
    public static void main(String[] args) {
        CombiBAPServicePhone real = (CombiBAPServicePhone) Proxy.newProxyInstance(
            GatedPhoneAndroidAutoTest.class.getClassLoader(), new Class[]{CombiBAPServicePhone.class},
            new InvocationHandler() {
                public Object invoke(Object p, Method m, Object[] a) {
                    if (m.getName().equals("updateFsgSetup")) {
                        lastMct = ((FsgSetup) a[0]).getMobileConnectionType(); setups++;
                    }
                    return null;
                }
            });
        GatedPhoneService g = new GatedPhoneService(real);

        g.updateFsgSetup(fsg(3));
        check(lastMct == 3, "Bluetooth phone not passed through");
        g.updateFsgSetup(fsg(6));
        check(lastMct == 3, "Android Auto (6) not shown as HFP (3)");
        g.updateFsgSetup(fsg(0));
        check(lastMct == 0, "no phone not passed through after Android Auto");

        g.updateFsgSetup(fsg(5));
        check(lastMct == 3, "CarPlay gate did not publish HFP");
        int before = setups;
        g.updateFsgSetup(fsg(6));                       /* CarPlay -> Android Auto hand-over */
        check(setups > before && lastMct == 3, "replay after CarPlay kept the Android Auto note");
        System.out.println("GatedPhoneAndroidAutoTest: AA 6 -> HFP 3, BT/no-phone pass-through, "
            + "CarPlay gate and AA replay PASS");
    }
}
