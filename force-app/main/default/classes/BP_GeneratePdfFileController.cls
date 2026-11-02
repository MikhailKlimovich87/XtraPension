public with sharing class BP_GeneratePdfFileController {

    public static final String FILL_FROM_URL = XtraPension_Data__c.getInstance().BP_Pdf_File_Link__c;
    public static final String FILL_IPC1394_URL = XtraPension_Data__c.getInstance().BP_Pdf_File_IPC1394_Link__c;
    public static final String FILL_FROM_URL_SIGNATURE = XtraPension_Data__c.getInstance().BP_PDF_IPCBR1_Wet__c;
    public static final String FILL_IPC1394_URL_SIGNATURE = XtraPension_Data__c.getInstance().BP_PDF_IPC1394_Wet__c;


    @AuraEnabled(cacheable=false)
    public static Map<String,Object> getApplication(String recordId) {
        Map<String, Object> result = new Map<String, Object>();
        Map<String, Object> resultBR = new Map<String, Object>();
        BP_ResponseWrappers.ApplicationDataWrapper wrap = new BP_ResponseWrappers.ApplicationDataWrapper(BP_PortalUtils.getApplication(recordId));
        BP_BR1_Wrapper.ApplicationDataWrapper wrapforBR = new BP_BR1_Wrapper.ApplicationDataWrapper(BP_PortalUtils.getApplication(recordId)[0]);
        BP_IPC1394_Wrapper.ApplicationDataWrapper wrapforIPC = new BP_IPC1394_Wrapper.ApplicationDataWrapper(BP_PortalUtils.getApplication(recordId)[0]);
        result.put(
            'application',
            wrapforIPC
        );
        resultBR.put(
            'application',
            wrapforBR
        );
        List<ContentDocumentLink> IPCBR1 =[
            SELECT
                ContentDocumentId,
                ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId AND
                    ContentDocument.Title LIKE '%_IPCBR1%'
                     AND (NOT ContentDocument.Title LIKE '%IPCBR1_Wet_Signature')
        ];
        List<ContentDocumentLink> IPC1394 =[
            SELECT
                ContentDocumentId,
                ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId AND
                    ContentDocument.Title LIKE '%_IPC1394%'
                     AND (NOT ContentDocument.Title LIKE '%IPC1394_Wet_Signature')
                      AND (NOT ContentDocument.Title LIKE '%Payment_Notes')
        ];

        BP_PdfServiceClient.Result response = BP_PdfServiceClient.post('BR1', FILL_FROM_URL, resultBR);
        BP_PdfServiceClient.Result responseIPC = BP_PdfServiceClient.post('IPC1394', FILL_IPC1394_URL, result);
        result.put(
            'Status BR1 ' + response.statusCode,
           new ResultWrapper(response.body)
        );
        result.put(
            'Status IPC ' + responseIPC.statusCode,
           new ResultWrapper(responseIPC.body)
        );
        String fileName = '';
        if(String.isNotBlank(wrap?.client?.firstName)) {
            fileName = fileName + wrap?.client?.firstName;
        }
        if(String.isNotBlank(wrap?.client?.lastName)) {
            fileName = fileName + ' ' + wrap?.client?.lastName;
        }
        if(String.isNotBlank(wrap?.name)) {
             fileName = fileName + '_' + wrap?.name;
        }
        String fileNameForm = fileName + '_IPCBR1' ;
        String fileNameIPC = fileName + '_IPC1394' ;
        

        if(response.success) {
            if (IPCBR1.size() != 0) {
                updateDocumentVersion(response.body,fileNameForm, 'pdf',  IPCBR1);
            } else {
                generateDocument(response.body, recordId, fileNameForm);
            }
            
        }
         if(responseIPC.success) {
            
            if (IPC1394.size() != 0) {
                updateDocumentVersion(responseIPC.body,fileNameIPC, 'pdf',  IPC1394);
            } else {
                generateDocument(responseIPC.body,recordId, fileNameIPC);
            }
        }
        reportFailures(recordId, new List<BP_PdfServiceClient.Result>{ response, responseIPC });
        return result;
    }

    @AuraEnabled(cacheable=false)
    public static Map<String,Object> generateSignature(String recordId) {
        Map<String, Object> result = new Map<String, Object>();
        Map<String, Object> wrapSignBr = new Map<String, Object>();
        BP_ResponseWrappers.ApplicationDataWrapper wrap = new BP_ResponseWrappers.ApplicationDataWrapper(BP_PortalUtils.getApplication(recordId));
        BP_BR1_Wet_Wrapper.ApplicationDataWrapper wrapSign = new BP_BR1_Wet_Wrapper.ApplicationDataWrapper(BP_PortalUtils.getApplication(recordId)[0]);
        result.put(
            'application',
            wrap
        );
         wrapSignBr.put(
            'application',
            wrapSign
        );

         List<ContentDocumentLink> IPCBR1 =[
            SELECT
                ContentDocumentId,
                ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId AND
                    ContentDocument.Title LIKE '%IPCBR1_Wet_Signature'
        ];
        List<ContentDocumentLink> IPC1394 =[
            SELECT
                ContentDocumentId,
                ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId AND
                    ContentDocument.Title LIKE '%IPC1394_Wet_Signature'
        ];

        BP_PdfServiceClient.Result response = BP_PdfServiceClient.post('BR1 wet signature', FILL_FROM_URL_SIGNATURE, wrapSignBr);
        BP_PdfServiceClient.Result responseIPC = BP_PdfServiceClient.post('IPC1394 wet signature', FILL_IPC1394_URL_SIGNATURE, result);
        result.put(
            'Status BR1 ' + response.statusCode,
           new ResultWrapper(response.body)
        );
        result.put(
            'Status IPC ' + responseIPC.statusCode,
           new ResultWrapper(responseIPC.body)
        );
        String fileName = '';
        if(String.isNotBlank(wrap?.client?.firstName)) {
            fileName = fileName + wrap?.client?.firstName;
        }
        if(String.isNotBlank(wrap?.client?.lastName)) {
            fileName = fileName + ' ' + wrap?.client?.lastName;
        }
        String fileNameForm = fileName + '_'+ wrap?.name +  '_D5_IPCBR1_Wet_Signature' ;
        String fileNameIPC = fileName + '_'+ wrap?.name +  '_D4_IPC1394_Wet_Signature' ;
        
        if(response.success) {
            if (IPCBR1.size() != 0) {
                updateDocumentVersion(response.body,fileNameForm, 'pdf',  IPCBR1);
            } else {
                generateDocument(response.body, recordId, fileNameForm);
            }
            
            
        }
        if(responseIPC.success) {
             if (IPC1394.size() != 0) {
                updateDocumentVersion(responseIPC.body,fileNameIPC, 'pdf',  IPC1394);
            } else {
                generateDocument(responseIPC.body,recordId, fileNameIPC);
            }
        }
        reportFailures(recordId, new List<BP_PdfServiceClient.Result>{ response, responseIPC });
        return result;
    }

    // Interactive callers get the error (and the transaction rolls back, so nothing is half-saved);
    // background jobs have nobody to show it to, so it is logged instead.
    private static void reportFailures(Id recordId, List<BP_PdfServiceClient.Result> results) {
        String errors = BP_PdfServiceClient.joinErrors(results);
        if (String.isBlank(errors)) {
            return;
        }
        if (System.isQueueable() || System.isFuture() || System.isBatch() || System.isScheduled()) {
            BP_PdfServiceClient.logFailures(recordId, results);
            return;
        }
        AuraHandledException ex = new AuraHandledException(errors);
        ex.setMessage(errors);
        throw ex;
    }

    public static void generateDocument(String resultBody, String recordId, String fileName) {
        BP_RequestWrappers.UploadDocumentDataWrapper wrapper  = new BP_RequestWrappers.UploadDocumentDataWrapper(resultBody);
        if (String.isBlank(wrapper.base64) || String.isBlank(fileName)) {
                return;
        }
            ContentVersion contentVersion = BP_PortalUtils.createContentVersion(wrapper.base64, fileName, 'pdf');
            ContentDocumentLink cdl = BP_PortalUtils.createContentLink(contentVersion.Id, recordId);
    }

    public static void updateDocumentVersion(String resultBody, String fileName, String fileType, List<ContentDocumentLink> zipDoc) {
        BP_RequestWrappers.UploadDocumentDataWrapper wrapper  = new BP_RequestWrappers.UploadDocumentDataWrapper(resultBody);
        if (String.isBlank(wrapper.base64) || String.isBlank(fileName)) {
                return;
        }
        insert new ContentVersion (
                    Title = fileName,
                    ContentDocumentId = zipDoc[0].ContentDocumentId,
                    VersionData = EncodingUtil.base64Decode(wrapper.base64),
                    PathOnClient = fileName + '.' + fileType
        );
    }


    
    public class ResultWrapper {
        @AuraEnabled public String resultBody {get;set;}
        public ResultWrapper(String inputData) {
            this.resultBody = inputData;
        }
    }
}