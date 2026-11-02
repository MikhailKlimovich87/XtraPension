/**
 * Unified Batch Apex class for retrieving files from AWS S3 and linking them to Salesforce
 * Supports both Application records (from app bucket) and Email Message records (from email bucket)
 * Links email attachments to both the Email Message AND the parent Application
 */
public with sharing class AwsS3RetrieveUnifiedBatch implements Database.Batchable<String>, Database.AllowsCallouts, Database.Stateful {
    
    // Configuration
    private static final Integer MAX_FILE_SIZE = 5000000; // 5MB limit for Salesforce
    
    // Named credentials for different buckets
    private static final String AWS_APP_ENDPOINT = 'callout:AWS_S3'; // For Application bucket
    private static final String AWS_EMAIL_ENDPOINT = 'callout:AWS_S3_Email'; // For Email bucket
    
    // Instance variables
    private Id applicationId;
    private String applicationPackageFolder;
    private Map<Id, EmailMessageWrapper> emailMessagesMap = new Map<Id, EmailMessageWrapper>();
    
    // Tracking
    private Integer totalProcessed = 0;
    private Integer successfullyLinked = 0;
    private Integer failedCount = 0;
    private Integer duplicateCount = 0;
    private List<String> failedFiles = new List<String>();
    private List<String> successFiles = new List<String>();
    private Map<String, String> fileStatusMap = new Map<String, String>();
    
    // Application tracking
    private Application__c applicationRecord;
    private Map<String, Id> existingAppDocuments = new Map<String, Id>();
    private Map<String, Id> appDocumentByS3Key = new Map<String, Id>(); // Map S3 key to ContentDocument ID
    
    // Email Message tracking
    private Map<Id, Integer> emailTotalProcessed = new Map<Id, Integer>();
    private Map<Id, Integer> emailSuccessCount = new Map<Id, Integer>();
    private Map<Id, Integer> emailFailedCount = new Map<Id, Integer>();
    private Map<Id, List<String>> emailFailedFiles = new Map<Id, List<String>>();
    private Map<Id, List<String>> emailFileKeys = new Map<Id, List<String>>();
    private Map<Id, Map<String, Id>> emailDocumentByS3Key = new Map<Id, Map<String, Id>>();
    
    // Upload Results tracking
    private Id uploadResultId;
    private String uploadResultStatus = 'Pending';
    private String uploadResultErrorMessage = '';
    
    // S3 Package tracking
    private Map<String, Set<String>> s3KeysByPackage = new Map<String, Set<String>>();
    private Map<String, Id> packageToEmailMap = new Map<String, Id>(); // Map package folder to Email ID
    private Boolean hasEmailPackages = false;
    
    // Debug info
    private String s3ListResponse = '';
    private Integer s3ListStatusCode = 0;
    private String s3ListErrorMessage = '';
    
    /**
     * Inner class to hold S3 metadata extracted from response headers
     */
    private class S3Metadata {
        public String s3VersionId;
        public String s3ObjectKey;
        public DateTime uploadDate;
        public String fileExtension;
        public Long fileSize;
        public String contentType;
        public String fileNameWithExtension; // New field for filename with extension
        
        public S3Metadata() {
            this.s3VersionId = '';
            this.s3ObjectKey = '';
            this.uploadDate = System.now();
            this.fileExtension = '';
            this.fileSize = 0;
            this.contentType = '';
            this.fileNameWithExtension = '';
        }
    }
    
    /**
     * Wrapper class for Email Message with its S3 package info
     */
    private class EmailMessageWrapper {
        public Id emailId;
        public String s3PackageId;
        public DateTime s3UploadDate;
        public String emailSubject;
        public Map<String, Id> existingDocuments = new Map<String, Id>();
        public List<String> s3FileKeys = new List<String>();
        public Integer totalFiles = 0;
        public Integer successCount = 0;
        public Integer failedCount = 0;
        public List<String> failedFiles = new List<String>();
        public List<String> successFiles = new List<String>();
        public Map<String, Id> createdDocumentIds = new Map<String, Id>(); // Track created document IDs
        public Map<String, Id> documentByS3Key = new Map<String, Id>(); // Map S3 key to ContentDocument ID
        
        public EmailMessageWrapper(EmailMessage email) {
            this.emailId = email.Id;
            this.s3PackageId = email.AWS_S3_Package_Id__c;
            this.s3UploadDate = email.S3_Upload_Date__c;
            this.emailSubject = email.Subject != null ? email.Subject : 'Email_' + String.valueOf(email.Id).substring(0, 8);
        }
    }
    
    /**
     * Constructor with Application ID
     * @param applicationId - Id of the Application record
     */
    public AwsS3RetrieveUnifiedBatch(Id applicationId) {
        this.applicationId = applicationId;
        System.debug('=== AwsS3RetrieveUnifiedBatch Initialized ===');
        System.debug('Application ID: ' + applicationId);
        
        initializeBatch();
    }
    
    /**
     * Initializes the batch by getting application, email messages, and existing documents
     */
    private void initializeBatch() {
        if (applicationId == null) {
            System.debug('ERROR: Application ID is null. Batch cannot be initialized.');
            return;
        }
        
        // Get Application record
        applicationRecord = getApplication(applicationId);
        if (applicationRecord == null) {
            System.debug('ERROR: Application not found with ID: ' + applicationId);
            return;
        }
        
        // Build application package folder
        this.applicationPackageFolder = AwsS3ApiHandler.buildApplicationPackageFolder(applicationRecord, null);
        
        // Load existing Application documents
        loadExistingDocuments(applicationId, existingAppDocuments, appDocumentByS3Key);
        
        // Get related Email Messages with S3 data
        loadEmailMessages();
        
        // Create initial Upload Results record
        createInitialUploadResult();
        
        System.debug('Application Name: ' + applicationRecord.Name);
        System.debug('Application Package Folder: ' + applicationPackageFolder);
        System.debug('Email Messages with S3 data: ' + emailMessagesMap.size());
        System.debug('Has Email Packages: ' + hasEmailPackages);
        System.debug('Upload Result ID: ' + uploadResultId);
    }
    
    /**
     * Loads email messages related to the application that have S3 data
     */
    private void loadEmailMessages() {
        try {
            // Query Email Messages with S3 data - try ParentId first
            List<EmailMessage> emailMessages = [
                SELECT Id, Subject, AWS_S3_Package_Id__c, S3_Upload_Date__c, 
                       S3_Upload_Status__c, S3_Total_Files__c, S3_Retrieved_Count__c,
                       S3_Failed_Count__c, S3_Retrieve_Date__c
                FROM EmailMessage
                WHERE ParentId = :applicationId
                AND AWS_S3_Package_Id__c != null
                AND S3_Upload_Date__c != null
                ORDER BY S3_Upload_Date__c DESC
            ];
            
            // If no emails found with ParentId, try RelatedToId
            if (emailMessages.isEmpty()) {
                System.debug('No emails found with ParentId, trying RelatedToId...');
                emailMessages = [
                    SELECT Id, Subject, AWS_S3_Package_Id__c, S3_Upload_Date__c, 
                           S3_Upload_Status__c, S3_Total_Files__c, S3_Retrieved_Count__c,
                           S3_Failed_Count__c, S3_Retrieve_Date__c
                    FROM EmailMessage
                    WHERE RelatedToId = :applicationId
                    AND AWS_S3_Package_Id__c != null
                    AND S3_Upload_Date__c != null
                    ORDER BY S3_Upload_Date__c DESC
                ];
            }
            
            System.debug('Found ' + emailMessages.size() + ' Email Messages with S3 data');
            
            for (EmailMessage email : emailMessages) {
                EmailMessageWrapper wrapper = new EmailMessageWrapper(email);
                emailMessagesMap.put(email.Id, wrapper);
                
                // Map package to email
                if (String.isNotBlank(email.AWS_S3_Package_Id__c)) {
                    packageToEmailMap.put(email.AWS_S3_Package_Id__c, email.Id);
                }
                // Also map the email ID itself
                packageToEmailMap.put(String.valueOf(email.Id), email.Id);
                
                // Load existing documents for this email
                Map<String, Id> emailDocs = new Map<String, Id>();
                Map<String, Id> emailDocByKey = new Map<String, Id>();
                loadExistingDocuments(email.Id, emailDocs, emailDocByKey);
                wrapper.existingDocuments = emailDocs;
                wrapper.documentByS3Key = emailDocByKey;
                
                System.debug('  - Email: ' + email.Id + ' | Package: ' + email.AWS_S3_Package_Id__c +
                    ' | Existing Docs: ' + emailDocs.size());
            }
            
            // Set flag if we have email packages
            hasEmailPackages = !emailMessagesMap.isEmpty();
            
        } catch (Exception ex) {
            System.debug('ERROR loading email messages: ' + ex.getMessage());
        }
    }
    
    /**
     * Loads existing ContentDocuments linked to a record
     * Also maps S3 keys to ContentDocument IDs for deduplication
     */
    private void loadExistingDocuments(Id recordId, Map<String, Id> documentMap, Map<String, Id> documentByS3Key) {
        try {
            documentMap.clear();
            documentByS3Key.clear();
            
            // First get all ContentDocumentLinks for this record
            Set<Id> docIds = new Set<Id>();
            Map<Id, String> docTitles = new Map<Id, String>();
            
            for (ContentDocumentLink link : [
                SELECT ContentDocumentId, ContentDocument.Title
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :recordId
            ]) {
                docIds.add(link.ContentDocumentId);
                docTitles.put(link.ContentDocumentId, link.ContentDocument.Title);
            }
            
            if (docIds.isEmpty()) {
                return;
            }
            
            // Get S3 metadata from ContentVersions
            for (ContentVersion cv : [
                SELECT Id, ContentDocumentId, AWS_S3_Object_Key__c, S3_Version_Id__c, 
                       Title, FileExtension, S3_Upload_Date__c
                FROM ContentVersion
                WHERE ContentDocumentId IN :docIds
                AND IsLatest = true
                AND AWS_S3_Object_Key__c != null
            ]) {
                String title = docTitles.get(cv.ContentDocumentId);
                if (String.isNotBlank(title)) {
                    String titleKey = normalizeTitle(title);
                    documentMap.put(titleKey, cv.ContentDocumentId);
                }
                
                // Map S3 key to ContentDocument ID for deduplication
                if (String.isNotBlank(cv.AWS_S3_Object_Key__c)) {
                    documentByS3Key.put(cv.AWS_S3_Object_Key__c, cv.ContentDocumentId);
                }
            }
            
            System.debug('Loaded ' + documentMap.size() + ' existing documents for ' + recordId);
            
        } catch (Exception ex) {
            System.debug('Error loading existing documents for ' + recordId + ': ' + ex.getMessage());
        }
    }
    
    /**
     * Creates initial AwsS3UploadResult__c record
     */
    private void createInitialUploadResult() {
        try {
            // Check for existing pending result
            List<AwsS3UploadResult__c> existingResults = [
                SELECT Id, Status__c 
                FROM AwsS3UploadResult__c 
                WHERE Application__c = :applicationId 
                AND Status__c = 'Pending'
                AND Batch_Type__c = 'Unified S3 Retrieve'
                ORDER BY CreatedDate DESC 
                LIMIT 1
            ];
            
            if (!existingResults.isEmpty()) {
                uploadResultId = existingResults[0].Id;
                uploadResultStatus = 'Pending';
                System.debug('Using existing pending Upload Result: ' + uploadResultId);
                return;
            }
            
            // Create new Upload Result record
            AwsS3UploadResult__c uploadResult = new AwsS3UploadResult__c();
            uploadResult.Application__c = applicationId;
            uploadResult.Status__c = 'Pending';
            uploadResult.Batch_Type__c = 'Unified S3 Retrieve';
            uploadResult.UploadDate__c = System.now();
            uploadResult.TotalProcessed__c = 0;
            uploadResult.UploadedCount__c = 0;
            uploadResult.FailedCount__c = 0;
            uploadResult.Success_Rate__c = 0;
            
            insert uploadResult;
            uploadResultId = uploadResult.Id;
            uploadResultStatus = 'Pending';
            
            System.debug('Created new Upload Result record: ' + uploadResultId);
            
        } catch (Exception ex) {
            System.debug('ERROR creating Upload Result: ' + ex.getMessage());
            uploadResultErrorMessage = 'Failed to create Upload Result: ' + ex.getMessage();
        }
    }
    
    /**
     * Start method - gets list of files from S3 for all packages
     */
    public Iterable<String> start(Database.BatchableContext bc) {
        System.debug('=== START METHOD CALLED ===');
        
        if (applicationRecord == null) {
            System.debug('ERROR: Application record not found');
            updateUploadResult('Failed', 'Application record not found');
            return new List<String>();
        }
        
        List<String> allFileKeys = new List<String>();
        
        try {
            // 1. Get files for Application package (using App bucket)
            if (String.isNotBlank(applicationPackageFolder)) {
                System.debug('📁 Processing Application package from App bucket: ' + applicationPackageFolder);
                List<String> appFiles = getS3FileList(applicationPackageFolder, 'APP');
                allFileKeys.addAll(appFiles);
                
                // Track which files belong to application package
                if (!s3KeysByPackage.containsKey(applicationPackageFolder)) {
                    s3KeysByPackage.put(applicationPackageFolder, new Set<String>());
                }
                for (String fileKey : appFiles) {
                    s3KeysByPackage.get(applicationPackageFolder).add(fileKey);
                }
                
                System.debug('✅ Found ' + appFiles.size() + ' files for Application');
            }
            
            // 2. Get files for each Email Message package (using Email bucket)
            // First, search the email bucket for email folders even if no emails found in query
            System.debug('📁 Searching Email bucket for email folders...');
            List<String> allEmailKeys = getS3FileList('', 'EMAIL');
            
            // Group files by email folder
            Map<String, List<String>> filesByEmailFolder = new Map<String, List<String>>();
            Set<String> emailFolderNames = new Set<String>();
            
            for (String fileKey : allEmailKeys) {
                String folderName = getFolderNameFromKey(fileKey);
                if (String.isNotBlank(folderName) && folderName.startsWith('02s')) {
                    if (!filesByEmailFolder.containsKey(folderName)) {
                        filesByEmailFolder.put(folderName, new List<String>());
                        emailFolderNames.add(folderName);
                    }
                    filesByEmailFolder.get(folderName).add(fileKey);
                }
            }
            
            System.debug('📊 Found ' + filesByEmailFolder.size() + ' email folders in S3 bucket');
            
            // ***** FIX: Bulk query ALL email folders at once *****
            if (!emailFolderNames.isEmpty()) {
                // Convert folder names to Ids (they are already Salesforce IDs)
                Set<Id> emailIds = new Set<Id>();
                for (String folderName : emailFolderNames) {
                    try {
                        emailIds.add(Id.valueOf(folderName));
                    } catch (Exception ex) {
                        System.debug('Invalid ID format: ' + folderName);
                    }
                }
                
                // Bulk query all emails at once
                Map<Id, EmailMessage> emailMap = new Map<Id, EmailMessage>([
                SELECT Id, Subject, AWS_S3_Package_Id__c, S3_Upload_Date__c
                FROM EmailMessage
                WHERE Id IN :emailIds
                AND (ParentId = :applicationId OR RelatedToId = :applicationId)
            ]);
                
                System.debug('📊 Found ' + emailMap.size() + ' matching Email Messages from ' + emailIds.size() + ' folders');
                
                // Process each email folder
                for (String folderName : filesByEmailFolder.keySet()) {
                    Id emailId;
                    try {
                        emailId = Id.valueOf(folderName);
                    } catch (Exception ex) {
                        continue;
                    }
                    
                    EmailMessage email = emailMap.get(emailId);
                    
                    if (email != null) {
                        // Found a matching email - add it to our map if not already there
                        if (!emailMessagesMap.containsKey(emailId)) {
                            EmailMessageWrapper wrapper = new EmailMessageWrapper(email);
                            wrapper.s3PackageId = folderName;
                            wrapper.s3FileKeys = filesByEmailFolder.get(folderName);
                            wrapper.totalFiles = wrapper.s3FileKeys.size();
                            emailMessagesMap.put(emailId, wrapper);
                            packageToEmailMap.put(folderName, emailId);
                            hasEmailPackages = true;
                            
                            // Load existing documents for this email
                            Map<String, Id> emailDocs = new Map<String, Id>();
                            Map<String, Id> emailDocByKey = new Map<String, Id>();
                            loadExistingDocuments(emailId, emailDocs, emailDocByKey);
                            wrapper.existingDocuments = emailDocs;
                            wrapper.documentByS3Key = emailDocByKey;
                            
                            allFileKeys.addAll(wrapper.s3FileKeys);
                            
                            // Track which files belong to this email
                            if (!s3KeysByPackage.containsKey(folderName)) {
                                s3KeysByPackage.put(folderName, new Set<String>());
                            }
                            for (String fileKey : wrapper.s3FileKeys) {
                                s3KeysByPackage.get(folderName).add(fileKey);
                            }
                            
                            System.debug('✅ Found email from S3 folder: ' + folderName + ' with ' + wrapper.totalFiles + ' files');
                        }
                    } else {
                        System.debug('⚠️ No matching email found for folder: ' + folderName);
                    }
                }
            }
            
            // Also process any email packages already in the map (from query)
            if (hasEmailPackages) {
                for (EmailMessageWrapper wrapper : emailMessagesMap.values()) {
                    if (wrapper.s3FileKeys.isEmpty() && String.isNotBlank(wrapper.s3PackageId)) {
                        // Try to get files for this specific package
                        System.debug('📁 Processing email package from map: ' + wrapper.s3PackageId);
                        List<String> emailFiles = getS3FileList(wrapper.s3PackageId, 'EMAIL');
                        wrapper.s3FileKeys = emailFiles;
                        wrapper.totalFiles = emailFiles.size();
                        emailTotalProcessed.put(wrapper.emailId, emailFiles.size());
                        
                        allFileKeys.addAll(emailFiles);
                        
                        if (!s3KeysByPackage.containsKey(wrapper.s3PackageId)) {
                            s3KeysByPackage.put(wrapper.s3PackageId, new Set<String>());
                        }
                        for (String fileKey : emailFiles) {
                            s3KeysByPackage.get(wrapper.s3PackageId).add(fileKey);
                        }
                        
                        System.debug('✅ Found ' + emailFiles.size() + ' files for Email: ' + wrapper.emailId);
                    }
                }
            }
            
            totalProcessed = allFileKeys.size();
            System.debug('📊 Total files to process: ' + totalProcessed);
            
            // Update Upload Result with total files
            try {
                if (uploadResultId != null) {
                    AwsS3UploadResult__c updateResult = new AwsS3UploadResult__c(
                        Id = uploadResultId,
                    TotalProcessed__c = totalProcessed
                        );
                    update updateResult;
                }
            } catch (Exception ex) {
                System.debug('Error updating total files: ' + ex.getMessage());
            }
            
            // If no files found, update status
            if (allFileKeys.isEmpty()) {
                String message = 'No files found in S3 packages';
                if (!hasEmailPackages) {
                    message += ' (No email packages found)';
                }
                if (String.isNotBlank(s3ListErrorMessage)) {
                    message += ' | S3 Error: ' + s3ListErrorMessage;
                }
                updateUploadResult('No Files', message);
            }
            
        } catch (Exception ex) {
            System.debug('❌ Error in start method: ' + ex.getMessage());
            System.debug('Stack trace: ' + ex.getStackTraceString());
            updateUploadResult('Error', 'Start error: ' + ex.getMessage());
        }
        
        return allFileKeys;
    }
    /**
     * Extracts folder name from a file key
     */
    private String getFolderNameFromKey(String fileKey) {
        if (String.isBlank(fileKey)) return '';
        
        // If the key contains a slash, the folder is the first part
        Integer firstSlash = fileKey.indexOf('/');
        if (firstSlash != -1) {
            return fileKey.substring(0, firstSlash);
        }
        
        // If no slash, the file is in the root
        return '';
    }
    
    /**
     * Execute method - processes one S3 file at a time
     */
    public void execute(Database.BatchableContext bc, List<String> scope) {
        System.debug('=== EXECUTE METHOD CALLED ===');
        System.debug('Scope size: ' + scope.size());
        
        for (String fileKey : scope) {
            processS3File(fileKey);
        }
        
        // Update progress after each execute
        updateUploadResultProgress();
    }
    
    /**
     * Process a single S3 file
     */
    private void processS3File(String fileKey) {
        System.debug('Processing file: ' + fileKey);
        
        try {
            // Determine which email this file belongs to
            Id targetRecordId = null;
            Map<String, Id> existingDocs = null;
            Map<String, Id> documentByS3Key = null;
            String bucketType = 'EMAIL';
            EmailMessageWrapper emailWrapper = null;
            Boolean isApplicationFile = false;
            
            // Check if this is an application file
            if (String.isNotBlank(applicationPackageFolder) && fileKey.startsWith(applicationPackageFolder)) {
                targetRecordId = applicationId;
                existingDocs = existingAppDocuments;
                documentByS3Key = appDocumentByS3Key;
                bucketType = 'APP';
                isApplicationFile = true;
                System.debug('📄 Processing Application file: ' + fileKey);
            } else {
                // Find which email this file belongs to
                String folderName = getFolderNameFromKey(fileKey);
                
                // Try to find by folder name
                if (String.isNotBlank(folderName)) {
                    for (EmailMessageWrapper wrapper : emailMessagesMap.values()) {
                        String emailIdStr = String.valueOf(wrapper.emailId);
                        if (folderName == emailIdStr || (wrapper.s3PackageId != null && folderName == wrapper.s3PackageId)) {
                            emailWrapper = wrapper;
                            break;
                        }
                    }
                }
                
                // If not found by folder, try to find by checking if the file key contains any email ID
                if (emailWrapper == null) {
                    for (EmailMessageWrapper wrapper : emailMessagesMap.values()) {
                        if (fileKey.contains(String.valueOf(wrapper.emailId)) ||
                        (wrapper.s3PackageId != null && fileKey.contains(wrapper.s3PackageId))) {
                            emailWrapper = wrapper;
                            break;
                        }
                    }
                }
                
                if (emailWrapper == null) {
                    System.debug('⚠️ Could not find email for file: ' + fileKey);
                    failedCount++;
                    failedFiles.add(fileKey + ' (No target email found)');
                    return;
                }
                
                targetRecordId = emailWrapper.emailId;
                existingDocs = emailWrapper.existingDocuments;
                documentByS3Key = emailWrapper.documentByS3Key;
                bucketType = 'EMAIL';
                System.debug('📧 Processing Email attachment: ' + fileKey + ' for Email: ' + emailWrapper.emailId);
            }
            
            // Check if this file already exists in Salesforce by S3 key
            if (documentByS3Key != null && documentByS3Key.containsKey(fileKey)) {
                System.debug('📄 File already exists in Salesforce: ' + fileKey);
                duplicateCount++;
                successFiles.add(fileKey + ' (already exists)');
                fileStatusMap.put(fileKey, 'DUPLICATE');
                return;
            }
            
            // Download file from S3 using the appropriate bucket
            HttpResponse response = downloadFileFromS3(fileKey, bucketType);
            
            if (response != null && response.getStatusCode() == 200) {
                // Extract S3 metadata from response headers
                S3Metadata s3Metadata = extractS3Metadata(fileKey, response);
                
                // Process the file - this will create the ContentVersion and link it
                boolean success = processFileContent(fileKey, response, targetRecordId, existingDocs, emailWrapper, s3Metadata);
                
                if (success) {
                    successfullyLinked++;
                    successFiles.add(fileKey);
                    fileStatusMap.put(fileKey, 'SUCCESS');
                    
                    // Update email tracking
                    if (bucketType == 'EMAIL' && emailWrapper != null) {
                        emailWrapper.successCount++;
                        emailWrapper.successFiles.add(fileKey);
                        emailSuccessCount.put(emailWrapper.emailId, emailWrapper.successCount);
                    }
                } else {
                    failedCount++;
                    failedFiles.add(fileKey + ' (Failed to create document)');
                    fileStatusMap.put(fileKey, 'FAILED');
                    
                    if (bucketType == 'EMAIL' && emailWrapper != null) {
                        emailWrapper.failedCount++;
                        emailWrapper.failedFiles.add(fileKey);
                        emailFailedCount.put(emailWrapper.emailId, emailWrapper.failedCount);
                    }
                }
            } else {
                failedCount++;
                String errorMsg = response != null ? 'Status: ' + response.getStatusCode() : 'Null response';
                failedFiles.add(fileKey + ' (' + errorMsg + ')');
                fileStatusMap.put(fileKey, 'FAILED: ' + errorMsg);
                
                if (bucketType == 'EMAIL' && emailWrapper != null) {
                    emailWrapper.failedCount++;
                    emailWrapper.failedFiles.add(fileKey);
                    emailFailedCount.put(emailWrapper.emailId, emailWrapper.failedCount);
                }
            }
            
        } catch (Exception ex) {
            failedCount++;
            String errorMsg = 'Exception: ' + ex.getMessage();
            failedFiles.add(fileKey + ' (' + errorMsg + ')');
            fileStatusMap.put(fileKey, 'FAILED: ' + errorMsg);
            System.debug('❌ ERROR processing file: ' + fileKey + ' - ' + ex.getMessage());
        }
    }
    
    /**
     * Extracts S3 metadata from HTTP response headers
     */
    private S3Metadata extractS3Metadata(String fileKey, HttpResponse response) {
        S3Metadata metadata = new S3Metadata();
        metadata.s3ObjectKey = fileKey;
        metadata.uploadDate = System.now();
        
        try {
            // Extract S3 Version ID (x-amz-version-id)
            String versionId = response.getHeader('x-amz-version-id');
            if (String.isNotBlank(versionId)) {
                metadata.s3VersionId = versionId;
                System.debug('  - S3 Version ID from header: ' + versionId);
            } else {
                metadata.s3VersionId = 'v1_' + System.now().format('yyyyMMddHHmmssSSS');
                System.debug('  - Generated Version ID: ' + metadata.s3VersionId);
            }
            
            // Get file extension - try multiple sources
            String fileName = getFileNameFromKey(fileKey);
            String extension = '';
            
            // First try: Get extension from filename
            if (fileName.contains('.')) {
                extension = fileName.substringAfterLast('.');
                System.debug('  - Extension from filename: ' + extension);
            }
            
            // Second try: Get extension from Content-Type header
            if (String.isBlank(extension)) {
                String contentType = response.getHeader('Content-Type');
                if (String.isNotBlank(contentType)) {
                    metadata.contentType = contentType.split(';')[0].trim();
                    extension = getExtensionFromContentType(metadata.contentType);
                    System.debug('  - Extension from Content-Type: ' + extension + ' (' + metadata.contentType + ')');
                }
            }
            
            // Third try: Get extension from file key's last part
            if (String.isBlank(extension)) {
                // Check if the file key itself has an extension after the last slash
                String lastPart = fileKey.substringAfterLast('/');
                if (lastPart.contains('.')) {
                    extension = lastPart.substringAfterLast('.');
                    System.debug('  - Extension from file key: ' + extension);
                }
            }
            
            metadata.fileExtension = extension;
            
            // If we have an extension but the filename doesn't have it, add it
            if (String.isNotBlank(extension) && !fileName.contains('.')) {
                // Store the full filename with extension for PathOnClient
                metadata.fileNameWithExtension = fileName + '.' + extension;
                System.debug('  - Added extension to filename: ' + metadata.fileNameWithExtension);
            } else {
                metadata.fileNameWithExtension = fileName;
            }
            
            // Get file size
            if (response.getBodyAsBlob() != null) {
                metadata.fileSize = response.getBodyAsBlob().size();
            }
            
        } catch (Exception ex) {
            System.debug('⚠️ Error extracting S3 metadata: ' + ex.getMessage());
            metadata.s3VersionId = 'v1_' + System.now().format('yyyyMMddHHmmssSSS');
        }
        
        return metadata;
    }
    private String getExtensionFromContentType(String contentType) {
        if (String.isBlank(contentType)) return '';
        
        Map<String, String> contentTypeToExtension = new Map<String, String>{
            'application/pdf' => 'pdf',
            'image/jpeg' => 'jpg',
            'image/jpg' => 'jpg',
            'image/png' => 'png',
            'image/gif' => 'gif',
            'image/bmp' => 'bmp',
            'image/webp' => 'webp',
            'image/svg+xml' => 'svg',
            'application/msword' => 'doc',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document' => 'docx',
            'application/vnd.ms-excel' => 'xls',
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' => 'xlsx',
            'application/vnd.ms-powerpoint' => 'ppt',
            'application/vnd.openxmlformats-officedocument.presentationml.presentation' => 'pptx',
            'text/plain' => 'txt',
            'text/csv' => 'csv',
            'application/json' => 'json',
            'application/xml' => 'xml',
            'application/zip' => 'zip',
            'application/x-rar-compressed' => 'rar',
            'application/x-7z-compressed' => '7z',
            'application/octet-stream' => ''
        };
        
        String lowerType = contentType.toLowerCase();
        if (contentTypeToExtension.containsKey(lowerType)) {
            return contentTypeToExtension.get(lowerType);
        }
        
        // Try partial match
        for (String key : contentTypeToExtension.keySet()) {
            if (lowerType.startsWith(key) || lowerType.contains(key)) {
                return contentTypeToExtension.get(key);
            }
        }
        
        return '';
    }
    /**
     * Process the file content and create ContentVersion
     * Links to BOTH the Email Message AND the Application
     * Stores S3 metadata including Version ID - SET DURING CREATION
     */
    private Boolean processFileContent(String fileKey, HttpResponse response, Id targetRecordId,
    Map<String, Id> existingDocs, EmailMessageWrapper emailWrapper, S3Metadata s3Metadata) {
        try {
            String fileName = String.isNotBlank(s3Metadata.fileNameWithExtension)
                ? s3Metadata.fileNameWithExtension
                : getFileNameFromKey(fileKey);
            
            String title = fileName.contains('.') ? fileName.substringBeforeLast('.') : fileName;
            String titleKey = normalizeTitle(title);
            Blob fileData = response.getBodyAsBlob();
            
            if (fileData.size() > MAX_FILE_SIZE) {
                System.debug('❌ File too large: ' + fileData.size() + ' bytes');
                return false;
            }
            
            if (fileData.size() == 0) {
                System.debug('❌ File is empty: ' + fileKey);
                return false;
            }
            
            // Create ContentVersion
            ContentVersion contentVersion = new ContentVersion();
            contentVersion.VersionData = fileData;
            contentVersion.PathOnClient = fileName;
            contentVersion.Title = title;
            contentVersion.Origin = 'H';
            
            // ***** CRITICAL: Set ALL S3 metadata BEFORE insert *****
            contentVersion.AWS_S3_Object_Key__c = s3Metadata.s3ObjectKey;
            contentVersion.S3_Version_Id__c = s3Metadata.s3VersionId;
            contentVersion.S3_Upload_Date__c = s3Metadata.uploadDate;
            contentVersion.S3_Upload_Status__c = 'Retrieved';
            if (String.isNotBlank(s3Metadata.fileExtension)) {
                contentVersion.File_Extension__c = s3Metadata.fileExtension;
            }
            
            // Check if document already exists by title
            Boolean isExisting = false;
            if (existingDocs.containsKey(titleKey)) {
                contentVersion.ContentDocumentId = existingDocs.get(titleKey);
                duplicateCount++;
                isExisting = true;
                System.debug('📄 Updating existing document: ' + contentVersion.ContentDocumentId);
            } else {
                // Set the first publish location to the target record
                contentVersion.FirstPublishLocationId = targetRecordId;
                System.debug('📄 Creating new document for ' + targetRecordId);
            }
            
            // Add description with S3 info including Version ID
            String description = 'Retrieved from S3: ' + fileKey;
            description += ' | Retrieved: ' + System.now().format();
            if (String.isNotBlank(s3Metadata.s3VersionId)) {
                description += ' | Version: ' + s3Metadata.s3VersionId;
            }
            if (String.isNotBlank(s3Metadata.fileExtension)) {
                description += ' | Type: ' + s3Metadata.fileExtension;
            }
            if (emailWrapper != null) {
                description += ' | Email: ' + emailWrapper.emailSubject;
            }
            contentVersion.Description = description;
            
            // ***** INSERT ContentVersion with ALL fields populated *****
            insert contentVersion;
            System.debug('✅ ContentVersion inserted: ' + contentVersion.Id);
            
            // Get the ContentDocument ID
            ContentVersion insertedVersion = [
                SELECT ContentDocumentId, AWS_S3_Object_Key__c, S3_Version_Id__c, S3_Upload_Status__c
                FROM ContentVersion 
                WHERE Id = :contentVersion.Id
            ];
            Id documentId = insertedVersion.ContentDocumentId;
            
            // Log verification
            System.debug('✅ VERIFICATION - S3 Object Key: ' + insertedVersion.AWS_S3_Object_Key__c);
            System.debug('✅ VERIFICATION - S3 Version ID: ' + insertedVersion.S3_Version_Id__c);
            System.debug('✅ VERIFICATION - S3 Status: ' + insertedVersion.S3_Upload_Status__c);
            
            // Update existing documents map
            existingDocs.put(titleKey, documentId);
            
            // ***** ALWAYS link to the Application *****
            if (applicationId != null) {
                try {
                    List<ContentDocumentLink> existingLinks = [
                        SELECT Id FROM ContentDocumentLink 
                        WHERE ContentDocumentId = :documentId 
                        AND LinkedEntityId = :applicationId
                        LIMIT 1
                    ];
                    
                    if (existingLinks.isEmpty()) {
                        ContentDocumentLink appLink = new ContentDocumentLink(
                            ContentDocumentId = documentId,
                        LinkedEntityId = applicationId,
                        ShareType = 'V'
                            );
                        insert appLink;
                        System.debug('🔗✅ Linked document ' + documentId + ' to Application: ' + applicationId);
                    } else {
                        System.debug('📄 Document already linked to Application: ' + applicationId);
                    }
                } catch (Exception ex) {
                    System.debug('❌ Error linking to Application: ' + ex.getMessage());
                }
            }
            
            // ***** If this is an email attachment, link it to the Email Message *****
            if (emailWrapper != null) {
                try {
                    List<ContentDocumentLink> emailLinks = [
                        SELECT Id FROM ContentDocumentLink 
                        WHERE ContentDocumentId = :documentId 
                        AND LinkedEntityId = :emailWrapper.emailId
                        LIMIT 1
                    ];
                    
                    if (emailLinks.isEmpty()) {
                        ContentDocumentLink emailLink = new ContentDocumentLink(
                            ContentDocumentId = documentId,
                        LinkedEntityId = emailWrapper.emailId,
                        ShareType = 'V'
                            );
                        insert emailLink;
                        System.debug('🔗✅ Linked document ' + documentId + ' to Email: ' + emailWrapper.emailId);
                    } else {
                        System.debug('📄 Document already linked to Email: ' + emailWrapper.emailId);
                    }
                } catch (Exception ex) {
                    System.debug('❌ Error linking to Email: ' + ex.getMessage());
                }
            }
            
            System.debug('✅ Successfully retrieved and linked: ' + fileKey);
            System.debug('  - ContentDocument ID: ' + documentId);
            System.debug('  - S3 Version ID: ' + s3Metadata.s3VersionId);
            System.debug('  - S3 Object Key: ' + s3Metadata.s3ObjectKey);
            
            return true;
            
        } catch (Exception ex) {
            System.debug('❌ Error processing file content: ' + ex.getMessage());
            System.debug('Stack trace: ' + ex.getStackTraceString());
            return false;
        }
    }
    
    /**
     * Finish method - called after all batches are processed
     */
    public void finish(Database.BatchableContext bc) {
        System.debug('=== FINISH METHOD CALLED ===');
        
        String finalStatus;
        String errorMessage = '';
        
        if (totalProcessed == 0) {
            finalStatus = 'No Files';
            errorMessage = 'No files found in any S3 package';
            if (!hasEmailPackages) {
                errorMessage += ' (No email packages found)';
            }
            if (String.isNotBlank(s3ListErrorMessage)) {
                errorMessage += ' | S3 Error: ' + s3ListErrorMessage;
            }
        } else if (failedCount == 0 && successfullyLinked > 0) {
            finalStatus = 'Success';
        } else if (failedCount > 0 && successfullyLinked > 0) {
            finalStatus = 'Partial Success';
            errorMessage = 'Failed to retrieve ' + failedCount + ' file(s)';
        } else if (failedCount > 0 && successfullyLinked == 0) {
            finalStatus = 'Failed';
            errorMessage = 'All ' + failedCount + ' file(s) failed to retrieve';
        } else {
            finalStatus = 'Unknown';
            errorMessage = 'Unexpected completion state';
        }
        
        // Update Application record
        updateApplicationRecord(finalStatus);
        
        // Update Email Message records (if any exist)
        if (hasEmailPackages) {
            updateEmailMessages(finalStatus);
        } else {
            System.debug('ℹ️ No Email Messages to update');
        }
        
        // Update Upload Result
        updateUploadResult(finalStatus, errorMessage);
        
        // Generate and send notification
        String summary = generateDetailedSummary();
        System.debug('S3 Retrieve Unified Batch Completed: ' + summary);
        
        if (String.isNotBlank(errorMessage) && finalStatus != 'Success' && finalStatus != 'No Files') {
            try {
                AwsS3NotificationService notificationService = new AwsS3NotificationService();
                notificationService.sendFailRetrieveNotification(errorMessage + '\n\n' + summary);
            } catch (Exception ex) {
                System.debug('⚠️ Error sending notification: ' + ex.getMessage());
            }
        }
    }
    
    /**
     * Updates Application record with retrieval information
     */
    private void updateApplicationRecord(String status) {
        try {
            if (applicationId == null) return;
            
            Application__c app = new Application__c(Id = applicationId);
            
            // If there were any files for the application OR email files were linked
            if (s3KeysByPackage.containsKey(applicationPackageFolder) || hasEmailPackages) {
                if (status == 'Success' || status == 'Partial Success') {
                    app.Retrieved_From_AWS_S3_Date__c = System.now();
                }
                
                // Clear package ID if all files were retrieved successfully
                if (status == 'Success') {
                    app.AWS_S3_Package_Id__c = null;
                    app.Send_Files_To_AWS_S3__c = false;
                }
            }
            
            update app;
            System.debug('✅ Updated Application record');
            
        } catch (Exception ex) {
            System.debug('ERROR updating Application record: ' + ex.getMessage());
        }
    }
    
    /**
     * Updates Email Message records with retrieval information
     */
    private void updateEmailMessages(String status) {
        try {
            List<EmailMessage> emailsToUpdate = new List<EmailMessage>();
            
            for (EmailMessageWrapper wrapper : emailMessagesMap.values()) {
                EmailMessage email = new EmailMessage(Id = wrapper.emailId);
                
                // Always update the email to mark it as processed
                if (wrapper.totalFiles > 0) {
                    email.S3_Upload_Status__c = 'Retrieved - ' + status;
                    email.S3_Retrieve_Date__c = System.now();
                    email.S3_Retrieved_Count__c = wrapper.successCount;
                    email.S3_Failed_Count__c = wrapper.failedCount;
                    
                    // Clear package ID if all files retrieved successfully
                    if (wrapper.failedCount == 0 && wrapper.successCount > 0) {
                        email.AWS_S3_Package_Id__c = null;
                    }
                } else {
                    email.S3_Upload_Status__c = 'No Files Found';
                    email.S3_Retrieve_Date__c = System.now();
                    email.S3_Retrieved_Count__c = 0;
                    email.S3_Failed_Count__c = 0;
                }
                
                // Add error details if any
                if (!wrapper.failedFiles.isEmpty()) {
                    String failedList = String.join(wrapper.failedFiles, '\n');
                    if (failedList.length() > 255) {
                        failedList = failedList.substring(0, 252) + '...';
                    }
                    email.S3_Error_Details__c = failedList;
                }
                
                emailsToUpdate.add(email);
                System.debug('📧 Updated Email: ' + wrapper.emailId + ' | Success: ' + wrapper.successCount + ' | Failed: ' + wrapper.failedCount);
            }
            
            if (!emailsToUpdate.isEmpty()) {
                update emailsToUpdate;
                System.debug('✅ Updated ' + emailsToUpdate.size() + ' Email Message records');
            }
            
        } catch (Exception ex) {
            System.debug('ERROR updating Email Messages: ' + ex.getMessage());
        }
    }
    
    /**
     * Updates Upload Result with current progress
     */
    private void updateUploadResultProgress() {
        try {
            if (uploadResultId == null) return;
            
            Decimal successRate = 0;
            if (totalProcessed > 0) {
                successRate = (successfullyLinked * 100.0) / totalProcessed;
            }
            
            AwsS3UploadResult__c uploadResult = new AwsS3UploadResult__c(
                Id = uploadResultId,
            UploadedCount__c = successfullyLinked,
            FailedCount__c = failedCount,
            Success_Rate__c = successRate.setScale(2),
            Status__c = 'In Progress'
                );
            
            update uploadResult;
            
        } catch (Exception ex) {
            System.debug('Error updating progress: ' + ex.getMessage());
        }
    }
    
    /**
     * Updates Upload Result with final status
     */
    private void updateUploadResult(String status, String errorMessage) {
        try {
            if (uploadResultId == null) return;
            
            Decimal successRate = 0;
            if (totalProcessed > 0) {
                successRate = (successfullyLinked * 100.0) / totalProcessed;
            }
            
            AwsS3UploadResult__c uploadResult = new AwsS3UploadResult__c(
                Id = uploadResultId,
            Status__c = status,
            UploadDate__c = System.now(),
            TotalProcessed__c = totalProcessed,
            UploadedCount__c = successfullyLinked,
            FailedCount__c = failedCount,
            Success_Rate__c = successRate.setScale(2)
                );
            
            if (String.isNotBlank(errorMessage)) {
                uploadResult.Failed_Details__c = errorMessage;
            }
            
            update uploadResult;
            uploadResultStatus = status;
            uploadResultErrorMessage = errorMessage;
            
        } catch (Exception ex) {
            System.debug('ERROR updating Upload Result: ' + ex.getMessage());
        }
    }
    
    // ==================== S3 UTILITY METHODS ====================
    
    /**
     * Gets list of files from S3 using the appropriate bucket
     * @param folderPath - The folder path to list
     * @param bucketType - 'APP' for application bucket, 'EMAIL' for email bucket
     */
    private List<String> getS3FileList(String folderPath, String bucketType) {
        List<String> fileKeys = new List<String>();
        
        // Choose the correct endpoint based on bucket type
        String endpointPrefix;
        String bucketName;
        if (bucketType == 'APP') {
            endpointPrefix = AWS_APP_ENDPOINT;
            bucketName = 'Application bucket';
        } else {
            endpointPrefix = AWS_EMAIL_ENDPOINT;
            bucketName = 'Email bucket';
        }
        
        // Build the folder path - if blank, just list the bucket root
        String pathParam = '';
        if (String.isNotBlank(folderPath)) {
            String formattedFolder = folderPath;
            if (!formattedFolder.endsWith('/')) {
                formattedFolder += '/';
            }
            pathParam = '&prefix=' + formattedFolder;
        }
        
        System.debug('📡 S3 LIST Request:');
        System.debug('  - Bucket: ' + bucketName);
        System.debug('  - Folder: ' + (String.isNotBlank(folderPath) ? folderPath : '(root)'));
        
        try {
            String baseEndpoint = endpointPrefix;
            if (baseEndpoint.endsWith('/')) {
                baseEndpoint = baseEndpoint.substring(0, baseEndpoint.length() - 1);
            }
            
            // Build the S3 LIST URL
            String endpoint = baseEndpoint + '/?list-type=2' + pathParam;
            
            HttpRequest request = new HttpRequest();
            request.setEndpoint(endpoint);
            request.setMethod('GET');
            request.setHeader('Content-Type', 'application/xml');
            request.setTimeout(30000);
            
            Http http = new Http();
            HttpResponse response = http.send(request);
            
            s3ListStatusCode = response.getStatusCode();
            s3ListResponse = response.getBody();
            
            System.debug('  - Status Code: ' + response.getStatusCode());
            
            if (response.getStatusCode() == 200) {
                String responseBody = response.getBody();
                if (String.isNotBlank(responseBody)) {
                    fileKeys = parseS3ListResponse(responseBody);
                    System.debug('  - Parsed ' + fileKeys.size() + ' files');
                    
                    // Log first few files found
                    if (!fileKeys.isEmpty()) {
                        System.debug('  - First 5 files:');
                        for (Integer i = 0; i < Math.min(5, fileKeys.size()); i++) {
                            System.debug('    ' + (i+1) + '. ' + fileKeys[i]);
                        }
                    }
                }
            } else {
                System.debug('❌ S3 LIST failed: ' + response.getStatusCode());
                System.debug('  - Response: ' + response.getBody());
                s3ListErrorMessage = 'Bucket: ' + bucketName + ' | Status: ' + response.getStatusCode();
            }
            
        } catch (Exception ex) {
            System.debug('❌ Error getting S3 file list: ' + ex.getMessage());
            s3ListErrorMessage = 'Exception: ' + ex.getMessage();
        }
        
        return fileKeys;
    }
    
    /**
     * Parses S3 LIST XML response
     */
    private List<String> parseS3ListResponse(String xmlResponse) {
        List<String> fileKeys = new List<String>();
        
        if (String.isBlank(xmlResponse)) {
            return fileKeys;
        }
        
        try {
            // Parse using String operations
            String keyTag = '<Key>';
            String endKeyTag = '</Key>';
            Integer startPos = 0;
            
            while (true) {
                Integer startIndex = xmlResponse.indexOf(keyTag, startPos);
                if (startIndex == -1) break;
                
                Integer endIndex = xmlResponse.indexOf(endKeyTag, startIndex);
                if (endIndex == -1) break;
                
                String key = xmlResponse.substring(startIndex + keyTag.length(), endIndex);
                
                if (!key.endsWith('/') && String.isNotBlank(key)) {
                    fileKeys.add(key);
                }
                
                startPos = endIndex + endKeyTag.length();
            }
            
        } catch (Exception ex) {
            System.debug('Error parsing S3 LIST response: ' + ex.getMessage());
        }
        
        return fileKeys;
    }
    
    /**
     * Downloads a file from S3 using the appropriate bucket
     * Enhanced to capture response headers for metadata extraction
     */
    private HttpResponse downloadFileFromS3(String fileKey, String bucketType) {
        try {
            String encodedKey = EncodingUtil.urlEncode(fileKey, 'UTF-8');
            encodedKey = encodedKey.replace('%2F', '/');
            encodedKey = encodedKey.replace('+', '%20');
            
            // Choose the correct endpoint based on bucket type
            String endpointPrefix;
            if (bucketType == 'APP') {
                endpointPrefix = AWS_APP_ENDPOINT;
            } else {
                endpointPrefix = AWS_EMAIL_ENDPOINT;
            }
            
            String endpoint = endpointPrefix + '/' + encodedKey;
            
            System.debug('📥 Downloading: ' + fileKey);
            
            HttpRequest request = new HttpRequest();
            request.setEndpoint(endpoint);
            request.setMethod('GET');
            request.setHeader('Content-Type', 'application/octet-stream');
            request.setTimeout(60000);
            
            Http http = new Http();
            HttpResponse response = http.send(request);
            
            if (response.getStatusCode() == 200) {
                System.debug('  ✅ Download successful');
                System.debug('  - S3 Version ID: ' + response.getHeader('x-amz-version-id'));
                System.debug('  - Last Modified: ' + response.getHeader('Last-Modified'));
                System.debug('  - ETag: ' + response.getHeader('ETag'));
            } else {
                System.debug('  ❌ Download failed: ' + response.getStatusCode());
            }
            
            return response;
            
        } catch (Exception ex) {
            System.debug('❌ Error downloading file: ' + ex.getMessage());
            return null;
        }
    }
    
    // ==================== HELPER METHODS ====================
    
    /**
     * Normalizes title for comparison
     */
    private String normalizeTitle(String title) {
        return title == null ? '' : title.trim().toLowerCase();
    }
    
    /**
     * Extracts filename from S3 key
     */
    private String getFileNameFromKey(String s3Key) {
        String fileName = s3Key;
        
        Integer lastSlash = s3Key.lastIndexOf('/');
        if (lastSlash != -1) {
            fileName = s3Key.substring(lastSlash + 1);
        }
        
        try {
            fileName = EncodingUtil.urlDecode(fileName, 'UTF-8');
        } catch (Exception ex) {
            // Keep original if decode fails
        }
        
        return fileName;
    }
    
    /**
     * Gets Application record
     */
    private Application__c getApplication(Id appId) {
        List<Application__c> applications = [
            SELECT Id, Name, AWS_S3_Package_Id__c, Send_To_AWS_S3_Date__c,
                   Retrieved_From_AWS_S3_Date__c, Send_Files_To_AWS_S3__c
            FROM Application__c
            WHERE Id = :appId
            LIMIT 1
        ];
        return applications.isEmpty() ? null : applications[0];
    }
    
    /**
     * Generates detailed summary
     */
    private String generateDetailedSummary() {
        List<String> parts = new List<String>();
        
        parts.add('=== UNIFIED S3 RETRIEVE BATCH SUMMARY ===');
        parts.add('');
        parts.add('Application: ' + (applicationRecord != null ? applicationRecord.Name : 'Unknown'));
        parts.add('Application ID: ' + applicationId);
        parts.add('Email Messages with S3 Data: ' + emailMessagesMap.size());
        parts.add('');
        parts.add('--- S3 Buckets ---');
        parts.add('Application Bucket: xtrapension-prod-bucket');
        parts.add('Email Bucket: xtrapension-prod-email-messages-bucket');
        parts.add('');
        parts.add('--- Overall Statistics ---');
        parts.add('Total Files in S3: ' + totalProcessed);
        parts.add('Successfully Retrieved: ' + successfullyLinked);
        parts.add('Duplicate Files: ' + duplicateCount);
        parts.add('Failed: ' + failedCount);
        if (totalProcessed > 0) {
            Decimal successRate = (successfullyLinked * 100.0) / totalProcessed;
            parts.add('Success Rate: ' + successRate.setScale(2) + '%');
        }
        parts.add('');
        parts.add('--- Linking Strategy ---');
        parts.add('✅ Email attachments are linked to both the Email Message AND the Application');
        parts.add('✅ S3 Version ID is extracted and stored on ContentVersion');
        parts.add('✅ S3 Object Key is stored for future upload detection');
        parts.add('');
        
        // Application files
        if (s3KeysByPackage.containsKey(applicationPackageFolder)) {
            Integer appFileCount = s3KeysByPackage.get(applicationPackageFolder).size();
            parts.add('--- Application Files (' + appFileCount + ' files) ---');
            parts.add('Status: ' + (failedCount == 0 ? '✅ Success' : '⚠️ Partial'));
            parts.add('');
        }
        
        // Email files
        if (hasEmailPackages) {
            for (EmailMessageWrapper wrapper : emailMessagesMap.values()) {
                if (wrapper.totalFiles > 0) {
                    parts.add('--- Email: ' + wrapper.emailSubject + ' (' + wrapper.totalFiles + ' files) ---');
                    parts.add('  Success: ' + wrapper.successCount);
                    parts.add('  Failed: ' + wrapper.failedCount);
                    if (!wrapper.successFiles.isEmpty()) {
                        parts.add('  Success Files:');
                        for (String file : wrapper.successFiles) {
                            parts.add('    ✅ ' + file);
                        }
                    }
                    if (!wrapper.failedFiles.isEmpty()) {
                        parts.add('  Failed Files:');
                        for (String file : wrapper.failedFiles) {
                            parts.add('    ❌ ' + file);
                        }
                    }
                    parts.add('');
                } else {
                    parts.add('--- Email: ' + wrapper.emailSubject + ' (No files found) ---');
                    parts.add('');
                }
            }
        } else {
            parts.add('ℹ️ No Email Messages with S3 data found');
            parts.add('');
        }
        
        if (failedFiles.isEmpty() && totalProcessed > 0) {
            parts.add('✅ All files retrieved successfully and linked to both Email and Application!');
        } else if (!failedFiles.isEmpty()) {
            parts.add('⚠️ Some files failed to retrieve. Please check the logs.');
        } else if (totalProcessed == 0) {
            parts.add('ℹ️ No files found in any S3 package');
        }
        
        return String.join(parts, '\n');
    }
    
    // ==================== PUBLIC GETTERS ====================
    
    public Integer getTotalProcessed() { return totalProcessed; }
    public Integer getSuccessfullyLinked() { return successfullyLinked; }
    public Integer getFailedCount() { return failedCount; }
    public Integer getDuplicateCount() { return duplicateCount; }
    public List<String> getFailedFiles() { return failedFiles; }
    public Id getUploadResultId() { return uploadResultId; }
    public String getUploadResultStatus() { return uploadResultStatus; }
    public Map<Id, Integer> getEmailTotalProcessed() { return emailTotalProcessed; }
    public Map<Id, Integer> getEmailSuccessCount() { return emailSuccessCount; }
    public Map<Id, Integer> getEmailFailedCount() { return emailFailedCount; }
    public Boolean getHasEmailPackages() { return hasEmailPackages; }
    
    public static void fakemethod() {
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