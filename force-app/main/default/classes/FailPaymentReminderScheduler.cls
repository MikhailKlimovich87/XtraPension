public class FailPaymentReminderScheduler implements Schedulable {

    public void execute(SchedulableContext SC) {
        Database.executeBatch(new FailPaymentReminderBatch(), 1);
    }
}