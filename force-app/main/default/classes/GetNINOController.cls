public class GetNINOController {
    @AuraEnabled(cacheable = true)
    public static NINODataResult getApplicationData(String recordId) {
        NINODataResult result = new NINODataResult();
        if (recordId != null) {
            List<Application__c> currentApps = [
                SELECT
                    JR_Posted_2_Env_s__c,
                    Env_A_Number__c,
                    Env_B_Number__c,
                    Envelop_A__c,
                    Envelop_B__c,
                    Envelop_A_Date__c,
                    Envelop_B_Date__c,
                    Posted_Env_A__c,
                    Posted_Env_B__c,
                    Salutation__c,
                    First_Name__c,
                    Second_Name__c,
                    Current_Address_Abroad__Street__s,
                    Current_Address_Abroad__City__s,
                    Current_Address_Abroad_State__c,
                    Current_Address_Abroad__PostalCode__s,
                    Current_Address_Abroad_Country__c
                FROM Application__c
                WHERE Id = :recordId
            ];
            if (!currentApps.isEmpty()) {
                result.isSuccess   = true;
                result.application = currentApps[0];
                return result;
            } else {
                result.isSuccess = false;
                result.errorMessage = 'Not exist app with this record Id ';
            }
        } else {
            result.isSuccess = false;
            result.errorMessage = 'RecordId is null';
        }
        return result;
    }

    @AuraEnabled(cacheable = false)
    public static NINODataResult saveNINOEnvelopsData(NINOSaveData data) {
        NINODataResult result = new NINODataResult();
        if (data.applicationId != null) {
            Application__c currentApp = new Application__c(
                Id = data?.applicationId,
                JR_Posted_2_Env_s__c = data?.posted2Envs,
                Envelop_A__c = data?.envelopA,
                Envelop_B__c = data?.envelopB,
                Envelop_A_Date__c = data?.dateEnvelopA,
                Envelop_B_Date__c = data?.dateEnvelopB,
                Posted_Env_A__c = data?.postedEnvelopA,
                Posted_Env_B__c = data?.postedEnvelopB
            );
            try {
                Database.SaveResult updateData = Database.update(currentApp);
                result.isSuccess = true;
                result.application = currentApp;
            } catch (Exception ex) {
                result.isSuccess = false;
                result.application = currentApp;
                result.errorMessage = ex.getLineNumber() + ' - ' + ex.getMessage();
                return result;
            }
        } else {
            result.isSuccess = false;
            result.errorMessage = 'Application Id is null.';
        }
        return result;
    }

    @AuraEnabled
    public static NINODataResult generateGetNINOFile(String applicationId) {
        NINODataResult result = new NINODataResult();
        if (applicationId == null) {
            result.isSuccess = false;
            result.errorMessage = 'applicationId is null';
            return result;
        }
        List<Application__c> apps = [
            SELECT
                Name,
                First_Name__c,
                Second_Name__c
            FROM Application__c
            WHERE Id = :applicationId
        ];
        if (apps.isEmpty()) {
            result.isSuccess = false;
            result.errorMessage = 'Didn\'t find application';
            return result;
        }
        Application__c currentApp = apps[0];
        PageReference savepage ;
        savepage = Page.NINOData;
        savepage.getParameters().put('id', applicationId);
        blob pdfBlob;
        if (!Test.isRunningTest()) {
            pdfBlob = savepage.getContent();
        } else {
            pdfBlob = Blob.valueOf('Test');
        }
        List<ContentDocumentLink> oldDocuments = [
            SELECT
                ContentDocument.Id,
                ContentDocument.Title,
                LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocument.Title LIKE '%CA5403%' AND 
                  LinkedEntityId = :applicationId
        ];
        if (oldDocuments.isEmpty()) {
            String FinalTitle = currentApp.First_Name__c + '_' + currentApp.Second_Name__c + '_' + currentApp.Name +'_CA5403';

		    ContentVersion conVer = new ContentVersion();
		    conVer.ContentLocation = 'S';
		    conVer.PathOnClient = FinalTitle+'.pdf';
		    conVer.Title = FinalTitle;
		    conVer.VersionData = pdfBlob;
		    insert conVer;

		    ContentVersion conDoc = [SELECT ContentDocumentId, ContentSize FROM ContentVersion WHERE Id =:conVer.Id][0];

		    ContentDocumentLink conDocLink = new ContentDocumentLink();
		    conDocLink.LinkedEntityId = applicationId;
		    conDocLink.ContentDocumentId = conDoc.ContentDocumentId;
		    conDocLink.shareType = 'V';
            conDocLink.Visibility = 'AllUsers';
		    insert conDocLink;
            result.isSuccess = true;
            return result;
        } else {
            ContentDocumentLink caDocLink = oldDocuments[0];
            ContentVersion conVer = new ContentVersion();
		    conVer.ContentLocation = 'S';
		    conVer.PathOnClient = caDocLink.ContentDocument.Title+'.pdf';
		    conVer.Title = caDocLink.ContentDocument.Title;
		    conVer.VersionData = pdfBlob;
            conVer.ContentDocumentId = caDocLink.ContentDocument.Id;
		    insert conVer;
            result.isSuccess = true;
            return result;
        }
    }

    public class NINODataResult {
        @AuraEnabled
        public Boolean isSuccess{get; set;}
        @AuraEnabled
        public Application__c application{get; set;}
        @AuraEnabled
        public String errorMessage{get; set;}
    }

    public class NINOSaveData {
        @AuraEnabled
        public String applicationId{get; set;}
        @AuraEnabled
        public String posted2Envs{get; set;}
        @AuraEnabled
        public String envelopA{get; set;}
        @AuraEnabled
        public String envelopB{get; set;}
        @AuraEnabled
        public String postedEnvelopA{get; set;}
        @AuraEnabled
        public String postedEnvelopB{get; set;}
        @AuraEnabled
        public Date dateEnvelopA{get; set;}
        @AuraEnabled
        public Date dateEnvelopB{get; set;}
    }
}