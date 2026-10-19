package com.luka.carplay.core;

import de.audi.atip.log.LogChannel;
import de.audi.atip.startup.DomainHandler;
import java.io.File;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.ArrayList;
import java.util.List;

/**
 * DomainStartRescue against the real stock DomainHandler (base.jar): the dropped Media request of
 * carplay_logs 027 is re-sent and stock doStartDomain returns long before its 20 s timeout;
 * answered, failed, capped and switched-off requests are left alone.
 */
public final class DomainStartRescueTest {
    static final int MEDIA = 3, REQ = 0xd00;
    private static int checks;
    private static void check(boolean ok, String why) { checks++; if (!ok) throw new AssertionError(why); }

    /** Fake DSIStartup: records requests and answers them the way the test scenario says. */
    static final class Dsi implements InvocationHandler {
        final List<String> calls = new ArrayList<String>();
        DomainHandler handler;
        int dropFirst;               /* answer nothing for this many requests (medialauncher reset) */
        int answer = 0x4d00;
        public synchronized Object invoke(Object p, Method m, Object[] a) throws Throwable {
            if (!m.getName().equals("startDomain")) return null;
            calls.add(a[0] + ":" + Integer.toHexString(((Integer) a[1]).intValue()));
            if (dropFirst > 0) { dropFirst--; return null; }
            final int state = answer;
            new Thread() { public void run() { pause(20); update(handler, MEDIA, state); } }.start();
            return null;
        }
        synchronized int count() { return calls.size(); }
    }

    /** What findHandler() walks: framework.getFwServices().getDomainHandler(). */
    public static final class Services {
        final DomainHandler h;
        Services(DomainHandler h) { this.h = h; }
        public DomainHandler getDomainHandler() { return h; }
    }
    public static final class Framework {
        final Services s;
        Framework(DomainHandler h) { s = new Services(h); }
        public Services getFwServices() { return s; }
    }

    static DomainHandler newHandler(Dsi dsi) throws Exception {
        final LogChannel log = new LogChannel() {
            public void log(int a, String b, Object c, Object d, Object e, Object f, long g, long h, long i, int j, Throwable k) { }
            public void log(int a, int b, Object c, Object d, Object e, Object f, long g, long h, long i, int j, Throwable k) { }
        };
        InvocationHandler fw = new InvocationHandler() {
            public Object invoke(Object p, Method m, Object[] a) {
                String n = m.getName();
                if (n.equals("getMonotonicTime")) return new Long(System.currentTimeMillis());
                if (n.equals("getLogChannel")) return log;
                if (n.equals("getErrorMgr")) return Proxy.newProxyInstance(
                    DomainStartRescueTest.class.getClassLoader(), new Class[] { de.audi.atip.error.IErrorManager.class },
                    new InvocationHandler() { public Object invoke(Object q, Method k, Object[] b) { return null; } });
                Class r = m.getReturnType();
                if (r == Boolean.TYPE) return Boolean.FALSE;
                if (r == Integer.TYPE) return new Integer(0);
                if (r == Long.TYPE) return new Long(0);
                return null;
            }
        };
        de.audi.atip.base.IFrameworkAccess access = (de.audi.atip.base.IFrameworkAccess) Proxy.newProxyInstance(
            DomainStartRescueTest.class.getClassLoader(), new Class[] { de.audi.atip.base.IFrameworkAccess.class }, fw);
        DomainHandler h = new DomainHandler(access);
        dsi.handler = h;
        Object proxy = Proxy.newProxyInstance(DomainStartRescueTest.class.getClassLoader(),
            new Class[] { org.dsi.ifc.startup.DSIStartup.class }, dsi);
        Field f = DomainHandler.class.getDeclaredField("dsiProvider"); f.setAccessible(true); f.set(h, proxy);
        update(h, MEDIA, 0x4500);                       /* medialauncher running, before the request */
        return h;
    }

    static void update(DomainHandler h, int id, int state) {
        try {
            Method m = DomainHandler.class.getDeclaredMethod("doUpdateDomainStatus", new Class[] { Integer.TYPE, Integer.TYPE });
            m.setAccessible(true);
            m.invoke(h, new Object[] { new Integer(id), new Integer(state) });
        } catch (Exception e) { throw new RuntimeException(e); }
    }

    static void pause(long ms) { try { Thread.sleep(ms); } catch (InterruptedException e) { } }

    static DomainStartRescue watcher(DomainHandler h, String[] markers) throws Exception {
        DomainStartRescue r = new DomainStartRescue(new Framework(h), markers, 50L);
        Field f = DomainStartRescue.class.getDeclaredField("handler"); f.setAccessible(true); f.set(r, h);
        check(r.resolve(), "stock layout not resolved");
        return r;
    }

