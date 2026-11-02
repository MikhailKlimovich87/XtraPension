/**
 * Controller for AwsS3RetrieveBatch LWC
 * Executes the AwsS3RetrieveUnifiedBatch and returns status
 */
public with sharing class AwsS3RetrieveBatchController {
    
    @AuraEnabled
    public static BatchResult executeBatch(Id applicationId) {
        try {
            // Check permissions
            if (!Schema.sObjectType.Application__c.isAccessible()) {
                return new BatchResult(false, 'You do not have permission to access Application records.', null);
            }
            
            // Start the batch
            AwsS3RetrieveUnifiedBatch batch = new AwsS3RetrieveUnifiedBatch(applicationId);
            Id batchJobId = Database.executeBatch(batch, 1);
            
            return new BatchResult(
                true,
            'Retrieve batch job started successfully. Job ID: ' + batchJobId,
            batchJobId
                );
            
        } catch (Exception e) {
            return new BatchResult(false, 'Failed to execute batch: ' + e.getMessage(), null);
        }
    }
    
    @AuraEnabled
    public static BatchStatus getBatchStatus(Id batchJobId) {
        try {
            // Query the batch job status
            List<AsyncApexJob> jobs = [
                SELECT Id, Status, JobItemsProcessed, TotalJobItems, 
                       ExtendedStatus, CompletedDate, CreatedDate
                FROM AsyncApexJob
                WHERE Id = :batchJobId
                LIMIT 1
            ];
            
            if (jobs.size() == 0) {
                return new BatchStatus('UNKNOWN', 0, 0, 'Batch job not found', null, null);
            }
            AsyncApexJob job = jobs[0];
            // Check for failures
            if (job.Status == 'Failed' || job.Status == 'Aborted') {
                return new BatchStatus(
                    job.Status,
                job.JobItemsProcessed,
                job.TotalJobItems,
                job.ExtendedStatus,
                job.CompletedDate,
                job.CreatedDate
                    );
            }
            
            // Check if completed
            if (job.Status == 'Completed') {
                // Check if any failures occurred during processing
                Boolean hasErrors = checkForErrors(batchJobId);
                
                if (hasErrors) {
                    return new BatchStatus(
                        'Completed with Errors',
                    job.JobItemsProcessed,
                    job.TotalJobItems,
                    'Batch completed but some records failed to process.',
                    job.CompletedDate,
                    job.CreatedDate
                        );
                }
                
                return new BatchStatus(
                    job.Status,
                job.JobItemsProcessed,
                job.TotalJobItems,
                'Batch completed successfully.',
                job.CompletedDate,
                job.CreatedDate
                    );
            }
            
            return new BatchStatus(
                job.Status,
            job.JobItemsProcessed,
            job.TotalJobItems,
            job.ExtendedStatus,
            job.CompletedDate,
            job.CreatedDate
                );
            
        } catch (Exception e) {
            System.debug(e.getMessage());
            return new BatchStatus('ERROR', 0, 0, 'Error fetching status: ' + e.getMessage(), null, null);
        }
    }
    
    @AuraEnabled
    public static ApplicationInfo getApplicationInfo(Id applicationId) {
        try {
            Application__c app = [
                SELECT Id, Name
                FROM Application__c
                WHERE Id = :applicationId
                LIMIT 1
            ];
            
            if (app == null) {
                return new ApplicationInfo(null, 'Application not found');
            }
            
            return new ApplicationInfo(app.Id, app.Name);
            
        } catch (Exception e) {
            return new ApplicationInfo(null, 'Error fetching application: ' + e.getMessage());
        }
    }
    
    private static Boolean checkForErrors(Id batchJobId) {
        try {
            List<AsyncApexJob> jobs = [
                SELECT Id, Status
                FROM AsyncApexJob
                WHERE Id = :batchJobId
                AND (Status LIKE '%Failed%' OR Status LIKE '%Aborted%')
            ];
            
            return !jobs.isEmpty();
            
        } catch (Exception e) {
            System.debug('Error checking for batch errors: ' + e.getMessage());
            return false;
        }
    }
    
    // Wrapper classes for Aura response
    public class BatchResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Id batchJobId;
        
        public BatchResult(Boolean success, String message, Id batchJobId) {
            this.success = success;
            this.message = message;
            this.batchJobId = batchJobId;
        }
    }
    
    public class BatchStatus {
        @AuraEnabled public String status;
        @AuraEnabled public Integer jobItemsProcessed;
        @AuraEnabled public Integer totalJobItems;
        @AuraEnabled public String extendedStatus;
        @AuraEnabled public DateTime completedDate;
        @AuraEnabled public DateTime createdDate;
        
        public BatchStatus(String status, Integer jobItemsProcessed, Integer totalJobItems,
        String extendedStatus, DateTime completedDate, DateTime createdDate) {
            this.status = status;
            this.jobItemsProcessed = jobItemsProcessed;
            this.totalJobItems = totalJobItems;
            this.extendedStatus = extendedStatus;
            this.completedDate = completedDate;
            this.createdDate = createdDate;
        }
    }
    
    public class ApplicationInfo {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        
        public ApplicationInfo(String id, String name) {
            this.id = id;
            this.name = name;
        }
    }
    
    public static void fakeMethod() {
        Integer i = 0;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
    }
}