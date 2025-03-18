public with sharing class SFTPZipFileUploaderSchedule implements Schedulable {
    public void execute(SchedulableContext SC) {
        Id batchJobId = Database.executeBatch(new SFTPZipFileUploaderBatch(), 1);
    }
}