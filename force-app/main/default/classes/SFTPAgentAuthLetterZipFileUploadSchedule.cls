public class SFTPAgentAuthLetterZipFileUploadSchedule implements Schedulable {
    public void execute(SchedulableContext SC) {
        Id batchJobId = Database.executeBatch(new SFTPAgentAuthLetterZipFileUploaderBatch(), 1);
    }
}