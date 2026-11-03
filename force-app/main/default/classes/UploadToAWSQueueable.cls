public with sharing class UploadToAWSQueueable implements Queueable {
    private Set<Id> appIds;
    
    // Constructor for testing
    public UploadToAWSQueueable(Set<Id> appIds) {
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
                    AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(appId);
                    Database.executeBatch(batch, 1);
                }
                counter++;
            }
        }
    }
}