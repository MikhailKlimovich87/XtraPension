public with sharing class BP_GenerateApplication_BR1 {
    public static final String FILL_FROM_URL = XtraPension_Data__c.getInstance().BP_Pdf_File_Link__c;
    public class Request {
        @InvocableVariable(required=true)
        public Id recordId;
    }

    @InvocableMethod(label='Generate Application BR1')
    public static void generate(List<Request> requests) {
        for (Request request : requests) {
            getApplication_BR1((String)request.recordId);
        }
    }

    @future(callout=true)
    public static void getApplication_BR1(String recordId) {
        Map<String, Object> result = new Map<String, Object>();
        BP_BR1_Wrapper.ApplicationDataWrapper wrap = new BP_BR1_Wrapper.ApplicationDataWrapper(BP_PortalUtils.getApplication(recordId)[0]);
        result.put(
            'application',
            wrap
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
        BP_PdfServiceClient.Result response = BP_PdfServiceClient.post('BR1', FILL_FROM_URL, result);

        String fileName = '';
        if(String.isNotBlank(wrap?.q2)) {
            fileName = fileName + wrap?.q2;
        }
        if(String.isNotBlank(wrap?.q4)) {
            fileName = fileName + ' ' + wrap?.q4;
        }
        if(String.isNotBlank(wrap?.name)) {
             fileName = fileName + '_' + wrap?.name;
        }
        String fileNameIPC = fileName + '_D5_IPCBR1' ;

        if(!response.success) {
            BP_PdfServiceClient.logFailures(recordId, new List<BP_PdfServiceClient.Result>{ response });
            return;
        }
        if(!Test.isRunningTest()) {
            updateCodesBR(wrap, recordId);
            if (IPCBR1.size() != 0) {
                BP_GeneratePdfFileController.updateDocumentVersion(response.body,fileNameIPC, 'pdf',  IPCBR1);
            } else {
                BP_GeneratePdfFileController.generateDocument(response.body,recordId, fileNameIPC);
            }
            buildFullFormZipIfSigned(recordId);
        }
    }

    // The full-form ZIP sent to WDM must contain the BR1 that carries the DocuSign date, so it is built here,
    // right after the regenerated BR1 has been saved, and not when the status changes.
    public static void buildFullFormZipIfSigned(Id recordId) {
        List<Basic__c> claims = [SELECT Status__c FROM Basic__c WHERE Id = :recordId LIMIT 1];
        if (claims.isEmpty() || claims[0].Status__c != BP_DocuSignController.STATUS_SIGNED_WAITING_DOCS) {
            return;
        }
        BP_PortalUtils.generateZipArchiveFullFormClaim(recordId);
    }

    // public static void updateCodes(BP_BR1_Wrapper.ApplicationDataWrapper wrap) {     

    //     update  new Basic__c (
    //         Id = wrap.applicationId,
    //         Current_Address_Abroad_State__c = CountryCodeHelper.getCountryStateISOByName(wrap?.stateName),           
    //         Current_Address_Abroad_Country__c = CountryCodeHelper.getCountryIsoCodeByCountryName(wrap?.countryName),
    //         Partner_Country_Code__c = CountryCodeHelper.getCountryIsoCodeByCountryName(wrap?.partnerCountryName)
    //     ); 
    //     if(wrap?.contryLivedList != null && wrap?.contryLivedList.size()>0) {
    //         List<Claimant_Country_lived__c> countryLivedToUpdate = new List<Claimant_Country_lived__c>();

    //         for(Claimant_Country_lived__c item : wrap?.contryLivedList)  {
    //             countryLivedToUpdate.add(new Claimant_Country_lived__c(Id = item.recordId, Country_Type__c = CountryCodeHelper.getCountryIsoCodeByCountryName(item?.countryName)));
    //         }

    //         if(countryLivedToUpdate.size()>0) {
    //             update countryLivedToUpdate;
    //         }
    //     } 
    // }

    public static void updateCodesBR(BP_BR1_Wrapper.ApplicationDataWrapper wrap, String recordId) {     

        update  new Basic__c (
            Id = recordId,
            Partner_State_Code__c = CountryCodeHelper.getCountryStateISOByName(wrap?.partnerStateName),
            Current_Address_Abroad_State__c = CountryCodeHelper.getCountryStateISOByName(wrap?.stateName),           
            Current_Address_Abroad_Country__c = CountryCodeHelper.getCountryIsoCodeByCountryName(wrap?.countryName),
            Partner_Country_Code__c = CountryCodeHelper.getCountryIsoCodeByCountryName(wrap?.partnerCountryName)
        ); 
       if(wrap?.contryLivedList != null && wrap?.contryLivedList.size()>0) {
            List<Claimant_Country_lived__c> countryLivedToUpdate = new List<Claimant_Country_lived__c>();

            for(Claimant_Country_lived__c item : wrap?.contryLivedList)  {
                countryLivedToUpdate.add(new Claimant_Country_lived__c(Id = item.Id, Country_Type__c = CountryCodeHelper.getCountryIsoCodeByCountryName(item?.Name)));
            }

            if(countryLivedToUpdate.size()>0) {
                update countryLivedToUpdate;
            }
        } 
    }
}