public with sharing class RE_SFTPZipFileUploaderSchedule implements Schedulable {
    public void execute(SchedulableContext SC) {
        Id batchJobId = Database.executeBatch(new RE_SFTPZipFileFullFormBatch(), 1); 
    }
}