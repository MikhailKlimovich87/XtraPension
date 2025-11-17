public class ApplicationPaymentReminderScheduler implements Schedulable {

    public void execute(SchedulableContext SC) {
        ApplicationPaymentReminderSchedulerBatch schedulerBatch = new ApplicationPaymentReminderSchedulerBatch();
        Database.executeBatch(schedulerBatch, 1);
    }
}