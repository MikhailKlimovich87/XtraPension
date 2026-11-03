/**
 * Utility class for scheduling and managing S3 upload batches
 */
public with sharing class AwsS3BatchScheduler {
    
    /**
     * Schedules a single-record batch job to run immediately
     * @param applicationId - Id of the Application record
     * @return Id - The batch job Id
     */
    public static Id scheduleSingleBatch(Id applicationId) {
        if (applicationId == null) {
            throw new IllegalArgumentException('Application ID cannot be null');
        }
        
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(applicationId);
        return Database.executeBatch(batch, 1); // Batch size of 1
    }
    
    /**
     * Schedules a batch job with custom batch size
     * @param applicationId - Id of the Application record
     * @param batchSize - Number of records per batch (use 1 for single record processing)
     * @return Id - The batch job Id
     */
    public static Id scheduleBatch(Id applicationId, Integer batchSize) {
        if (applicationId == null) {
            throw new IllegalArgumentException('Application ID cannot be null');
        }
        
        if (batchSize == null || batchSize <= 0) {
            batchSize = 1; // Default to 1 for single-record processing
        }
        
        if (batchSize == 1) {
            AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(applicationId);
            return Database.executeBatch(batch, 1);
        } else {
            // For larger batches, use the original batch class
            AwsS3UploadBatch batch = new AwsS3UploadBatch(applicationId);
            return Database.executeBatch(batch, batchSize);
        }
    }
    
    /**
     * Schedules a single-record batch job to run at a specific time
     * @param applicationId - Id of the Application record
     * @param cronExpression - Cron expression for scheduling
     * @return String - The scheduled job Id
     */
    public static String scheduleSingleBatchAtTime(Id applicationId, String cronExpression) {
        if (applicationId == null) {
            throw new IllegalArgumentException('Application ID cannot be null');
        }
        
        if (String.isBlank(cronExpression)) {
            throw new IllegalArgumentException('Cron expression cannot be blank');
        }
        
        // Create a schedulable wrapper for the batch
        AwsS3BatchSchedulable schedulable = new AwsS3BatchSchedulable(applicationId, 1);
        String jobName = 'S3_Single_Upload_App_' + applicationId + '_' + System.now().getTime();
        
        return System.schedule(jobName, cronExpression, schedulable);
    }
    
    /**
     * Schedules a batch job with custom batch size at a specific time
     * @param applicationId - Id of the Application record
     * @param batchSize - Number of records per batch
     * @param cronExpression - Cron expression for scheduling
     * @return String - The scheduled job Id
     */
    public static String scheduleBatchAtTime(Id applicationId, Integer batchSize, String cronExpression) {
        if (applicationId == null) {
            throw new IllegalArgumentException('Application ID cannot be null');
        }
        
        if (String.isBlank(cronExpression)) {
            throw new IllegalArgumentException('Cron expression cannot be blank');
        }
        
        if (batchSize == null || batchSize <= 0) {
            batchSize = 1;
        }
        
        // Create a schedulable wrapper for the batch
        AwsS3BatchSchedulable schedulable = new AwsS3BatchSchedulable(applicationId, batchSize);
        String jobName = 'S3_Batch_Upload_App_' + applicationId + '_' + System.now().getTime();
        
        return System.schedule(jobName, cronExpression, schedulable);
    }
    
    /**
     * Executes single-record batch for multiple applications
     * @param applicationIds - List of Application IDs
     * @return Map<Id, Id> - Map of Application ID to Batch Job ID
     */
    public static Map<Id, Id> scheduleBatchForMultipleApps(List<Id> applicationIds) {
        Map<Id, Id> jobMap = new Map<Id, Id>();
        
        if (applicationIds == null || applicationIds.isEmpty()) {
            return jobMap;
        }
        
        for (Id appId : applicationIds) {
            if (appId != null) {
                try {
                    Id jobId = scheduleSingleBatch(appId);
                    jobMap.put(appId, jobId);
                } catch (Exception ex) {
                    System.debug('Failed to schedule batch for application ' + appId +
                        ': ' + ex.getMessage());
                }
            }
        }
        
        return jobMap;
    }
    
    /**
     * Executes batch for multiple applications with custom batch size
     * @param applicationIds - List of Application IDs
     * @param batchSize - Number of records per batch
     * @return Map<Id, Id> - Map of Application ID to Batch Job ID
     */
    public static Map<Id, Id> scheduleBatchForMultipleApps(List<Id> applicationIds, Integer batchSize) {
        Map<Id, Id> jobMap = new Map<Id, Id>();
        
        if (applicationIds == null || applicationIds.isEmpty()) {
            return jobMap;
        }
        
        if (batchSize == null || batchSize <= 0) {
            batchSize = 1;
        }
        
        for (Id appId : applicationIds) {
            if (appId != null) {
                try {
                    Id jobId = scheduleBatch(appId, batchSize);
                    jobMap.put(appId, jobId);
                } catch (Exception ex) {
                    System.debug('Failed to schedule batch for application ' + appId +
                        ': ' + ex.getMessage());
                }
            }
        }
        
        return jobMap;
    }
    
    /**
     * Checks the status of a batch job
     * @param jobId - The batch job Id
     * @return String - Status of the job
     */
    public static String getBatchStatus(Id jobId) {
        if (jobId == null) {
            return 'Invalid Job ID';
        }
        
        List<AsyncApexJob> jobs = [
            SELECT Id, Status, JobType, TotalJobItems, JobItemsProcessed, 
                   NumberOfErrors, ExtendedStatus, CreatedDate, CompletedDate
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];
        
        if (jobs.isEmpty()) {
            return 'Job not found';
        }
        
        AsyncApexJob job = jobs[0];
        String status = 'Status: ' + job.Status;
        status += ', Processed: ' + job.JobItemsProcessed + '/' + job.TotalJobItems;
        status += ', Errors: ' + job.NumberOfErrors;
        
        if (job.CreatedDate != null) {
            status += ', Started: ' + job.CreatedDate.format();
        }
        if (job.CompletedDate != null) {
            status += ', Completed: ' + job.CompletedDate.format();
        }
        if (job.ExtendedStatus != null) {
            status += ', Details: ' + job.ExtendedStatus;
        }
        
        return status;
    }
    
    /**
     * Stops a running batch job
     * @param jobId - The batch job Id
     * @return Boolean - True if successfully aborted
     */
    public static Boolean abortBatch(Id jobId) {
        if (jobId == null) {
            return false;
        }
        
        try {
            // Check if job exists and is running
            List<AsyncApexJob> jobs = [
                SELECT Id, Status
                FROM AsyncApexJob
                WHERE Id = :jobId AND Status IN ('Queued', 'Processing')
                LIMIT 1
            ];
            
            if (jobs.isEmpty()) {
                return false;
            }
            
            System.abortJob(jobId);
            return true;
            
        } catch (Exception ex) {
            System.debug('Failed to abort job: ' + ex.getMessage());
            return false;
        }
    }
    
    /**
     * Schedulable wrapper class for AwsS3 batch jobs
     * This class implements the Schedulable interface to allow scheduling of batch jobs
     */
    public class AwsS3BatchSchedulable implements Schedulable {
        
        private Id applicationId;
        private Integer batchSize;
        
        /**
         * Constructor
         * @param applicationId - Id of the Application record
         * @param batchSize - Number of records per batch
         */
        public AwsS3BatchSchedulable(Id applicationId, Integer batchSize) {
            this.applicationId = applicationId;
            this.batchSize = batchSize != null && batchSize > 0 ? batchSize : 1;
        }
        
        /**
         * Execute method called by the scheduler
         * @param sc - SchedulableContext
         */
        public void execute(SchedulableContext sc) {
            if (applicationId == null) {
                System.debug('Cannot execute batch: Application ID is null');
                return;
            }
            
            try {
                if (batchSize == 1) {
                    // Use single-record batch
                    AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(applicationId);
                    Database.executeBatch(batch, 1);
                    System.debug('Scheduled single-record batch for application: ' + applicationId);
                } else {
                    // Use standard batch
                    AwsS3UploadBatch batch = new AwsS3UploadBatch(applicationId);
                    Database.executeBatch(batch, batchSize);
                    System.debug('Scheduled batch for application: ' + applicationId +
                        ' with batch size: ' + batchSize);
                }
            } catch (Exception ex) {
                System.debug('Error executing scheduled batch: ' + ex.getMessage());
            }
        }
    }
}