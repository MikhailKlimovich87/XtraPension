public class BulkUpdateStripePaymentIntentsScheduler implements Schedulable {

    public void execute(SchedulableContext SC) {
        if (Test.isRunningTest()) {
            return;
        }

        Date yestDate = Date.today().addDays(-1);

        BulkUpdateStripePaymentIntentsBatch batch = new BulkUpdateStripePaymentIntentsBatch(
            DateTime.newInstanceGmt(yestDate.year(), yestDate.month(), yestDate.day(), 0, 0, 0),
            DateTime.newInstanceGmt(yestDate.year(), yestDate.month(), yestDate.day(), 23, 59, 59)
        );
        Database.executeBatch(batch, 1);
    }
}