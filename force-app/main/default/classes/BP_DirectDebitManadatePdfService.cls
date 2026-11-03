public class BP_DirectDebitManadatePdfService {
    public static final String DD_MANDATE_PDF_URL = XtraPension_Data__c.getInstance().BP_DD_Mandate_Pdf_File_Link__c;
    public static final String DD_MANDATE_AUSTRALIA_PDF_URL = XtraPension_Data__c.getInstance().BP_DD_Mandate_Australia_Pdf_File_Link__c;


    public static void generatePdf(Id basicId) {
        if (basicId == null) return;
        List<Basic__c> basics = BP_PortalUtils.getDDMandateBasicData(basicId);
        if (basics.size() == 0)  return;
        Basic__c currBasic = basics[0];

        BP_RequestWrappers.DDMandateDataWrapper wrap =
            new BP_RequestWrappers.DDMandateDataWrapper(currBasic);

        List<ContentDocumentLink> mandateDocs =[
            SELECT
                ContentDocumentId,
                ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :basicId AND
                    ContentDocument.Title LIKE '%ddMandate%' AND
                    (NOT ContentDocument.Title LIKE '%completed%')
            ORDER BY ContentDocument.CreatedDate DESC
        ];
        
        Map<String, Object> result = new Map<String, Object>();
        result.put('claim', wrap);

        String endpoint;
        if (currBasic.CurrencyIsoCode == 'EUR') {
            endpoint = DD_MANDATE_PDF_URL;
        } else if (currBasic.CurrencyIsoCode == 'AUD') {
            endpoint = DD_MANDATE_AUSTRALIA_PDF_URL;
        } else return;

        BP_PdfServiceClient.Result response = BP_PdfServiceClient.post('ddMandate', endpoint, result);
        
        String fileName =
            currBasic.First_Name__c + '_' +
            currBasic.Last_Name__c + '_' +
            currBasic.Name + '_ddMandate';
        if (!response.success) {
            BP_PdfServiceClient.logFailures(basicId, new List<BP_PdfServiceClient.Result>{ response });
            return;
        }
        if (!Test.isRunningTest()) {
            if (mandateDocs.size() > 0) {
                updateDocumentVersion(
                    response.body,
                    fileName,
                    'pdf',
                    mandateDocs
                );
            } else {
                generateDocument(
                    response.body,
                    basicId,
                    fileName
                );
            }
        }
    }

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
            PathOnClient = fileName + '.' + fileType
        );
    }

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
        contentVersion.PathOnClient = fileName + '.' + fileType;
        
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