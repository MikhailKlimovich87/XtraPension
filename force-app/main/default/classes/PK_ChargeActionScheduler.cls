public class PK_ChargeActionScheduler implements Schedulable {

    public void execute(SchedulableContext SC) {
        Id batchJobId = Database.executeBatch(new PK_ChargeActionBatch(), 1);
    }
}