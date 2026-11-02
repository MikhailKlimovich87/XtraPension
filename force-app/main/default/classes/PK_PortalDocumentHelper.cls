public with sharing class PK_PortalDocumentHelper {
    public static Map<String, Object> getDocumentsFromRecord(PK_RequestWrappers.GetDocumentsDataWrapper wrapper) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            List<PK_PortalUtils.DocumentWrapper> documents = new List<PK_PortalUtils.DocumentWrapper>();
            if (String.isNotBlank(wrapper.recordId)) {
                documents = PK_PortalUtils.getDocumentWrappers(wrapper);
            }
            result.put('status', 'success');
            result.put('documents', documents);
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() + ' - ' + e.getMessage());
        }

        return result;
    }

    public static Map<String, Object> uploadFileToRecord(PK_RequestWrappers.UploadDocumentDataWrapper wrapper) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (String.isBlank(wrapper.base64) || String.isBlank(wrapper.fileName) || String.isBlank(wrapper.fileType)) {
                result.put('status', 'success');
                return result;
            }
            ContentVersion contentVersion = PK_PortalUtils.createContentVersion(wrapper.base64, wrapper.fileName, wrapper.fileType);
            ContentDocumentLink cdl = PK_PortalUtils.createContentLink(contentVersion.Id, wrapper.recordId);

            result.put('document', PK_PortalUtils.getDocumentWrapper(contentVersion.Id));
            result.put('status', 'success');
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() + ' - ' + e.getMessage());
        }

        return result;
    }

    public static Map<String, Object> getFileBase64(PK_RequestWrappers.GetDocumentDataWrapper wrapper) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            List<ContentVersion> contentVersions = [
                    SELECT Id, VersionData, Title, FileType, CreatedDate
                    FROM ContentVersion
                    WHERE Id = :wrapper.documentId
                    LIMIT 1
            ];
            if (contentVersions.size() > 0) {
                result.put('base64Data', EncodingUtil.base64Encode(contentVersions[0].VersionData));
                result.put('fileTitle', contentVersions[0].Title);
                result.put('fileType', contentVersions[0].FileType);
                result.put('createdDate', Date.valueOf(contentVersions[0].CreatedDate));
                result.put('status', 'success');
            } else {
                result.put('status', 'error');
                result.put('message', 'Document is not found!');
            }
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() + ' - ' + e.getMessage());
        }

        return result;
    }

    public static Map<String, Object> deleteFileFromRecord(PK_RequestWrappers.GetDocumentDataWrapper wrapper) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            List<ContentVersion> contentVersions = [
                    SELECT Id, VersionData, Title, FileType, ContentDocumentId
                    FROM ContentVersion
                    WHERE Id = :wrapper.documentId
                    LIMIT 1
            ];
            if (contentVersions.size() > 0) {
                ContentVersion contentVer = contentVersions[0];

                List<ContentDocument> documentsToDelete = [
                        SELECT Id
                        FROM ContentDocument
                        WHERE Id = :contentVer.ContentDocumentId
                ];

                if (!documentsToDelete.isEmpty()) {
                    delete documentsToDelete;
                    result.put('status', 'success');
                    result.put('message', 'Document deleted successfully');
                } else {
                    result.put('status', 'error');
                    result.put('message', 'ContentDocument not found');
                }
            } else {
                result.put('status', 'error');
                result.put('message', 'Document is not found!');
            }
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() + ' - ' + e.getMessage());
        }

        return result;
    }
}