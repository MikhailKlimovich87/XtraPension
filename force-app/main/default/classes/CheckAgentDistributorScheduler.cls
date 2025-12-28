public class CheckAgentDistributorScheduler implements Schedulable {
    public void execute(SchedulableContext SC) {
        CheckAgentDistributorSchedulerHandler handler = new CheckAgentDistributorSchedulerHandler();
        handler.assignedCheckUser();
    }
}