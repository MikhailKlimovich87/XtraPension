/**
 * Configuration class for S3 retrieve operations
 */
public with sharing class RetrieveConfiguration {
    
    public Id applicationId;
    public String packageFolder;
    public String s3PackageId;
    public Map<String, Id> existingContentDocuments = new Map<String, Id>();
}