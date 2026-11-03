public class HMRCAppealReplyCheckerScheduler implements Schedulable{
    public void execute(SchedulableContext SC) {
        Id batchJobId = Database.executeBatch(new HMRCAppealReplyCheckerBatch(), 1);
    }
}