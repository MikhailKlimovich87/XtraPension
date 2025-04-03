public class DWPOldApplicationScheduler implements Schedulable{
    public void execute(SchedulableContext SC) {
      DWPOldApplicationSchedulerHandler handler = new DWPOldApplicationSchedulerHandler();
      handler.changeAppsStatusForOldApps();
   }
}