public class DailyPaymentScheduler implements Schedulable {
    public void execute(SchedulableContext SC) {
        Id batchJobId = Database.executeBatch(new DailyPaymentSchedulerBatch(), 1);
    }
}