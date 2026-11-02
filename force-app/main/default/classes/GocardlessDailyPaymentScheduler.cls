public class GocardlessDailyPaymentScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new GocardlessPaymentBatch(), 1);
    }
}