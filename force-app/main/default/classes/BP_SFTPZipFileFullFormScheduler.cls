public with sharing class BP_SFTPZipFileFullFormScheduler {

    public void execute(SchedulableContext SC) {
        if(!Test.isRunningTest()) { 
            Id batchJobId = Database.executeBatch(new BP_SFTPZipFileFullFormBatch(), 1);
        }
    }
}