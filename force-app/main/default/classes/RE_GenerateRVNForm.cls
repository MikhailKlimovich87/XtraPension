public without sharing class RE_GenerateRVNForm {
    
    public static final String REAPPLY_FORM_URL =
        XtraPension_Data__c.getInstance().RE_Pdf_RVN_File_Link__c;
    
    public class Request {
        @InvocableVariable(required=true)
        public Id recordId;
    }
    
    @InvocableMethod(label='Generate RVN Form')
    public static void generate(List<Request> requests) {
        for (Request request : requests) {
            getRVNForm((String) request.recordId);
        }
    }
    
    @future(callout=true)
    public static void getRVNForm(String recordId) {
        
        Reapply__c currReapp = RE_PortalUtils.getRVN_ReapplyData(recordId);
        
        if (currReapp == null) {
            return;
        }
        
        RE_ResponseWrapper.RVN_FormWrapper wrap =
            new RE_ResponseWrapper.RVN_FormWrapper(currReapp);
        
        Map<String, Object> result = new Map<String, Object>();
        result.put('application', wrap);
        
        List<ContentDocumentLink> reapplyDocuments = [
            SELECT
                ContentDocumentId,
                ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
            AND ContentDocument.Title LIKE '%_RVN%'
        ];
        System.debug(reapplyDocuments);
        
        HttpRequest request = new HttpRequest();
        request.setEndpoint(REAPPLY_FORM_URL);
        request.setMethod('POST');
        request.setHeader(
            'Content-Type',
            'application/json;charset=UTF-8'
        );
        request.setBody(JSON.serialize(result));
        
        Http http = new Http();
        HttpResponse response = http.send(request);
        
        String fileName =
            currReapp.First_Name__c + '_' +
            currReapp.Second_Name__c + '_' +
            currReapp.Name + '__RVN';
        
        if (
            response.getStatusCode() >= 200 &&
            response.getStatusCode() < 300 &&
            !Test.isRunningTest()
        ) {
            if (reapplyDocuments.size() > 0) {
                updateDocumentVersion(
                    response.getBody(),
                    fileName,
                    'pdf',
                    reapplyDocuments
                );
            } else {
                generateDocument(
                    response.getBody(),
                    recordId,
                    fileName
                );
            }
        }
    }
    
    /**
     * Updates an existing ContentDocument with the generated PDF.
     *
     */
    public static void updateDocumentVersion(
        String resultBody,
        String fileName,
        String fileType,
        List<ContentDocumentLink> reappDocs
    ) {
        if (
            String.isBlank(resultBody) ||
            String.isBlank(fileName) ||
            reappDocs == null ||
            reappDocs.isEmpty()
        ) {
            return;
        }
        
        String base64 = extractBase64(resultBody);
        
        if (String.isBlank(base64)) {
            return;
        }

        insert new ContentVersion(
            ContentDocumentId = reappDocs[0].ContentDocumentId,
            VersionData = EncodingUtil.base64Decode(base64),
            PathOnClient = fileName + '.' + fileType,
            Title = fileName
        );
    }
    
    /**
     * Creates a new ContentVersion and links it to the Reapply record.
     */
    public static void generateDocument(
        String resultBody,
        String recordId,
        String fileName
    ) {
        if (
            String.isBlank(resultBody) ||
            String.isBlank(recordId) ||
            String.isBlank(fileName)
        ) {
            return;
        }
        
        String base64 = extractBase64(resultBody);
        
        if (String.isBlank(base64)) {
            return;
        }
        
        ContentVersion contentVersion =
            createContentVersion(
            base64,
            fileName,
            'pdf'
        );
        
        createContentLink(
            contentVersion.Id,
            recordId
        );
    }
    
    private static String extractBase64(String jsonString) {
        
        if (String.isBlank(jsonString)) {
            return null;
        }
        
        String key = '"base64"';
        
        Integer keyPosition = jsonString.indexOf(key);
        
        if (keyPosition == -1) {
            return null;
        }
        
        Integer colonPosition = jsonString.indexOf(
            ':',
        keyPosition + key.length()
            );
        
        if (colonPosition == -1) {
            return null;
        }
        
        Integer valueStart = colonPosition + 1;
        
        // Skip whitespace
        while (
            valueStart < jsonString.length() &&
            (
            jsonString.substring(valueStart, valueStart + 1) == ' ' ||
            jsonString.substring(valueStart, valueStart + 1) == '\n' ||
            jsonString.substring(valueStart, valueStart + 1) == '\r' ||
            jsonString.substring(valueStart, valueStart + 1) == '\t'
            )
        ) {
            valueStart++;
        }
        
        // Expect opening quote
        if (
            valueStart >= jsonString.length() ||
            jsonString.substring(valueStart, valueStart + 1) != '"'
        ) {
            return null;
        }
        
        valueStart++;
        
        Integer valueEnd = jsonString.indexOf(
            '"',
        valueStart
            );
        
        if (valueEnd == -1) {
            return null;
        }
        
        return jsonString.substring(
            valueStart,
            valueEnd
        );
    }
    
    public static ContentVersion createContentVersion(
        String base64,
        String fileName,
        String fileType
    ) {
        ContentVersion contentVersion = new ContentVersion();
        
        contentVersion.VersionData =
            EncodingUtil.base64Decode(base64);
        
        contentVersion.Title = fileName;
        contentVersion.PathOnClient =
            fileName + '.' + fileType;
        
        insert contentVersion;
        
        return contentVersion;
    }
    
    public static ContentDocumentLink createContentLink(
        String contentVersionId,
        String recordId
    ) {
        if (
            String.isBlank(contentVersionId) ||
            String.isBlank(recordId)
        ) {
            return null;
        }
        
        ContentVersion version = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersionId
            LIMIT 1
        ];
        
        ContentDocumentLink contentDocumentLink =
            new ContentDocumentLink();
        
        contentDocumentLink.ContentDocumentId =
            version.ContentDocumentId;
        
        contentDocumentLink.LinkedEntityId =
            recordId;
        
        contentDocumentLink.ShareType = 'V';
        
        insert contentDocumentLink;
        
        return contentDocumentLink;
    }
}