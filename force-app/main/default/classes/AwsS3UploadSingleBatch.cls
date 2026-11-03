/**
 * Batch Apex class for uploading ContentDocument versions to AWS S3
 * This class processes files ONE BY ONE (batch size = 1) and saves all versions
 * to a SINGLE file in S3 using S3 Versioning
 *
 * S3 Versioning must be enabled on the bucket
 * Each upload creates a new version of the SAME file
 */
public with sharing class AwsS3UploadSingleBatch implements Database.Batchable<ContentVersion>, Database.AllowsCallouts, Database.Stateful {
    
    // Services
    private AwsS3DocumentService documentService;
    private AwsS3UploadService uploadService;
    private AwsS3ApplicationService applicationService;
    private AwsS3ContentDocumentService contentDocumentService;
    private AwsS3ResultService resultService;
    private AwsS3SummaryService summaryService;
    private AwsS3NotificationService notificationService;
    private AwsS3DiscoveryService discoveryService;
    
    // State and Configuration
    private AwsS3BatchState state;
    private UploadConfiguration config;
    private Map<String, List<String>> documentVersionsMap;
    private Map<String, S3FileInfo> existingS3Files;
    private Map<String, String> contentVersionS3IdMap;
    private Set<Id> noteDocumentIds;
    private Set<Id> processedEmailIds;
    
    // Constants
    private static final String S3_PACKAGE_SUFFIX = '.zip';
    private static final Integer MAX_PREFLIGHT_RETRIES = 3;
    
    /**
     * Inner class to hold S3 file information
     */
    private class S3FileInfo {
        public String s3ObjectKey;
        public String s3VersionId;
        public String fileName;
        public DateTime uploadDateTime;
        public Long fileSize;
        public String extension;
        public String contentDocumentId;
        public String title;
        
        public S3FileInfo(String key, String versionId, String name, DateTime uploadDateTime, Long size, String ext, String docId, String title) {
            this.s3ObjectKey = key;
            this.s3VersionId = versionId;
            this.fileName = name;
            this.uploadDateTime = uploadDateTime;
            this.fileSize = size;
            this.extension = ext;
            this.contentDocumentId = docId;
            this.title = title;
        }
    }
    
    /**
     * Constructor
     * @param applicationId - Id of the Application record
     */
    public AwsS3UploadSingleBatch(Id applicationId) {
        initialize(applicationId);
    }
    
    /**
     * Initializes the batch
     */
    private void initialize(Id applicationId) {
        // Initialize state
        this.state = new AwsS3BatchState();
        this.existingS3Files = new Map<String, S3FileInfo>();
        this.contentVersionS3IdMap = new Map<String, String>();
        this.noteDocumentIds = new Set<Id>();
        this.processedEmailIds = new Set<Id>();
        
        // Initialize configuration
        this.config = new UploadConfiguration();
        this.config.applicationId = applicationId;
        
        // Load application and set up folder
        Application__c app = getApplication(applicationId);
        if (app != null) {
            this.config.packageFolder = AwsS3ApiHandler.buildApplicationPackageFolder(app, null);
            this.config.s3PackageId = this.config.packageFolder;
            this.config.applicationName = app.Name;
            
            // Store in state
            this.state.packageFolderPath = this.config.packageFolder;
            
            AwsS3Logger.info('=== AwsS3UploadSingleBatch Initialized ===');
            AwsS3Logger.info('Application: ' + app.Name + ' (ID: ' + applicationId + ')');
            AwsS3Logger.info('Package Folder: ' + config.packageFolder);
            
            // Initialize discovery service
            this.discoveryService = new AwsS3DiscoveryService();
            
            // Check if package exists in S3
            checkPackageExistence();
            
            // Load existing S3 IDs from ContentVersion records
            loadExistingS3Ids(applicationId);
        } else {
            AwsS3Logger.error('Application not found with ID: ' + applicationId);
        }
        
        // Initialize services
        this.documentService = new AwsS3DocumentService(applicationId, state);
        this.uploadService = new AwsS3UploadService(config, state);
        this.applicationService = new AwsS3ApplicationService(applicationId, config, state);
        this.contentDocumentService = new AwsS3ContentDocumentService(config, state);
        this.resultService = new AwsS3ResultService(applicationId, state);
        this.notificationService = new AwsS3NotificationService();
    }
    
    /**
     * Loads existing S3 Version IDs from ContentVersion records
     */
    private void loadExistingS3Ids(Id applicationId) {
        try {
            Set<Id> contentDocumentIds = new Set<Id>();
            
            // Get Application documents
            for (ContentDocumentLink link : [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :applicationId
            ]) {
                contentDocumentIds.add(link.ContentDocumentId);
            }
            
            // Get Email Message documents
            List<EmailMessage> emails = getApplicationEmails(applicationId);
            if (!emails.isEmpty()) {
                Set<Id> emailIds = new Map<Id, EmailMessage>(emails).keySet();
                for (ContentDocumentLink link : [
                    SELECT ContentDocumentId
                    FROM ContentDocumentLink
                    WHERE LinkedEntityId IN :emailIds
                ]) {
                    contentDocumentIds.add(link.ContentDocumentId);
                }
                AwsS3Logger.debug('Added ' + emails.size() + ' email documents to process');
            }
            
            if (contentDocumentIds.isEmpty()) {
                AwsS3Logger.debug('No existing ContentDocuments found for application');
                return;
            }
            
            // Identify which documents are Notes
            identifyNoteDocuments(contentDocumentIds);
            
            // Get the latest version of each ContentDocument with S3 metadata
            List<ContentVersion> versionsWithS3Ids = [
                SELECT Id, ContentDocumentId, S3_Version_Id__c, AWS_S3_Object_Key__c,
                       Title, FileExtension, ContentSize, S3_Upload_Date__c
                FROM ContentVersion
                WHERE ContentDocumentId IN :contentDocumentIds
                AND IsLatest = true
                AND (S3_Version_Id__c != null OR AWS_S3_Object_Key__c != null)
                ORDER BY CreatedDate DESC
            ];
            
            for (ContentVersion cv : versionsWithS3Ids) {
                if (noteDocumentIds.contains(cv.ContentDocumentId)) {
                    AwsS3Logger.debug('Skipping Note document: ' + cv.Title + ' (ID: ' + cv.ContentDocumentId + ')');
                    continue;
                }
                
                String docId = cv.ContentDocumentId;
                String s3VersionId = cv.S3_Version_Id__c;
                String s3ObjectKey = cv.AWS_S3_Object_Key__c;
                
                if (String.isNotBlank(s3VersionId) && String.isNotBlank(s3ObjectKey)) {
                    S3FileInfo fileInfo = new S3FileInfo(
                        s3ObjectKey,
                    s3VersionId,
                    cv.Title,
                    cv.S3_Upload_Date__c,
                    cv.ContentSize,
                    cv.FileExtension,
                    docId,
                    cv.Title
                        );
                    existingS3Files.put(docId, fileInfo);
                    
                    AwsS3Logger.debug('Loaded S3 file info for document ' + docId +
                        ': Title "' + cv.Title + '" -> Key: ' + s3ObjectKey);
                }
            }
            
            AwsS3Logger.info('Loaded ' + existingS3Files.size() + ' existing S3 file references from ContentVersion records');
            AwsS3Logger.info('Identified ' + noteDocumentIds.size() + ' Note documents to exclude');
            
        } catch (Exception ex) {
            AwsS3Logger.error('Error loading existing S3 IDs: ' + ex.getMessage());
        }
    }
    
    /**
     * Gets all Email Messages related to the Application
     */
    private List<EmailMessage> getApplicationEmails(Id applicationId) {
        List<EmailMessage> emails = [
            SELECT Id, Subject, AWS_S3_Package_Id__c, S3_Upload_Date__c
            FROM EmailMessage
            WHERE ParentId = :applicationId OR RelatedToId = :applicationId
            ORDER BY S3_Upload_Date__c DESC
        ];
        return emails;
    }
    
    /**
     * Identifies which ContentDocuments are Notes
     */
    private void identifyNoteDocuments(Set<Id> contentDocumentIds) {
        try {
            Map<Id, ContentDocument> docMap = new Map<Id, ContentDocument>(
                [SELECT Id, FileType, FileExtension, Title 
                 FROM ContentDocument 
                 WHERE Id IN :contentDocumentIds]
                );
            
            List<ContentVersion> versions = [
                SELECT Id, ContentDocumentId, Title, FileExtension, ContentSize
                FROM ContentVersion
                WHERE ContentDocumentId IN :contentDocumentIds
                AND IsLatest = true
            ];
            
            for (ContentVersion version : versions) {
                ContentDocument doc = docMap.get(version.ContentDocumentId);
                if (isNote(version, doc)) {
                    noteDocumentIds.add(version.ContentDocumentId);
                    AwsS3Logger.debug('Identified Note document: "' + version.Title + '" (ID: ' + version.ContentDocumentId + ')');
                }
            }
            
        } catch (Exception ex) {
            AwsS3Logger.error('Error identifying Note documents: ' + ex.getMessage());
        }
    }
    
    /**
     * Determines if a ContentVersion is a Note
     */
    private Boolean isNote(ContentVersion version, ContentDocument document) {
        if (document != null) {
            if (document.FileType == 'SNOTE' || document.FileType == 'NOTE') {
                return true;
            }
        }
        
        String fileExt = version.FileExtension;
        if (String.isNotBlank(fileExt)) {
            if (fileExt.toLowerCase() == 'snote') {
                return true;
            }
        }
        
        String title = version.Title;
        if (String.isNotBlank(title)) {
            String titleLower = title.toLowerCase();
            if (titleLower.startsWith('note') ||
                titleLower.contains(' - note') ||
                titleLower.contains(' note ') ||
                titleLower.equals('untitled') ||
            titleLower.startsWith('untitled')) {
                return true;
            }
        }
        
        if (String.isBlank(fileExt) && version.ContentSize != null && version.ContentSize < 10240) {
            return true;
        }
        
        return false;
    }
    
    /**
     * Checks if a document is a Note
     */
    private Boolean isNoteDocument(String contentDocumentId) {
        return noteDocumentIds.contains(contentDocumentId);
    }
    
    /**
     * Checks if package folder exists in S3
     */
    private void checkPackageExistence() {
        try {
            AwsS3Logger.debug('Checking if package exists in S3: ' + config.packageFolder);
            
            List<AwsS3DiscoveryService.S3ObjectInfo> existingObjects =
                discoveryService.listObjectsInFolder(config.packageFolder);
            
            if (existingObjects.isEmpty()) {
                AwsS3Logger.info('Package does NOT exist in S3. Will create new package.');
                state.packageExistsInS3 = false;
                state.packageAction = 'CREATE_NEW';
            } else {
                AwsS3Logger.info('Package EXISTS in S3 with ' + existingObjects.size() + ' files.');
                state.packageExistsInS3 = true;
                state.packageAction = 'UPDATE_EXISTING';
                state.totalVersionsInS3 = existingObjects.size();
                mapExistingFiles(existingObjects);
                
                AwsS3Logger.debug('Found ' + existingS3Files.size() + ' unique documents in S3');
                for (String docId : existingS3Files.keySet()) {
                    S3FileInfo info = existingS3Files.get(docId);
                    AwsS3Logger.debug('  - Document: "' + info.title + '" -> ' + info.s3ObjectKey +
                        ' (Version: ' + info.s3VersionId + ')');
                }
            }
        } catch (Exception e) {
            AwsS3Logger.error('Error checking package existence: ' + e.getMessage());
            state.packageAction = 'CREATE_NEW';
            state.packageExistsInS3 = false;
            AwsS3Logger.warn('Could not verify package existence, proceeding with new package creation');
        }
    }
    
    /**
     * Maps existing S3 files by document title
     */
    private void mapExistingFiles(List<AwsS3DiscoveryService.S3ObjectInfo> existingObjects) {
        Map<String, List<AwsS3DiscoveryService.S3ObjectInfo>> filesByNormalizedTitle = new Map<String, List<AwsS3DiscoveryService.S3ObjectInfo>>();
        Map<String, String> normalizedToOriginal = new Map<String, String>();
        
        for (AwsS3DiscoveryService.S3ObjectInfo obj : existingObjects) {
            String key = obj.key;
            String fileName = key.substringAfterLast('/');
            
            String normalizedTitle = getNormalizedTitle(fileName);
            String originalTitle = getOriginalTitle(fileName);
            
            if (String.isNotBlank(normalizedTitle)) {
                if (!filesByNormalizedTitle.containsKey(normalizedTitle)) {
                    filesByNormalizedTitle.put(normalizedTitle, new List<AwsS3DiscoveryService.S3ObjectInfo>());
                }
                filesByNormalizedTitle.get(normalizedTitle).add(obj);
                
                if (!normalizedToOriginal.containsKey(normalizedTitle)) {
                    normalizedToOriginal.put(normalizedTitle, originalTitle);
                }
            }
        }
        
        for (String normalizedTitle : filesByNormalizedTitle.keySet()) {
            List<AwsS3DiscoveryService.S3ObjectInfo> files = filesByNormalizedTitle.get(normalizedTitle);
            if (files.isEmpty()) continue;
            
            files.sort();
            AwsS3DiscoveryService.S3ObjectInfo latestFile = files[files.size() - 1];
            
            if (files.size() > 1) {
                AwsS3Logger.warn('Found ' + files.size() + ' files with the same normalized title: "' + normalizedTitle + '"');
                AwsS3Logger.warn('Will consolidate into a single file using the latest version');
                for (Integer i = 0; i < files.size() - 1; i++) {
                    AwsS3DiscoveryService.S3ObjectInfo oldFile = files[i];
                    AwsS3Logger.debug('  - Consolidating old file: ' + oldFile.key + ' (Modified: ' + oldFile.lastModified + ')');
                }
                AwsS3Logger.debug('  - Keeping latest file: ' + latestFile.key + ' (Modified: ' + latestFile.lastModified + ')');
            }
            
            String originalTitle = normalizedToOriginal.get(normalizedTitle);
            String docId = normalizedTitle.replaceAll('[^a-zA-Z0-9]', '');
            String versionId = 'v1_' + System.now().format('yyyyMMddHHmmss');
            String consolidatedKey = config.packageFolder + '/' + originalTitle;
            
            S3FileInfo fileInfo = new S3FileInfo(
                consolidatedKey,
            versionId,
            originalTitle,
            latestFile.lastModified,
            latestFile.size,
            '',
            docId,
            originalTitle
                );
            existingS3Files.put(docId, fileInfo);
            AwsS3Logger.debug('Mapped consolidated file: "' + originalTitle + '" -> ' + consolidatedKey);
        }
    }
    
    private String getNormalizedTitle(String fileName) {
        if (String.isBlank(fileName)) return null;
        
        String baseName = fileName;
        if (baseName.contains('.')) {
            baseName = baseName.substringBeforeLast('.');
        }
        
        Pattern idPattern = Pattern.compile('^[a-zA-Z0-9]{15,18}_');
        Matcher matcher = idPattern.matcher(baseName);
        if (matcher.find()) {
            baseName = baseName.substring(matcher.end());
        }
        
        baseName = baseName.replaceAll('[_-]', ' ');
        
        Pattern versionPattern = Pattern.compile('(?i)\\s*[\\(\\s]*(\\d+)[\\)\\s]*$');
        Matcher versionMatcher = versionPattern.matcher(baseName);
        if (versionMatcher.find()) {
            String versionNum = versionMatcher.group(1);
            String baseWithoutVersion = baseName.substring(0, versionMatcher.start()).trim();
            if (String.isNotBlank(baseWithoutVersion)) {
                baseName = baseWithoutVersion + ' (1)';
            }
        } else {
            baseName = baseName.trim();
        }
        
        baseName = baseName.replaceAll('\\s+', ' ').trim();
        return baseName;
    }
    
    private String getOriginalTitle(String fileName) {
        if (String.isBlank(fileName)) return null;
        
        String baseName = fileName;
        if (baseName.contains('.')) {
            baseName = baseName.substringBeforeLast('.');
        }
        
        Pattern idPattern = Pattern.compile('^[a-zA-Z0-9]{15,18}_');
        Matcher matcher = idPattern.matcher(baseName);
        if (matcher.find()) {
            baseName = baseName.substring(matcher.end());
        }
        
        return baseName.trim();
    }
    
    /**
     * Start method - retrieves all ContentVersions to be processed
     */
    public Iterable<ContentVersion> start(Database.BatchableContext bc) {
        AwsS3Logger.debug('=== START METHOD CALLED ===');
        AwsS3Logger.debug('Package exists in S3: ' + state.packageExistsInS3);
        AwsS3Logger.debug('Package action: ' + state.packageAction);
        AwsS3Logger.debug('Existing S3 files loaded: ' + existingS3Files.size());
        AwsS3Logger.debug('Note documents identified: ' + noteDocumentIds.size());
        
        // Get Application versions
        List<ContentVersion> versions = documentService.getVersionsToProcess();
        this.documentVersionsMap = documentService.getDocumentVersionsMap();
        
        // Get Email versions
        List<ContentVersion> emailVersions = getEmailVersionsToProcess();
        if (!emailVersions.isEmpty()) {
            versions.addAll(emailVersions);
            AwsS3Logger.info('Added ' + emailVersions.size() + ' email versions to process');
        }
        
        // Filter out Notes
        versions = filterOutNotes(versions);
        
        // Filter versions to only process those that need uploading
        versions = filterVersionsForProcessing(versions);
        
        AwsS3Logger.info('Total versions to process after filtering: ' + versions.size());
        return versions;
    }
    
    /**
     * Gets all ContentVersions for Email Messages related to the Application
     */
    private List<ContentVersion> getEmailVersionsToProcess() {
        List<ContentVersion> emailVersions = new List<ContentVersion>();
        
        try {
            List<EmailMessage> emails = getApplicationEmails(config.applicationId);
            
            if (emails.isEmpty()) {
                AwsS3Logger.debug('No Email Messages found for Application');
                return emailVersions;
            }
            
            Set<Id> emailIds = new Map<Id, EmailMessage>(emails).keySet();
            
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :emailIds
            ];
            
            if (links.isEmpty()) {
                AwsS3Logger.debug('No ContentDocumentLinks found for Email Messages');
                return emailVersions;
            }
            
            Set<Id> docIds = new Set<Id>();
            for (ContentDocumentLink link : links) {
                docIds.add(link.ContentDocumentId);
            }
            
            emailVersions = [
                SELECT Id, Title, FileType, ContentSize, VersionNumber, 
                       ContentDocumentId, CreatedDate, IsLatest, Description, FileExtension,
                       AWS_S3_Object_Key__c, S3_Version_Id__c, S3_Upload_Status__c
                FROM ContentVersion
                WHERE ContentDocumentId IN :docIds
                AND IsLatest = true
                AND FileExtension != 'snote'
            ];
            
            AwsS3Logger.debug('Found ' + emailVersions.size() + ' email versions to process');
            
        } catch (Exception ex) {
            AwsS3Logger.error('Error getting email versions: ' + ex.getMessage());
        }
        
        return emailVersions;
    }
    
    /**
     * Filters out Notes from the list of ContentVersions
     */
    private List<ContentVersion> filterOutNotes(List<ContentVersion> versions) {
        List<ContentVersion> filteredVersions = new List<ContentVersion>();
        Integer noteCount = 0;
        
        for (ContentVersion version : versions) {
            String docId = version.ContentDocumentId;
            
            if (isNoteDocument(docId)) {
                noteCount++;
                String versionKey = docId + '_v' + version.VersionNumber;
                state.skippedVersions.add(versionKey);
                state.addFailedUpload(version.Title, 'Skipped: Note file (not uploaded to S3)');
                AwsS3Logger.debug('Skipping Note: "' + version.Title + '" (ID: ' + docId + ')');
            } else {
                filteredVersions.add(version);
            }
        }
        
        if (noteCount > 0) {
            AwsS3Logger.info('Filtered out ' + noteCount + ' Note(s) from S3 upload');
        }
        
        return filteredVersions;
    }
    
    /**
     * Filters versions to only include those that need uploading
     */
    private List<ContentVersion> filterVersionsForProcessing(List<ContentVersion> versions) {
        List<ContentVersion> versionsToProcess = new List<ContentVersion>();
        Integer skippedRetrievedCount = 0;
        
        for (ContentVersion version : versions) {
            String docId = version.ContentDocumentId;
            String versionKey = docId + '_v' + version.VersionNumber;
            
            // Always process files - they will create new versions in S3
            versionsToProcess.add(version);
            state.versionComparisonMap.put(versionKey, 'CREATE_NEW');
            AwsS3Logger.debug('Processing: "' + version.Title + '" (will create new S3 version)');
        }
        
        if (skippedRetrievedCount > 0) {
            AwsS3Logger.info('⏭️ Skipped ' + skippedRetrievedCount + ' file(s) that were retrieved from S3');
        }
        
        AwsS3Logger.info('Filtered versions: ' + versionsToProcess.size() +
            ' (Skipped: ' + (versions.size() - versionsToProcess.size()) + ')');
        
        return versionsToProcess;
    }
    
    /**
     * Execute method - processes ONE ContentVersion at a time
     */
    public void execute(Database.BatchableContext bc, List<ContentVersion> scope) {
        AwsS3Logger.debug('=== EXECUTE METHOD CALLED ===');
        AwsS3Logger.debug('Scope size: ' + scope.size());
        
        for (ContentVersion contentVersion : scope) {
            processSingleVersion(contentVersion);
        }
        
        contentDocumentService.updateDocuments();
    }
    
    /**
     * Process a single ContentVersion - Creates NEW VERSION of the same S3 file
     * Uses S3 Versioning - S3 bucket must have versioning enabled
     */
    private void processSingleVersion(ContentVersion contentVersion) {
        String docId = contentVersion.ContentDocumentId;
        String versionId = contentVersion.Id;
        String versionNumber = String.valueOf(contentVersion.VersionNumber);
        String title = contentVersion.Title;
        
        AwsS3Logger.debug('🔥 Processing: "' + title + '" (Version ' + versionNumber + ')');
        
        String versionKey = docId + '_v' + versionNumber;
        if (state.skippedVersions.contains(versionKey)) {
            AwsS3Logger.debug('Skipping already processed version: ' + versionKey);
            return;
        }
        
        ContentVersion fullVersion = documentService.loadFullVersion(versionId);
        
        if (fullVersion == null || fullVersion.VersionData == null) {
            String errorMsg = 'No data available';
            state.addFailedUpload(title, errorMsg);
            AwsS3Logger.warn('SKIPPED: No data for version "' + title + '"');
            return;
        }
        
        // 🔥 USE THE SAME S3 KEY FOR ALL VERSIONS OF A DOCUMENT
        // S3 Versioning will handle creating new versions automatically
        String operation = 'CREATE_NEW';
        String existingS3VersionId = null;
        
        // Build consistent S3 key (without timestamp)
        String cleanTitle = cleanFileName(title);
        String extension = fullVersion.FileExtension != null ? fullVersion.FileExtension : '';
        
        String s3Key;
        if (String.isNotBlank(extension)) {
            String cleanExt = extension.replaceAll('[^a-zA-Z0-9]', '').toLowerCase();
            // Format: folder/filename.png (SAME key for all versions)
            s3Key = config.packageFolder + '/' + cleanTitle + '.' + cleanExt;
        } else {
            s3Key = config.packageFolder + '/' + cleanTitle;
        }
        
        // Check if we have existing S3 info for this document
        S3FileInfo existingInfo = existingS3Files.get(docId);
        if (existingInfo != null && String.isNotBlank(existingInfo.s3ObjectKey)) {
            // Use the existing S3 key to maintain version history
            s3Key = existingInfo.s3ObjectKey;
            AwsS3Logger.debug('📁 Using existing S3 key: ' + s3Key + ' (will create new version)');
        } else {
            AwsS3Logger.debug('📁 New S3 key: ' + s3Key + ' (will create first version)');
        }
        
        // Set the key in config
        config.s3ObjectKey = s3Key;
        
        AwsS3Logger.debug('🔥 UPLOADING NEW VERSION: "' + title + '" -> ' + s3Key);
        AwsS3Logger.debug('📌 S3 Versioning will create a new version of this file');
        
        state.documentOperationMap.put(docId, operation);
        
        UploadResult result = uploadService.uploadWithVersioning(fullVersion, operation, existingS3VersionId);
        
        if (result.success) {
            String newS3VersionId = result.s3VersionId;
            
            S3FileInfo updatedInfo = new S3FileInfo(
                s3Key,
            newS3VersionId,
            title,
            System.now(),
            fullVersion.ContentSize,
            fullVersion.FileExtension,
            docId,
            title
                );
            existingS3Files.put(docId, updatedInfo);
            
            updateContentVersionWithS3Id(fullVersion.Id, newS3VersionId, s3Key);
            
            state.addSuccessfulUpload(title, s3Key);
            AwsS3Logger.info('✅ Upload successful: "' + title + '" (S3 Version ID: ' + newS3VersionId + ')');
            AwsS3Logger.info('📁 S3 Key: ' + s3Key + ' (Version ' + versionNumber + ' of ' + cleanTitle + ')');
        } else {
            state.addFailedUpload(title, result.error);
            AwsS3Logger.error('❌ Upload failed: "' + title + '" - ' + result.error);
        }
        
        AwsS3Logger.debug('Processed ' + (state.uploadedCount + state.failedUploads.size()) + ' files. ' +
            'Uploaded: ' + state.uploadedCount + ', Failed: ' + state.failedUploads.size());
    }
    
    /**
     * Helper method to clean filename for S3
     */
    private String cleanFileName(String fileName) {
        if (String.isBlank(fileName)) return 'untitled';
        String cleaned = fileName.replaceAll('[^a-zA-Z0-9\\s\\(\\)\\-\\_\\.]', '');
        cleaned = cleaned.replaceAll('\\s+', ' ');
        cleaned = cleaned.trim();
        if (cleaned.length() > 200) {
            cleaned = cleaned.substring(0, 200);
        }
        return cleaned;
    }
    
    /**
     * Updates the ContentVersion record with S3 Version ID
     */
    private void updateContentVersionWithS3Id(Id contentVersionId, String s3VersionId, String s3ObjectKey) {
        try {
            ContentVersion currentVersion = [SELECT Id, ContentDocumentId, VersionNumber 
                                             FROM ContentVersion 
                                             WHERE Id = :contentVersionId 
                                             LIMIT 1];
            
            if (currentVersion == null) {
                AwsS3Logger.error('ContentVersion not found: ' + contentVersionId);
                return;
            }
            
            List<ContentVersion> latestVersions = [
                SELECT Id, ContentDocumentId, VersionNumber, IsLatest
                FROM ContentVersion
                WHERE ContentDocumentId = :currentVersion.ContentDocumentId
                AND IsLatest = true
                LIMIT 1
            ];
            
            Id versionToUpdateId;
            String versionInfo;
            
            if (!latestVersions.isEmpty()) {
                ContentVersion latestVersion = latestVersions[0];
                versionToUpdateId = latestVersion.Id;
                versionInfo = 'Latest (v' + latestVersion.VersionNumber + ')';
                
                if (latestVersion.Id != contentVersionId) {
                    AwsS3Logger.warn('Version mismatch: Attempted to update v' + currentVersion.VersionNumber +
                        ', but using latest v' + latestVersion.VersionNumber);
                    
                    ContentVersion checkLatest = [SELECT Id, IsLatest, VersionNumber
                                                  FROM ContentVersion 
                                                  WHERE Id = :contentVersionId 
                                                  LIMIT 1];
                    
                    if (!checkLatest.IsLatest) {
                        AwsS3Logger.warn('Version ' + contentVersionId + ' is not the latest (v' +
                            checkLatest.VersionNumber + '). Will update the latest version instead.');
                        
                        ContentVersion latestToUpdate = new ContentVersion(
                            Id = latestVersion.Id,
                        S3_Version_Id__c = s3VersionId,
                        AWS_S3_Object_Key__c = s3ObjectKey,
                        S3_Upload_Date__c = System.now(),
                        S3_Upload_Status__c = 'Uploaded'
                            );
                        update latestToUpdate;
                        AwsS3Logger.info('✅ Updated latest version (v' + latestVersion.VersionNumber +
                            ') with S3 Version ID: ' + s3VersionId);
                        return;
                    }
                }
            } else {
                versionToUpdateId = contentVersionId;
                versionInfo = 'Provided (no latest found)';
            }
            
            ContentVersion cv = new ContentVersion(
                Id = versionToUpdateId,
            S3_Version_Id__c = s3VersionId,
            AWS_S3_Object_Key__c = s3ObjectKey,
            S3_Upload_Date__c = System.now(),
            S3_Upload_Status__c = 'Uploaded'
                );
            
            update cv;
            AwsS3Logger.debug('✅ Updated ContentVersion ' + versionToUpdateId +
                ' (' + versionInfo + ') with S3 Version ID: ' + s3VersionId);
            
        } catch (DmlException dmlex) {
            for (Integer i = 0; i < dmlex.getNumDml(); i++) {
                AwsS3Logger.error('DML Error ' + i + ': ' + dmlex.getDmlMessage(i) +
                    ' on field: ' + dmlex.getDmlFieldNames(i));
            }
            
            if (dmlex.getMessage().contains('INVALID_STATUS')) {
                try {
                    AwsS3Logger.warn('Retrying with a different approach...');
                    
                    ContentVersion sourceVersion = [SELECT ContentDocumentId 
                                                    FROM ContentVersion 
                                                    WHERE Id = :contentVersionId 
                                                    LIMIT 1];
                    
                    if (sourceVersion != null) {
                        ContentVersion latestVersion = [SELECT Id, ContentDocumentId
                                                        FROM ContentVersion
                                                        WHERE ContentDocumentId = :sourceVersion.ContentDocumentId
                                                        AND IsLatest = true
                                                        LIMIT 1];
                        
                        if (latestVersion != null) {
                            ContentVersion retryUpdate = new ContentVersion(
                                Id = latestVersion.Id,
                            S3_Version_Id__c = s3VersionId,
                            AWS_S3_Object_Key__c = s3ObjectKey,
                            S3_Upload_Date__c = System.now(),
                            S3_Upload_Status__c = 'Uploaded'
                                );
                            update retryUpdate;
                            AwsS3Logger.info('✅ Retry successful - updated latest version: ' + latestVersion.Id);
                            return;
                        }
                    }
                    
                    AwsS3Logger.error('Could not update ContentVersion. Manual intervention may be required.');
                    AwsS3Logger.error('Failed to update S3 info for version: ' + contentVersionId);
                    
                } catch (Exception retryEx) {
                    AwsS3Logger.error('Retry also failed: ' + retryEx.getMessage());
                    AwsS3Logger.error('Could not update ContentVersion. Manual intervention may be required.');
                    AwsS3Logger.error('Failed to update S3 info for version: ' + contentVersionId);
                }
            } else {
                throw dmlex;
            }
        } catch (Exception ex) {
            AwsS3Logger.error('Error updating ContentVersion with S3 ID: ' + ex.getMessage());
            AwsS3Logger.error('Stack trace: ' + ex.getStackTraceString());
        }
    }
    
    /**
     * Finish method - called after all batches are processed
     */
    public void finish(Database.BatchableContext bc) {
        AwsS3Logger.debug('=== FINISH METHOD CALLED ===');
        finalizeState();
        finishOperations();
    }
    
    /**
     * Finalizes the batch state
     */
    private void finalizeState() {
        if (!state.totalSet || state.totalProcessed == 0) {
            if (!state.uploadStatusMap.isEmpty()) {
                state.totalProcessed = state.uploadStatusMap.size();
            } else if (documentVersionsMap != null && !documentVersionsMap.isEmpty()) {
                Integer total = 0;
                for (List<String> versions : documentVersionsMap.values()) {
                    total += versions.size();
                }
                total -= state.getSkippedCount();
                state.totalProcessed = total;
            }
            state.totalSet = true;
        }
        
        state.uploadedCount = state.uploadStatusMap.values().size();
        state.allUploadsSuccessful = state.isAllUploadsSuccessful();
        
        AwsS3Logger.debug('Final - Total: ' + state.totalProcessed +
            ', Uploaded: ' + state.uploadedCount +
            ', Failed: ' + state.failedUploads.size() +
            ', Skipped: ' + state.getSkippedCount());
    }
    
    /**
     * Executes all finish operations
     */
    private void finishOperations() {
        applicationService.updateApplication();
        
        AwsS3Logger.info('Package action performed: ' + state.packageAction);
        if (state.packageAction == 'CREATE_NEW') {
            AwsS3Logger.info('Created new package for application: ' + config.applicationName);
        } else {
            AwsS3Logger.info('Updated existing package for application: ' + config.applicationName);
        }
        
        if (config.deleteAfterUpload && state.allUploadsSuccessful) {
            contentDocumentService.deleteFiles(noteDocumentIds);
            AwsS3Logger.info('Deleted uploaded files from Salesforce (excluding ' + noteDocumentIds.size() + ' Notes)');
        } else if (config.deleteAfterUpload && !state.allUploadsSuccessful) {
            AwsS3Logger.warn('Skipping file deletion because not all uploads were successful');
        }
        
        this.summaryService = new AwsS3SummaryService(
            config.applicationId,
        state,
        documentVersionsMap,
        config
            );
        String summary = summaryService.generateDetailedSummary();
        
        resultService.createResult();
        
        if (!state.failedUploads.isEmpty()) {
            String failureMessage =
                'AWS S3 Upload completed with errors.\n\n' +
                'Application: ' + config.applicationId + '\n' +
                'Action: ' + state.packageAction + '\n' +
                'Uploaded: ' + state.uploadedCount + '\n' +
                'Failed: ' + state.failedUploads.size() + '\n' +
                'Skipped: ' + state.getSkippedCount() + ' (including Notes)\n\n' +
                'Failed files:\n' +
                String.join(state.failedUploads, '\n');
            
            notificationService.sendFailureNotification(failureMessage);
        }
        
        AwsS3Logger.info('S3 Upload Single Batch Completed');
        AwsS3Logger.info('Package Action: ' + state.packageAction);
        AwsS3Logger.info('Summary: ' + summary);
    }
    
    /**
     * Retrieves Application record
     */
    private Application__c getApplication(Id appId) {
        List<Application__c> applications = [
            SELECT Id, Name
            FROM Application__c
            WHERE Id = :appId
            LIMIT 1
        ];
        return applications.isEmpty() ? null : applications[0];
    }
    
    // ==================== PUBLIC GETTERS ====================
    
    public Integer getUploadedCount() {
        return state.uploadedCount;
    }
    
    public Integer getTotalProcessed() {
        return state.totalProcessed;
    }
    
    public List<String> getFailedUploads() {
        return state.failedUploads;
    }
    
    public Boolean getPackageExistsInS3() {
        return state.packageExistsInS3;
    }
    
    public String getPackageAction() {
        return state.packageAction;
    }
}