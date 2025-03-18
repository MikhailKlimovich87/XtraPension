public with sharing class SFTPFileUploaderSchedule implements Schedulable{
    public void execute(SchedulableContext SC) {
        Id batchJobId = Database.executeBatch(new SFTPFileUploaderBatch(), 1);
    }
}