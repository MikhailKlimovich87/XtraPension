public with sharing class BP_SFTPZipFileUploaderSchedule implements Schedulable {
    public void execute(SchedulableContext SC) {

        if(!Test.isRunningTest()) { Id batchJobId = Database.executeBatch(new BP_SFTPZipFileEnvelupeBatch(), 1); }
    }
}