package de.audi.app.terminalmode;

import com.luka.carplay.aa.AaClusterTheme;
import de.audi.app.terminalmode.diagnosis.IDiagnosisCommandProvider;
import de.audi.app.terminalmode.dsi.DefaultDSIGeneralVehicleStatesListener;
import de.audi.app.terminalmode.smartphone.IDSISmartphoneManager;
import de.audi.app.terminalmode.statemachine.commands.AbstractDSICommand;
import de.audi.atip.log.LogChannel;
import de.audi.mib.jdsi.DSIActivator;
import de.audi.mib.jdsi.IDSIClient;
import org.dsi.ifc.base.DSIBase;
import org.dsi.ifc.generalvehiclestates.DSIGeneralVehicleStates;
import org.dsi.ifc.generalvehiclestates.DSIGeneralVehicleStatesListener;

/**
 * Stock NightDayModeHandler (rebuilt from bytecode, same members and inner-class order) with
 * one addition: every MMI day/night design update is also published for the Android Auto
 * cluster hook (AaClusterTheme), which uses it only when the opt-in cluster day/night theme
 * is on.  The phone's own night mode (requestNightMode) is unchanged.
 */
public class NightDayModeHandler implements INightDayModeHandler, ITerminalModeComponent {
    protected static final String LOGCLASS = "NightDayModeHandler";
    private final DSIActivator dsiGeneralVehicleStatesActivator;
    private final IContext context;
    private final LogChannel logger;
    private volatile boolean requestedDisplayNightDesign;

    public NightDayModeHandler(IContext icontext, LogChannel logchannel) {
        this.context = icontext;
        this.logger = logchannel;
        this.dsiGeneralVehicleStatesActivator = new DSIActivator(
            icontext.getFramework(),
            DSIGeneralVehicleStates.class.getName(),
            DSIGeneralVehicleStatesListener.class.getName(),
            new Integer(0),
            new DefaultDSIGeneralVehicleStatesListener() {
                public void updateDisplayDayNightDesign(boolean flag, int i) {
                    NightDayModeHandler.this.logger.log(1000000, "<- [%1.updateDisplayDayNightDesign] %2",
                        LOGCLASS, flag ? "night" : "day");
                    NightDayModeHandler.this.updateRequestedNightDesign(flag);
                }
            },
            new IDSIClient() {
                public void setDSI(DSIBase dsibase) {
                }

                public int[] getAutoNotifications() {
                    return new int[] {16};
                }
            });
        icontext.getDiagnosisManager().addCommandProvider(-1, new IDiagnosisCommandProvider() {
            public String[] getDiagKeys() {
                return new String[] {"requestNightMode", "requestDayMode"};
            }

            public void executeDiagCommand(String s, String[] as) {
                NightDayModeHandler.this.updateRequestedNightDesign("requestNightMode".equals(s));
            }
        });
    }

    public void init() {
        this.dsiGeneralVehicleStatesActivator.start(this.context.getFramework().getBundleCxt());
    }

    public void deinit() {
    }

    public boolean getRequestedNightMode() {
        return this.requestedDisplayNightDesign;
    }

    private void updateRequestedNightDesign(boolean flag) {
        this.requestedDisplayNightDesign = flag;
        AaClusterTheme.publish(flag);
        this.context.getCommandListHelper().create()
            .addSingle(new NightModeRequest(this.context, this.requestedDisplayNightDesign))
            .execute("NightDayModeHandler.executeCommand()");
    }

    static class NightModeRequest extends AbstractDSICommand {
        private static final String LOGCLASS = "NightModeRequest";
        private final boolean useNightMode;
        final IDSISmartphoneManager smartphoneDSIManager;

        public NightModeRequest(IContext icontext, boolean flag) {
            super(icontext.getLogger().main(), LOGCLASS, icontext, icontext.getSmartphoneDSIManager());
            this.useNightMode = flag;
            this.smartphoneDSIManager = icontext.getSmartphoneDSIManager();
        }

        public void execute() {
            this.logger.log(1000000, "[%1.execute] %2", LOGCLASS, this.useNightMode ? "night" : "day");
            this.smartphoneDSIManager.requestNightMode(this.useNightMode);
            this.getCommandList().commandFinished();
        }
    }
}
