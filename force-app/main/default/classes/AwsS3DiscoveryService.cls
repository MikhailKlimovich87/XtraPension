/**
 * Service for discovering S3 objects using Named Credentials
 * Uses AWS S3 REST API with Named Credentials for authentication
 */
public with sharing class AwsS3DiscoveryService {
    
    // Named Credential configuration
    private static final String NAMED_CREDENTIAL = 'AWS_S3';
    
    /**
     * Default constructor
     */
    public AwsS3DiscoveryService() {
        // Default constructor
    }
    
    /**
     * Lists all objects in a folder using AWS S3 ListObjects API
     * @param folderPath - The folder path to list objects from
     * @return List of S3ObjectInfo objects
     */
    public List<S3ObjectInfo> listObjectsInFolder(String folderPath) {
        List<S3ObjectInfo> objects = new List<S3ObjectInfo>();
        
        try {
            AwsS3Logger.debug('Listing objects in folder: ' + folderPath);
            
            // Ensure folder path ends with / for proper listing
            String prefix = folderPath;
            if (!prefix.endsWith('/')) {
                prefix += '/';
            }
            
            String endpoint = 'callout:' + NAMED_CREDENTIAL + '/?list-type=2&prefix=' +
                EncodingUtil.urlEncode(prefix, 'UTF-8') + '&delimiter=/';
            
            HttpRequest request = new HttpRequest();
            request.setEndpoint(endpoint);
            request.setMethod('GET');
            request.setHeader('Content-Type', 'application/xml');
            
            AwsS3Logger.debug('Request endpoint: ' + endpoint);
            
            Http http = new Http();
            HttpResponse response = http.send(request);
            
            Integer statusCode = response.getStatusCode();
            AwsS3Logger.debug('Response status: ' + statusCode);
            
            if (statusCode == 200) {
                String responseBody = response.getBody();
                if (String.isBlank(responseBody)) {
                    AwsS3Logger.warn('Empty response body from S3');
                    return objects;
                }
                
                // Parse XML response
                Dom.Document doc = response.getBodyDocument();
                if (doc == null) {
                    AwsS3Logger.warn('Failed to parse XML response');
                    return objects;
                }
                
                Dom.XmlNode root = doc.getRootElement();
                if (root == null) {
                    AwsS3Logger.warn('Empty XML response from S3');
                    return objects;
                }
                
                // Get all child nodes (Contents, CommonPrefixes, etc.)
                List<Dom.XmlNode> childNodes = root.getChildElements();
                if (childNodes == null || childNodes.isEmpty()) {
                    AwsS3Logger.debug('No child elements found in XML response');
                    return objects;
                }
                
                for (Dom.XmlNode node : childNodes) {
                    // Check for Contents nodes
                    if (node != null && node.getName() == 'Contents') {
                        
                        // Get child elements - using getChildElement with null namespace works for DOM nodes
                        // but we need to handle the case where elements might not exist
                        Dom.XmlNode keyNode = null;
                        Dom.XmlNode sizeNode = null;
                        Dom.XmlNode lastModifiedNode = null;
                        Dom.XmlNode eTagNode = null;
                        
                        // Iterate through children to find elements by name
                        List<Dom.XmlNode> children = node.getChildElements();
                        for (Dom.XmlNode child : children) {
                            String childName = child.getName();
                            if (childName == 'Key') {
                                keyNode = child;
                            } else if (childName == 'Size') {
                                sizeNode = child;
                            } else if (childName == 'LastModified') {
                                lastModifiedNode = child;
                            } else if (childName == 'ETag') {
                                eTagNode = child;
                            }
                        }
                        
                        if (keyNode == null) {
                            AwsS3Logger.debug('Skipping Contents node: Key element missing');
                            continue;
                        }
                        
                        String key = keyNode.getText();
                        if (String.isBlank(key) || key.endsWith('/')) {
                            continue;
                        }
                        
                        // Extract file name from key
                        String fileName = key.substringAfterLast('/');
                        
                        // Determine extension
                        String extension = '';
                        if (fileName.contains('.')) {
                            extension = fileName.substringAfterLast('.');
                        }
                        // If no extension, keep it empty
                        
                        Long size = 0;
                        if (sizeNode != null && String.isNotBlank(sizeNode.getText())) {
                            try {
                                size = Long.valueOf(sizeNode.getText());
                            } catch (Exception e) {
                                AwsS3Logger.warn('Failed to parse size for key: ' + key);
                            }
                        }
                        
                        String lastModified = '';
                        if (lastModifiedNode != null && String.isNotBlank(lastModifiedNode.getText())) {
                            lastModified = lastModifiedNode.getText();
                        }
                        
                        String eTag = '';
                        if (eTagNode != null && String.isNotBlank(eTagNode.getText())) {
                            eTag = eTagNode.getText().replaceAll('"', '');
                        }
                        
                        DateTime lastModifiedDate = parseS3Date(lastModified);
                        
                        S3ObjectInfo obj = new S3ObjectInfo(
                            key,
                        extension,
                        size,
                        eTag,
                        lastModifiedDate
                            );
                        objects.add(obj);
                        
                        AwsS3Logger.debug('Found object: ' + key + ' (Size: ' + size + ' bytes)');
                    }
                }
                
                AwsS3Logger.info('Found ' + objects.size() + ' objects in folder: ' + folderPath);
                
            } else if (statusCode == 404) {
                AwsS3Logger.warn('Folder not found: ' + folderPath);
            } else {
                String responseBody = response.getBody();
                AwsS3Logger.error('Error listing objects. Status: ' + statusCode +
                    ', Body: ' + (responseBody != null ? responseBody : 'No response body'));
                throw new AwsS3Exception('Error listing objects: ' + statusCode);
            }
            
        } catch (AwsS3Exception e) {
            throw e;
        } catch (Exception e) {
            AwsS3Logger.error('Error listing objects: ' + e.getMessage());
            throw new AwsS3Exception('Failed to list objects: ' + e.getMessage());
        }
        
        return objects;
    }
    
    /**
     * Checks if a specific object exists in S3 using HeadObject API
     * @param key - The S3 object key to check
     * @return Boolean indicating if the object exists
     */
    public Boolean objectExists(String key) {
        try {
            AwsS3Logger.debug('Checking if object exists: ' + key);
            
            // Build S3 HeadObject request using Named Credential
            String endpoint = 'callout:' + NAMED_CREDENTIAL + '/' + EncodingUtil.urlEncode(key, 'UTF-8');
            
            HttpRequest request = new HttpRequest();
            request.setEndpoint(endpoint);
            request.setMethod('HEAD');
            
            Http http = new Http();
            HttpResponse response = http.send(request);
            
            // 200 = exists, 404 = doesn't exist
            Boolean exists = response.getStatusCode() == 200;
            AwsS3Logger.debug('Object exists: ' + exists + ' (Status: ' + response.getStatusCode() + ')');
            
            return exists;
            
        } catch (Exception e) {
            AwsS3Logger.error('Error checking object existence: ' + e.getMessage());
            return false;
        }
    }
    
    /**
     * Checks if a folder exists by listing objects with the folder prefix
     * @param folderPath - The folder path to check
     * @return Boolean indicating if the folder has any objects
     */
    public Boolean folderExists(String folderPath) {
        try {
            // Ensure folder path ends with /
            if (!folderPath.endsWith('/')) {
                folderPath += '/';
            }
            
            // Check if folder exists by trying to list objects
            List<S3ObjectInfo> objects = listObjectsInFolder(folderPath);
            
            // If there are objects in the folder, it exists
            Boolean exists = !objects.isEmpty();
            AwsS3Logger.debug('Folder exists: ' + exists + ' (Found ' + objects.size() + ' objects)');
            
            return exists;
            
        } catch (Exception e) {
            AwsS3Logger.error('Error checking folder existence: ' + e.getMessage());
            return false;
        }
    }
    
    /**
     * Gets the size of a folder (total bytes)
     */
    public Long getFolderSize(String folderPath) {
        Long totalSize = 0;
        
        try {
            List<S3ObjectInfo> objects = listObjectsInFolder(folderPath);
            
            for (S3ObjectInfo obj : objects) {
                totalSize += obj.size;
            }
            
            AwsS3Logger.debug('Folder size: ' + totalSize + ' bytes (' + (totalSize / 1024) + ' KB)');
            
        } catch (Exception e) {
            AwsS3Logger.error('Error getting folder size: ' + e.getMessage());
        }
        
        return totalSize;
    }
    
    /**
     * Parses S3 date format to DateTime
     * Format: 2024-01-15T10:30:00.000Z
     */
    private static DateTime parseS3Date(String dateString) {
        try {
            if (String.isBlank(dateString)) {
                return DateTime.now();
            }
            
            // Remove the Z and convert to standard format
            String cleanDate = dateString.replace('Z', '');
            // Replace T with space for DateTime parsing
            cleanDate = cleanDate.replace('T', ' ');
            
            // Handle milliseconds
            if (cleanDate.contains('.')) {
                cleanDate = cleanDate.substringBefore('.');
            }
            
            return DateTime.valueOf(cleanDate);
        } catch (Exception e) {
            AwsS3Logger.warn('Error parsing date: ' + dateString + ' - ' + e.getMessage());
            return DateTime.now();
        }
    }
    
    /**
     * Extracts document ID from filename
     * Format: documentId_vN.ext
     */
    private static String extractDocumentId(String fileName) {
        if (String.isBlank(fileName)) return null;
        
        // Handle files without extension
        String nameWithoutExt = fileName;
        if (fileName.contains('.')) {
            nameWithoutExt = fileName.substringBeforeLast('.');
        }
        
        // Try to find pattern: 15 or 18 character ID followed by _v
        Pattern docIdPattern = Pattern.compile('^([a-zA-Z0-9]{15,18})(_v\\d+)?$');
        Matcher matcher = docIdPattern.matcher(nameWithoutExt);
        if (matcher.find()) {
            return matcher.group(1);
        }
        
        // If no pattern match, return the whole name (for files like "APPEAL reply")
        return nameWithoutExt;
    }
    
    /**
     * Gets file information for a specific S3 object
     * @param fileKey - The S3 object key
     * @return S3ObjectInfo with file metadata
     */
    public S3ObjectInfo getFileInfo(String fileKey) {
        try {
            AwsS3Logger.debug('Getting file info for: ' + fileKey);
            
            String encodedKey = EncodingUtil.urlEncode(fileKey, 'UTF-8');
            encodedKey = encodedKey.replace('%2F', '/');
            String endpoint = 'callout:' + NAMED_CREDENTIAL + '/' + encodedKey;
            
            HttpRequest request = new HttpRequest();
            request.setEndpoint(endpoint);
            request.setMethod('HEAD');
            
            Http http = new Http();
            HttpResponse response = http.send(request);
            
            if (response.getStatusCode() == 200) {
                String fileName = fileKey.substringAfterLast('/');
                String extension = fileName.contains('.') ? fileName.substringAfterLast('.') : '';
                Long size = 0;
                
                String contentLength = response.getHeader('Content-Length');
                if (String.isNotBlank(contentLength)) {
                    try {
                        size = Long.valueOf(contentLength);
                    } catch (Exception e) {
                        AwsS3Logger.warn('Failed to parse content length: ' + contentLength);
                    }
                }
                
                String versionId = response.getHeader('x-amz-version-id');
                String lastModified = response.getHeader('Last-Modified');
                DateTime lastModifiedDate = parseS3Date(lastModified);
                
                S3ObjectInfo obj = new S3ObjectInfo(
                    fileKey,
                extension,
                size,
                versionId,
                lastModifiedDate
                    );
                
                AwsS3Logger.debug('File info retrieved: ' + fileKey + ' (Size: ' + size + ' bytes)');
                return obj;
            }
            
            if (response.getStatusCode() == 404) {
                AwsS3Logger.warn('File not found: ' + fileKey);
                return null;
            }
            
            AwsS3Logger.error('Error getting file info. Status: ' + response.getStatusCode());
            return null;
            
        } catch (Exception e) {
            AwsS3Logger.error('Error getting file info: ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * Deletes a file from S3
     * @param fileKey - The S3 object key to delete
     * @return Boolean indicating success
     */
    public Boolean deleteFile(String fileKey) {
        try {
            AwsS3Logger.debug('Deleting file: ' + fileKey);
            
            String encodedKey = EncodingUtil.urlEncode(fileKey, 'UTF-8');
            encodedKey = encodedKey.replace('%2F', '/');
            String endpoint = 'callout:' + NAMED_CREDENTIAL + '/' + encodedKey;
            
            HttpRequest request = new HttpRequest();
            request.setEndpoint(endpoint);
            request.setMethod('DELETE');
            
            Http http = new Http();
            HttpResponse response = http.send(request);
            
            if (response.getStatusCode() == 204 || response.getStatusCode() == 200) {
                AwsS3Logger.debug('File deleted successfully: ' + fileKey);
                return true;
            }
            
            if (response.getStatusCode() == 404) {
                AwsS3Logger.warn('File not found for deletion: ' + fileKey);
                return false;
            }
            
            AwsS3Logger.error('Error deleting file. Status: ' + response.getStatusCode());
            return false;
            
        } catch (Exception e) {
            AwsS3Logger.error('Error deleting file: ' + e.getMessage());
            return false;
        }
    }
    
    /**
     * Extracts ContentVersion ID from S3 key
     * @param s3Key - The S3 object key
     * @return The ContentDocument ID or title if not found
     */
    public String getContentVersionFromS3Key(String s3Key) {
        if (String.isBlank(s3Key)) return null;
        
        String fileName = s3Key.substringAfterLast('/');
        String docId = extractDocumentId(fileName);
        
        return docId != null ? docId : fileName;
    }
    
    /**
     * Wrapper class for S3 object information
     */
    public class S3ObjectInfo {
        public String key;
        public String extension;
        public Long size;
        public String eTag;
        public DateTime lastModified;
        public String versionId;  // Added for version tracking
        
        // Constructor with Long for size
        public S3ObjectInfo(String key, String extension, Long size, String eTag, DateTime lastModified) {
            this.key = key;
            this.extension = extension;
            this.size = size;
            this.eTag = eTag;
            this.lastModified = lastModified;
            this.versionId = eTag; // Use ETag as version identifier
        }
    }
    
    /**
     * Custom exception class for S3 errors
     */
    public class AwsS3Exception extends Exception {
    }
}