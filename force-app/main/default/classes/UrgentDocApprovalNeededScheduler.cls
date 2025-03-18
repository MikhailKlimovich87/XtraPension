public class UrgentDocApprovalNeededScheduler implements Schedulable {

    public void execute(SchedulableContext SC) {
        UrgentDocApprovalNeededHandler.sendUrgentDocApprovalEmail();
    }

}