public class StatusServerScheduler implements Schedulable {

    public void execute(SchedulableContext SC) {
        StatusServerSchedulerHelper.checkServerStatus();
    }
}