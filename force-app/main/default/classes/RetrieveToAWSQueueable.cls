public with sharing class RetrieveToAWSQueueable implements Queueable {
    private Set<Id> appIds;
    
    public RetrieveToAWSQueueable(Set<Id> appIds) {
        this.appIds = appIds;
    }
    
    public void execute(QueueableContext context) {
        Integer counter = 0;
        for (Id appId : appIds) {
            if (counter < 5) {
                if (Test.isRunningTest()) {
                    // Test mode - don't execute batch
                    System.debug('Test mode: Would process App ID: ' + appId);
                } else {
                    AwsS3RetrieveFilesBatch batch = new AwsS3RetrieveFilesBatch(appId);
                    Database.executeBatch(batch, 1);
                }
                counter++;
            }
        }
    }
}