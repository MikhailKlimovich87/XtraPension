public class AwsS3UploadSingleBatchScheduler implements Schedulable {
    
    public void execute(SchedulableContext SC) {
        List<Application__c> annualServiceApps = [
            SELECT Id
            FROM Application__c
            WHERE Status__c = 'Annual Service' 
                AND Send_Files_To_AWS_S3__c = false
            LIMIT 5
        ];
        if (annualServiceApps.size() > 0) {
            for (Integer i = 0; i < annualServiceApps.size(); i++) {
                AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(annualServiceApps[i].Id);
                Id batchJobId = Database.executeBatch(batch, 1);
            }
        }
    }
}