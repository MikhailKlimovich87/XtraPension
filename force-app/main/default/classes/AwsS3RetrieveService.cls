/**
 * Service class for S3 retrieve operations
 */
public with sharing class AwsS3RetrieveService {
    
    private static final Integer MAX_FILE_SIZE = 5000000; // 5MB limit for Salesforce
    private static final String AWS_ENDPOINT = 'callout:AWS_S3';
    
    private RetrieveConfiguration config;
    private AwsS3RetrieveState state;
    
    public AwsS3RetrieveService(RetrieveConfiguration config, AwsS3RetrieveState state) {
        this.config = config;
        this.state = state;
    }
    
    /**
     * Gets list of files from S3
     */
    public List<String> getFileList() {
        List<String> fileKeys = new List<String>();
        String folderPath = config.packageFolder;
        
        AwsS3Logger.debug('=== GETS3FILELIST START ===');
        AwsS3Logger.debug('📁 FolderPath: ' + folderPath);
        
        // Ensure folder path ends with /
        if (!folderPath.endsWith('/')) {
            folderPath += '/';
        }
        
        try {
            // Build the S3 LIST URL
            String baseEndpoint = AWS_ENDPOINT;
            if (baseEndpoint.endsWith('/')) {
                baseEndpoint = baseEndpoint.substring(0, baseEndpoint.length() - 1);
            }
            
            String endpoint = baseEndpoint + '/?list-type=2&prefix=' + folderPath;
            
            HttpRequest request = new HttpRequest();
            request.setEndpoint(endpoint);
            request.setMethod('GET');
            request.setHeader('Content-Type', 'application/xml');
            
            Http http = new Http();
            HttpResponse response = http.send(request);
            
            if (response.getStatusCode() == 200) {
                String responseBody = response.getBody();
                if (String.isNotBlank(responseBody)) {
                    fileKeys = parseS3ListResponse(responseBody);
                }
            } else {
                AwsS3Logger.warn('S3 LIST failed with status: ' + response.getStatusCode());
                fileKeys = getFilesFromApplicationRecords();
            }
            
        } catch (Exception ex) {
            AwsS3Logger.error('Exception in getS3FileList: ' + ex.getMessage());
            fileKeys = getFilesFromApplicationRecords();
        }
        
        AwsS3Logger.debug('Returning ' + fileKeys.size() + ' files');
        return fileKeys;
    }
    
    /**
     * Parses S3 LIST XML response
     */
    private List<String> parseS3ListResponse(String xmlResponse) {
        List<String> fileKeys = new List<String>();
        
        try {
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
            AwsS3Logger.error('Error parsing S3 LIST response: ' + ex.getMessage());
        }
        
        return fileKeys;
    }
    
    /**
     * Fallback: Get file list from Application ContentDocuments
     */
    private List<String> getFilesFromApplicationRecords() {
        List<String> fileKeys = new List<String>();
        
        try {
            List<ContentDocumentLink> existingLinks = [
                SELECT ContentDocumentId, ContentDocument.Title
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :config.applicationId
            ];
            
            for (ContentDocumentLink link : existingLinks) {
                if (String.isNotBlank(link.ContentDocument.Title)) {
                    String fileKey = config.packageFolder + '/' + link.ContentDocument.Title;
                    fileKeys.add(fileKey);
                }
            }
            
        } catch (Exception ex) {
            AwsS3Logger.error('Error getting files from records: ' + ex.getMessage());
        }
        
        return fileKeys;
    }
    
    /**
     * Downloads a file from S3
     */
    public HttpResponse downloadFile(String fileKey) {
        try {
            String encodedKey = EncodingUtil.urlEncode(fileKey, 'UTF-8');
            encodedKey = encodedKey.replace('%2F', '/');
            encodedKey = encodedKey.replace('+', '%20');
            
            String endpoint = AWS_ENDPOINT + '/' + encodedKey;
            
            HttpRequest request = new HttpRequest();
            request.setEndpoint(endpoint);
            request.setMethod('GET');
            request.setHeader('Content-Type', 'application/octet-stream');
            
            Http http = new Http();
            HttpResponse response = http.send(request);
            
            if (response.getStatusCode() != 200) {
                AwsS3Logger.warn('Download error: ' + response.getStatusCode() + ' - ' + response.getBody());
            }
            
            return response;
            
        } catch (Exception ex) {
            AwsS3Logger.error('Error downloading file: ' + ex.getMessage());
            return null;
        }
    }
    
    /**
     * Creates ContentVersion from downloaded file
     */
    public ContentVersion createContentVersion(String fileKey, HttpResponse response) {
        try {
            if (response == null || response.getStatusCode() != 200) {
                return null;
            }
            
            String fileName = getFileNameFromKey(fileKey);
            
            // Add extension if missing
            if (!fileName.contains('.')) {
                String contentType = response.getHeader('Content-Type');
                if (String.isNotBlank(contentType)) {
                    contentType = contentType.split(';')[0].trim().toLowerCase();
                    String extension = getExtensionFromContentType(contentType);
                    if (String.isNotBlank(extension)) {
                        fileName += extension;
                    }
                }
            }
            
            String title = fileName.contains('.')
                ? fileName.substringBeforeLast('.')
                : fileName;
            
            Blob fileData = response.getBodyAsBlob();
            
            if (fileData.size() > MAX_FILE_SIZE) {
                AwsS3Logger.warn('File too large: ' + fileData.size() + ' bytes');
                return null;
            }
            
            if (fileData.size() == 0) {
                AwsS3Logger.warn('File is empty: ' + fileKey);
                return null;
            }
            
            ContentVersion contentVersion = new ContentVersion();
            contentVersion.VersionData = fileData;
            contentVersion.PathOnClient = fileName;
            contentVersion.Description = 'Retrieved from S3: ' + fileKey +
                ' | Retrieved: ' + System.now().format();
            contentVersion.Origin = 'H';
            
            String lookupKey = normalizeTitle(title);
            
            if (config.existingContentDocuments.containsKey(lookupKey)) {
                // Existing file -> create new version
                contentVersion.ContentDocumentId = config.existingContentDocuments.get(lookupKey);
                AwsS3Logger.debug('Updating existing document: ' + contentVersion.ContentDocumentId);
            } else {
                // New file
                contentVersion.Title = title;
                contentVersion.FirstPublishLocationId = config.applicationId;
                AwsS3Logger.debug('Creating new document');
            }
            
            return contentVersion;
            
        } catch (Exception ex) {
            AwsS3Logger.error('Error creating ContentVersion: ' + ex.getMessage());
            return null;
        }
    }
    
    /**
     * Gets extension from content type
     */
    private String getExtensionFromContentType(String contentType) {
        Map<String, String> extensions = new Map<String, String>{
            'application/pdf' => '.pdf',
            'image/jpeg' => '.jpg',
            'image/png' => '.png',
            'application/msword' => '.doc',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document' => '.docx',
            'application/vnd.ms-excel' => '.xls',
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' => '.xlsx',
            'text/plain' => '.txt',
            'application/zip' => '.zip',
            'image/jpg' => '.jpg',
            'application/x-pdf' => '.pdf'
        };
        
        return extensions.containsKey(contentType) ? extensions.get(contentType) : '';
    }
    
    /**
     * Extracts filename from S3 key
     */
    public String getFileNameFromKey(String fileKey) {
        String fileName = fileKey;
        
        Integer lastSlash = fileKey.lastIndexOf('/');
        if (lastSlash != -1) {
            fileName = fileKey.substring(lastSlash + 1);
        }
        
        try {
            fileName = EncodingUtil.urlDecode(fileName, 'UTF-8');
        } catch (Exception ex) {
            // Use original if decoding fails
        }
        
        return fileName;
    }
    
    /**
     * Normalizes title for lookup
     */
    private String normalizeTitle(String title) {
        return title == null ? '' : title.trim().toLowerCase();
    }
}