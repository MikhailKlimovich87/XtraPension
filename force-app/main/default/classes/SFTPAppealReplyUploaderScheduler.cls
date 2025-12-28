public class SFTPAppealReplyUploaderScheduler implements Schedulable {
    public void execute(SchedulableContext SC) {
        Id batchJobId = Database.executeBatch(new SFTPAppealReplyUploaderBatch(), 1);
    }
}