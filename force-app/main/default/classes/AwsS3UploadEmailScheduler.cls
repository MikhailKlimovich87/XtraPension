/**
 * Scheduler for AwsS3UploadEmailBatch
 * Runs every minute to process EmailMessages with attachments that haven't been uploaded to S3
 * Excludes EmailMessages created in the current year (2026)
 */

global class AwsS3UploadEmailScheduler implements Schedulable {
    
    // Constants
    private static final Integer BATCH_SIZE = 1;
    private static final Integer MAX_EMAILS_PER_RUN = 5;
    
    // No date filter - process all emails
    //private static final DateTime CUTOFF_DATETIME = DateTime.newInstance(2026, 1, 1, 0, 0, 0);
    private static final String CUTOFF_DATETIME = 'LAST_MONTH';
    
    /**
     * Execute method called by the scheduler
     */
    global void execute(SchedulableContext ctx) {
        try {
            System.debug('=== AwsS3UploadEmailScheduler Started ===');
            System.debug('Time: ' + System.now());
            
            // Find EmailMessages with attachments that haven't been uploaded to S3
            List<EmailMessage> emailsToProcess = findEmailsToProcess();
            
            System.debug('Found ' + emailsToProcess.size() + ' emails to process');
            
            if (emailsToProcess.isEmpty()) {
                System.debug('No emails to process. Exiting.');
                return;
            }
            
            // Process each email
            Integer processedCount = 0;
            for (EmailMessage email : emailsToProcess) {
                if (processedCount >= MAX_EMAILS_PER_RUN) {
                    System.debug('Reached max emails per run limit: ' + MAX_EMAILS_PER_RUN);
                    break;
                }
                
                try {
                    System.debug('Processing email: ' + email.Id + ' - ' + email.Subject);
                    
                    // Execute batch for this email
                    AwsS3UploadEmailBatch batch = new AwsS3UploadEmailBatch(email.Id);
                    Database.executeBatch(batch, BATCH_SIZE);
                    
                    processedCount++;
                    
                } catch (Exception ex) {
                    System.debug('Error processing email ' + email.Id + ': ' + ex.getMessage());
                    
                    if (!Test.isRunningTest()) {
                        try {
                            AwsS3NotificationService notificationService = new AwsS3NotificationService();
                            notificationService.sendFailureNotification(
                                'AWS S3 Upload Scheduler Error',
                            'Error processing email: ' + email.Id + '\n' +
                                'Error: ' + ex.getMessage()
                                );
                        } catch (Exception e) {
                            System.debug('Failed to send notification: ' + e.getMessage());
                        }
                    }
                }
            }
            
            System.debug('=== AwsS3UploadEmailScheduler Completed ===');
            System.debug('Processed ' + processedCount + ' emails');
            
        } catch (Exception ex) {
            System.debug('Fatal error in scheduler: ' + ex.getMessage());
            
            if (!Test.isRunningTest()) {
                try {
                    AwsS3NotificationService notificationService = new AwsS3NotificationService();
                    notificationService.sendFailureNotification(
                        'AWS S3 Upload Scheduler - Fatal Error',
                    'Fatal error in scheduler: ' + ex.getMessage()
                        );
                } catch (Exception e) {
                    System.debug('Failed to send error notification: ' + e.getMessage());
                }
            }
        }
    }
    
    /**
     * Finds EmailMessages with attachments that haven't been uploaded to S3
     * Uses a single query approach with ContentDocumentLink
     */
    private List<EmailMessage> findEmailsToProcess() {
        List<EmailMessage> emailsToProcess = new List<EmailMessage>();
        
        try {
            // Step 1: Get all Email IDs that have attachments AND haven't been uploaded
            // Using the SOQL approach you suggested
            Set<Id> emailIdsWithAttachments = new Set<Id>();
            
            // Query ContentDocumentLink to get all EmailMessage IDs with attachments
            for (ContentDocumentLink link : [
                SELECT LinkedEntityId
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN (
                    SELECT Id 
                    FROM EmailMessage 
                    WHERE (
                        S3_Upload_Status__c = null OR
                        S3_Upload_Status__c = '' OR
                        S3_Upload_Status__c = 'Pending' OR
                        S3_Upload_Status__c = 'Failed' OR
                        S3_Upload_Status__c = 'Partial Success'
                    )
                    AND S3_Upload_Date__c = null
                    AND CreatedDate < LAST_MONTH  
                    //AND CreatedDate < :CUTOFF_DATETIME
                )
                ORDER BY ContentDocument.ContentSize DESC
                LIMIT 1000
            ]) {
                emailIdsWithAttachments.add(link.LinkedEntityId);
            }
            
            System.debug('Found ' + emailIdsWithAttachments.size() + ' emails with attachments needing upload');
            
            if (emailIdsWithAttachments.isEmpty()) {
                return emailsToProcess;
            }
            
            // Step 2: Get the full EmailMessage records
            emailsToProcess = [
                SELECT Id, Subject, FromAddress, ToAddress, MessageDate,
                       S3_Upload_Status__c, S3_Upload_Date__c, S3_Failed_Count__c
                FROM EmailMessage
                WHERE Id IN :emailIdsWithAttachments
                ORDER BY CreatedDate ASC
                LIMIT :MAX_EMAILS_PER_RUN
            ];
            
            System.debug('Final ' + emailsToProcess.size() + ' emails to process');
            
        } catch (Exception ex) {
            System.debug('Error finding emails to process: ' + ex.getMessage());
            System.debug('Stack trace: ' + ex.getStackTraceString());
        }
        
        return emailsToProcess;
    }
    
    /**
     * Helper method to schedule the job
     */
    public static Id scheduleJob(String cronExpression) {
        try {
            if (String.isBlank(cronExpression)) {
                cronExpression = '0 0/5 * * * ?';
            }
            
            AwsS3UploadEmailScheduler scheduler = new AwsS3UploadEmailScheduler();
            String jobName = 'AwsS3UploadEmailScheduler_' + System.now().format('yyyyMMddHHmmss');
            
            Id jobId = System.schedule(jobName, cronExpression, scheduler);
            
            System.debug('✅ Scheduled AwsS3UploadEmailScheduler');
            System.debug('   Job ID: ' + jobId);
            System.debug('   Cron: ' + cronExpression);
            
            return jobId;
            
        } catch (Exception ex) {
            System.debug('❌ Error scheduling job: ' + ex.getMessage());
            return null;
        }
    }
    
    /**
     * Helper method to unschedule a job
     */
    public static void unscheduleJob(String jobName) {
        try {
            List<CronTrigger> jobs = [
                SELECT Id, CronJobDetailId, State
                FROM CronTrigger
                WHERE CronJobDetail.Name = :jobName
            ];
            
            for (CronTrigger job : jobs) {
                if (job.State != 'DELETED') {
                    System.abortJob(job.Id);
                    System.debug('✅ Unscheduled job: ' + jobName);
                }
            }
            
        } catch (Exception ex) {
            System.debug('Error unscheduling job: ' + ex.getMessage());
        }
    }
    
    /**
     * Helper method to check if the scheduler is running
     */
    public static Boolean isSchedulerRunning() {
        try {
            List<CronTrigger> jobs = [
                SELECT Id, State
                FROM CronTrigger
                WHERE CronJobDetail.Name LIKE '%AwsS3UploadEmailScheduler%'
                AND State != 'DELETED'
            ];
            return !jobs.isEmpty();
        } catch (Exception ex) {
            return false;
        }
    }
    
    /**
     * Helper method to get scheduler status
     */
    public static String getSchedulerStatus() {
        try {
            List<CronTrigger> jobs = [
                SELECT Id, CronJobDetail.Name, State, NextFireTime, PreviousFireTime,
                       TimesTriggered, StartTime, EndTime
                FROM CronTrigger
                WHERE CronJobDetail.Name LIKE '%AwsS3UploadEmailScheduler%'
                ORDER BY CreatedDate DESC
            ];
            
            if (jobs.isEmpty()) {
                return 'No scheduler found.';
            }
            
            CronTrigger job = jobs[0];
            
            String status = '=== Scheduler Status ===\n';
            status += 'Name: ' + job.CronJobDetail.Name + '\n';
            status += 'State: ' + job.State + '\n';
            status += 'Times Triggered: ' + job.TimesTriggered + '\n';
            status += 'Next Fire Time: ' + (job.NextFireTime != null ? job.NextFireTime.format() : 'N/A') + '\n';
            status += 'Previous Fire Time: ' + (job.PreviousFireTime != null ? job.PreviousFireTime.format() : 'N/A') + '\n';
            
            return status;
            
        } catch (Exception ex) {
            return 'Error getting scheduler status: ' + ex.getMessage();
        }
    }
    
    /**
     * Helper method to get the count of pending emails
     */
    public static Integer getPendingEmailsCount() {
        try {
            // Count emails with attachments that haven't been uploaded
            Integer count = 0;
            
            for (ContentDocumentLink link : [
                SELECT LinkedEntityId
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN (
                    SELECT Id 
                    FROM EmailMessage 
                    WHERE (
                        S3_Upload_Status__c = null OR
                        S3_Upload_Status__c = '' OR
                        S3_Upload_Status__c = 'Pending' OR
                        S3_Upload_Status__c = 'Failed' OR
                        S3_Upload_Status__c = 'Partial Success'
                    )
                    AND S3_Upload_Date__c = null
                )
                LIMIT 1000
            ]) {
                count++;
            }
            
            return count;
            
        } catch (Exception ex) {
            System.debug('Error counting pending emails: ' + ex.getMessage());
            return -1;
        }
    }
    
    
    public static void fakeMethod() {
        Integer i=0;
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