public class CreditNoteGeneratorScheduler implements Schedulable {

    public void execute(SchedulableContext SC) {
        Id batchJobId = Database.executeBatch(new CreditNoteGeneratorBatch(), 1);
    }
}