public class RE_ReapplyCreatorScheduler implements Schedulable {

    public void execute(SchedulableContext SC) {
        Database.executeBatch(new RE_ReapplyCreatorBatch(), 1);
    }
}