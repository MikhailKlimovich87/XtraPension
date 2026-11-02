public with sharing class BP_GenerateApplication1394 {
    public static final String FILL_IPC1394_URL = XtraPension_Data__c.getInstance().BP_Pdf_File_IPC1394_Link__c;
    public class Request {
        @InvocableVariable(required=true)
        public Id recordId;
    }

    @InvocableMethod(label='Generate Application 1394')
    public static void generate(List<Request> requests) {
        for (Request request : requests) {
            getApplication_1394((String)request.recordId);
        }
    }

    @future(callout=true)
    public static void getApplication_1394(String recordId) {
        Map<String, Object> result = new Map<String, Object>();
        BP_ResponseWrappers.ApplicationDataWrapper wrap = new BP_ResponseWrappers.ApplicationDataWrapper(BP_PortalUtils.getApplication(recordId));
        BP_IPC1394_Wrapper.ApplicationDataWrapper wrapRec = new BP_IPC1394_Wrapper.ApplicationDataWrapper(BP_PortalUtils.getApplication(recordId)[0]);
        result.put(
            'application',
            wrapRec
        );
        List<ContentDocumentLink> IPC1394 = [
            SELECT
                ContentDocumentId,
                ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
                AND ContentDocument.Title LIKE '%_IPC1394%'
                AND (NOT ContentDocument.Title LIKE '%IPC1394_Wet_Signature')
                AND (NOT ContentDocument.Title LIKE '%Payment_Notes')
        ];
        BP_PdfServiceClient.Result response = BP_PdfServiceClient.post('IPC1394', FILL_IPC1394_URL, result);

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
        String fileNameIPC = fileName + '_D4_IPC1394' ;

        if(!response.success) {
            BP_PdfServiceClient.logFailures(recordId, new List<BP_PdfServiceClient.Result>{ response });
            return;
        }
        if(!Test.isRunningTest()) {
            updateCodes(wrap);
            if (IPC1394.size() != 0) {
                BP_GeneratePdfFileController.updateDocumentVersion(response.body,fileNameIPC, 'pdf',  IPC1394);
            } else {
                BP_GeneratePdfFileController.generateDocument(response.body,recordId, fileNameIPC);
            }
        }
    }

    public static void updateCodes(BP_ResponseWrappers.ApplicationDataWrapper wrap) {
        update  new Basic__c (
            Id = wrap.applicationId,
            Partner_State_Code__c = CountryCodeHelper.getCountryStateISOByName(wrap?.partner?.stateName),
            Current_Address_Abroad_State__c = CountryCodeHelper.getCountryStateISOByName(wrap?.client?.address?.stateName),
            Current_Address_Abroad_Country__c = CountryCodeHelper.getCountryIsoCodeByCountryName(wrap?.claimant?.countryName),
            Bank_Country_Code__c = CountryCodeHelper.getCountryIsoCodeByCountryName(wrap?.bank?.countryName)
        );  
    }
}