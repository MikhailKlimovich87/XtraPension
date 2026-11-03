public without sharing class RE_GenerateReapplyForm {

    public static final String REAPPLY_FORM_URL =
        XtraPension_Data__c.getInstance().RE_Pdf_File_Link__c;

    public class Request {
        @InvocableVariable(required=true)
        public Id recordId;
    }

    @InvocableMethod(label='Generate Reapply Form')
    public static void generate(List<Request> requests) {
        for (Request request : requests) {
            getReapplyForm((String) request.recordId);
        }
    }

    @future(callout=true)
    public static void getReapplyForm(String recordId) {
        System.debug('Generating Reapply Form for recordId: ' + recordId);
        Reapply__c currReapp = RE_PortalUtils.getFullReapplyData(recordId);

        if (currReapp == null) {
            return;
        }

        RE_ResponseWrapper.FullReapplyDataWrapper wrap =
            new RE_ResponseWrapper.FullReapplyDataWrapper(currReapp, false);

        Map<String, Object> result = new Map<String, Object>();
        result.put('application', wrap);

        List<ContentDocumentLink> reapplyDocuments = [
            SELECT
                ContentDocumentId,
                ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
            AND ContentDocument.Title LIKE '%_CF083%'
        ];

        HttpRequest request = new HttpRequest();
        request.setEndpoint(REAPPLY_FORM_URL);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json;charset=UTF-8');
        request.setBody(JSON.serialize(result));

        Http http = new Http();
        HttpResponse response = http.send(request);

        String fileName =
            currReapp.First_Name__c + '_' +
            currReapp.Second_Name__c + '_' +
            currReapp.Name + '_CF083';

        if (
            response.getStatusCode() >= 200 &&
            response.getStatusCode() < 300 &&
            !Test.isRunningTest()
        ) {
            if (!reapplyDocuments.isEmpty()) {
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
     * IMPORTANT:
     * We do not use JSON.deserialize() here because the response
     * contains a very large Base64 PDF and can cause:
     * System.LimitException: Regex too complicated
     *
     * SOLUTION 3:
     * The ContentVersion insert is executed with AccessLevel.SYSTEM_MODE
     * so it succeeds even when the running user does not own the
     * ContentDocument (the file is typically owned by "XtraPension Admin"
     * and shared with the running user as Viewer only).
     * Without SYSTEM_MODE this insert fails with:
     *   INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY
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

        ContentVersion newVersion = new ContentVersion();
        newVersion.ContentDocumentId = reappDocs[0].ContentDocumentId;
        newVersion.VersionData       = EncodingUtil.base64Decode(base64);
        newVersion.PathOnClient      = fileName + '.' + fileType;
        newVersion.Title             = fileName;

        // ✅ SOLUTION 3 — insert as SYSTEM so file-sharing rules don't block
        Database.SaveResult sr = Database.insert(newVersion, AccessLevel.SYSTEM_MODE);

        if (!sr.isSuccess()) {
            String errMsg = '';
            for (Database.Error err : sr.getErrors()) {
                errMsg += err.getStatusCode() + ': ' + err.getMessage() + ' | ';
            }
            throw new DmlException('Failed to create ContentVersion (updateDocumentVersion): ' + errMsg);
        }
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

    /**
     * SOLUTION 3:
     * Uses Database.insert(..., AccessLevel.SYSTEM_MODE) so the insert
     * is not blocked by ContentDocumentLink / ContentWorkspace sharing rules.
     */
    public static ContentVersion createContentVersion(
        String base64,
        String fileName,
        String fileType
    ) {
        ContentVersion contentVersion = new ContentVersion();

        contentVersion.VersionData =
            EncodingUtil.base64Decode(base64);
        contentVersion.ContentLocation = 'S';
        contentVersion.Title = fileName;
        contentVersion.PathOnClient =
            fileName + '.' + fileType;

        // ✅ SOLUTION 3 — insert as SYSTEM
        Database.SaveResult sr =
            Database.insert(contentVersion, AccessLevel.SYSTEM_MODE);

        if (!sr.isSuccess()) {
            String errMsg = '';
            for (Database.Error err : sr.getErrors()) {
                errMsg += err.getStatusCode() + ': ' + err.getMessage() + ' | ';
            }
            throw new DmlException('Failed to create ContentVersion (createContentVersion): ' + errMsg);
        }

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
        contentDocumentLink.Visibility = 'AllUsers';

        insert contentDocumentLink;

        return contentDocumentLink;
    }
}