    /** The 027 sequence end to end with the real stock wait. */
    static void droppedRequestIsResent() throws Exception {
        final Dsi dsi = new Dsi();
        dsi.dropFirst = 1;
        final DomainHandler h = newHandler(dsi);
        Thread w = new Thread(new DomainStartRescue(new Framework(h), new String[0], 50L));
        w.setDaemon(true); w.start();
        final int[] result = { -1 };
        Thread hmi = new Thread() { public void run() { result[0] = h.doStartDomain(MEDIA, REQ); } };
        long t0 = System.currentTimeMillis();
        hmi.start();
        pause(300);
        update(h, MEDIA, 0x500);                         /* medialauncher's own run-mode reset ... */
        update(h, MEDIA, 0x4500);                        /* ... which drops the request */
        hmi.join(15000);
        long took = System.currentTimeMillis() - t0;
        check(!hmi.isAlive(), "stock doStartDomain still waiting after 15 s");
        check(result[0] == 0x4d00, "domain state 0x" + Integer.toHexString(result[0]));
        check(took < 5000, "took " + took + " ms (stock alone: 20 s)");
        check(dsi.count() == 2 && dsi.calls.get(1).equals("3:d00"), "requests " + dsi.calls);
    }

    /** Requests answered normally, failed domains, the cap and the off marker: no extra traffic. */
    static void leavesOtherCasesAlone() throws Exception {
        Dsi dsi = new Dsi();
        DomainHandler h = newHandler(dsi);
        DomainStartRescue r = watcher(h, new String[0]);
        h.doStartDomainAsync(MEDIA, REQ);                /* answered at once */
        pause(100);
        long now = System.currentTimeMillis();
        r.poll(now + 10000);
        check(dsi.count() == 1, "answered request re-sent: " + dsi.calls);

        dsi = new Dsi(); dsi.dropFirst = 99;            /* never answered: at most MAX_RESENDS */
        h = newHandler(dsi);
        r = watcher(h, new String[0]);
        h.doStartDomainAsync(MEDIA, REQ);
        r.poll(System.currentTimeMillis() + 10000);
        check(dsi.count() == 1, "re-sent without a newer state from the domain: " + dsi.calls);
        update(h, MEDIA, 0x4500);
        now = System.currentTimeMillis();
        for (int i = 0; i < 10; i++) r.poll(now + 5000 + i * 4000L);
        check(dsi.count() == 1 + DomainStartRescue.MAX_RESENDS, "cap: " + dsi.calls);

        dsi = new Dsi(); dsi.dropFirst = 99;            /* failed domain: stock handles it */
        h = newHandler(dsi);
        r = watcher(h, new String[0]);
        h.doStartDomainAsync(MEDIA, REQ);
        update(h, MEDIA, 0x4510);
        r.poll(System.currentTimeMillis() + 10000);
        check(dsi.count() == 1, "failed domain re-sent: " + dsi.calls);

        File off = File.createTempFile("carplay_domain_rescue", ".off");
        try {
            dsi = new Dsi(); dsi.dropFirst = 99;        /* off marker */
            h = newHandler(dsi);
            r = watcher(h, new String[] { off.getPath() });
            h.doStartDomainAsync(MEDIA, REQ);
            update(h, MEDIA, 0x4500);
            r.poll(System.currentTimeMillis() + 10000);
            check(dsi.count() == 1, "re-sent with the off marker: " + dsi.calls);
        } finally {
            off.delete();
        }
    }

    static void timing() {
        /* request at 0, newer state at 2900: settle 1 s, then gaps of 3 s, two at most */
        check(!DomainStartRescue.shouldResend(3000, 0, REQ, 2900, 0x4500, 0, 0), "before settle");
        check(DomainStartRescue.shouldResend(3900, 0, REQ, 2900, 0x4500, 0, 0), "after settle");
        check(!DomainStartRescue.shouldResend(1500, 0, REQ, 100, 0x4500, 0, 0), "request too young");
        check(!DomainStartRescue.shouldResend(5000, 0, REQ, 2900, 0x4500, 1, 3900), "gap");
        check(DomainStartRescue.shouldResend(6900, 0, REQ, 2900, 0x4500, 1, 3900), "second");
        check(!DomainStartRescue.shouldResend(20000, 0, REQ, 2900, 0x4500, 2, 6900), "cap");
        check(!DomainStartRescue.shouldResend(9000, 0, REQ, -1, 0x4500, 0, 0), "no newer state");
        check(!DomainStartRescue.shouldResend(9000, 0, REQ, 2900, 0x4d00, 0, 0), "answered");
    }

    public static void main(String[] args) throws Exception {
        timing();
        leavesOtherCasesAlone();
        droppedRequestIsResent();
        System.out.println("DomainStartRescue: dropped Media request re-sent against stock DomainHandler "
            + "(answered/failed/capped/off left alone), " + checks + " checks PASS");
    }
}
