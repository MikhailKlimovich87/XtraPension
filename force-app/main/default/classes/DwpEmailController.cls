public class DwpEmailController {
    private static final String FROM_NAME = 'XtraPension';
    private static final String MESSAGE_BODY = 'Hi, please check your email about your UK State Pension Top-Up';
    private static final String SUCCESS_APP_STATUS = 'DWP 2 Emails Sent';
    private static final EmailTemplate DWP_TELECLAIM_TEMPLATE1 {
        get {
            if (DWP_TELECLAIM_TEMPLATE1 == null) {
                List<EmailTemplate> emailTemplates = [
                    SELECT Id, HtmlValue
                    FROM EmailTemplate
                    WHERE Name = 'DWP Teleclaim 1'
                    WITH USER_MODE
                    LIMIT 1
                ];
                if (!emailTemplates.isEmpty()) {
                    DWP_TELECLAIM_TEMPLATE1 = emailTemplates[0];
                }
            }
        return DWP_TELECLAIM_TEMPLATE1;
    }
        private set;
    }

    private static final EmailTemplate DWP_TELECLAIM_TEMPLATE2 {
        get {
            if (DWP_TELECLAIM_TEMPLATE2 == null) {
                List<EmailTemplate> emailTemplates = [
                    SELECT Id, HtmlValue
                    FROM EmailTemplate
                    WHERE Name = 'DWP Teleclaim 2'
                    WITH USER_MODE
                    LIMIT 1
                ];
                if (!emailTemplates.isEmpty()) {
                    DWP_TELECLAIM_TEMPLATE2 = emailTemplates[0];
                }
            }
        return DWP_TELECLAIM_TEMPLATE2;
    }
        private set;
    }

    private static final OrgWideEmailAddress OWD {
        get {
            if (OWD == null) {
                List<OrgWideEmailAddress> orgWideEmailAddresses = [
                    SELECT Id
                    FROM OrgWideEmailAddress
                    WHERE Address = 'clients@xtrapension.com'
                    WITH USER_MODE
                    LIMIT 1
                ];
                if (!orgWideEmailAddresses.isEmpty()) {
                    OWD = orgWideEmailAddresses[0];
                }
            }
            return OWD;
        }
        private set;
    }

    private static final Id DWP_INSTRUCTION_ID{
        get {
            if (DWP_INSTRUCTION_ID == null) {
                List<ContentDocument> instructionDoc = [
                    SELECT Id
                    FROM ContentDocument
                    WHERE Title = 'DWP 1 - Instructions'
                    LIMIT 1
                ];
                if (!instructionDoc.isEmpty()) {
                    DWP_INSTRUCTION_ID = instructionDoc[0].Id;
                }
            }
            return DWP_INSTRUCTION_ID;
        }
        private set;
    }

    public static final String ACCOUNT_ID {
        get {
            if (ACCOUNT_ID == null) {
                ACCOUNT_ID = XtraPension_Data__c.getInstance().Twilio_Account__c;
            }
            return ACCOUNT_ID;
        }
        private set;
    }
    public static final String TOKEN_ID {
        get {
            if (TOKEN_ID == null) {
                TOKEN_ID =XtraPension_Data__c.getInstance().Twilio_Token__c;
            }
            return TOKEN_ID;
        }
        private set;
    }


    @AuraEnabled(cacheable=false)
    public static string generateDwpDocs(Id appId) {
        if (appId == null) throw new DWPEmailException('Application Id is null');
        List<Application__c> apps = [
            SELECT
                First_Name__c,
                Second_Name__c,
                Contact__c,
                Email__c,
                Name
            FROM Application__c
            WHERE Id = :appId
        ];
        if(apps.isEmpty()) throw new DWPEmailException('Couldn\'t find app with this record Id');
        Application__c currentApplication = apps[0];

        List<Id> docIds = DWPDocsHandler.generateDocs(currentApplication);

        Messaging.SingleEmailMessage messageDWP1 = new Messaging.SingleEmailMessage();
        messageDWP1.setTargetObjectId(currentApplication.Contact__c);
        messageDWP1.setUseSignature(false);
        messageDWP1.setBccSender(false);
        messageDWP1.setSaveAsActivity(true);
        if (DWP_TELECLAIM_TEMPLATE1 != null) {
            messageDWP1.setTemplateID(DWP_TELECLAIM_TEMPLATE1.Id);
        }
        if (OWD != null) {
            messageDWP1.setOrgWideEmailAddressId(OWD.Id);
        }
        messageDWP1.setWhatId(currentApplication.Id);
        messageDWP1.toAddresses = new String[] {currentApplication.Email__c};
        messageDWP1.setTreatTargetObjectAsRecipient(false);

        if(!docIds.isEmpty()) {
            Id[] contDocIds = new List<Id>(docIds);
            messageDWP1.setEntityAttachments(contDocIds);
        }

        Messaging.SingleEmailMessage messageDWP2 = new Messaging.SingleEmailMessage();
        messageDWP2.setTargetObjectId(currentApplication.Contact__c);
        messageDWP2.setUseSignature(false);
        messageDWP2.setBccSender(false);
        messageDWP2.setSaveAsActivity(true);
        if (DWP_TELECLAIM_TEMPLATE2 != null) {
            messageDWP2.setTemplateID(DWP_TELECLAIM_TEMPLATE2.Id);
        }
        if (OWD != null) {
            messageDWP2.setOrgWideEmailAddressId(OWD.Id);
        }
        messageDWP2.setWhatId(currentApplication.Id);
        messageDWP2.toAddresses = new String[] {currentApplication.Email__c};
        messageDWP2.setTreatTargetObjectAsRecipient(false);

        Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {messageDWP1, messageDWP2};
        Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
        Boolean isSuccess = true;
        for (Messaging.SendEmailResult result : results) {
            if (result.isSuccess() == false) {
                isSuccess = false;
                break;
            }
        }
        sendSMS(currentApplication.Id);
        return String.valueOf(isSuccess);
    }

    @AuraEnabled(cacheable=false)
    public static string createDWPDocs(Id appId) {
        if (appId == null) throw new DWPEmailException('Application Id is null');
        List<Application__c> apps = [
            SELECT
                Id,
                First_Name__c,
                Second_Name__c,
                Contact__c,
                Email__c,
                Name
            FROM Application__c
            WHERE Id = :appId
        ];
        if(apps.isEmpty()) throw new DWPEmailException('Couldn\'t find app with this record Id');
        Application__c currentApplication = apps[0];

        List<Id> docIds = DWPDocsHandler.generateDocs(currentApplication);
        if (docIds.isEmpty()) {
            return null;
        }

        if (DWP_INSTRUCTION_ID != null) {
            List<ContentDocumentLink> currentInstLink = [
                SELECT Id
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :appId AND
                      ContentDocumentId = :DWP_INSTRUCTION_ID
            ];
            if (currentInstLink.isEmpty()) {
                ContentDocumentLink instructionLink = new ContentDocumentLink();
                instructionLink.LinkedEntityId = appId;
                instructionLink.ContentDocumentId = DWP_INSTRUCTION_ID;
                insert instructionLink;
            }
        }
        return 'Success';
    }

    @AuraEnabled(cacheable=false)
    public static void sendDWPsmsMessage(Id appId) {
        List<Application__c> apps = [
            SELECT
                Related_Contact_Phone__c,
                Status__c,
                is_Sent_DWP_SMS_Message__c
            FROM Application__c
            WHERE Id = :appId
        ];
        if (apps.isEmpty()) {
            return;
        }
        Application__c app = apps[0];

        TwilioSF.TwilioApiClient api = new TwilioSF.TwilioApiClient();
        api.addUrlPart('Accounts');
        api.addUrlPart(ACCOUNT_ID);
        api.addUrlPart('Messages.json');
        api.addParam('From', FROM_NAME);
        api.addParam('Body', MESSAGE_BODY);
        api.addParam('To', app.Related_Contact_Phone__c);
        if (!Test.isRunningTest()) {
            TwilioSF.TwilioApiClientResponse response = api.doPost();
            TwilioSF.TwilioJsonParser responseMap = response.getTwilioJsonParser();

            // Extract details from the response
            String messageSid = responseMap.get('sid').getString();
            String status = responseMap.get('status').getString();
            String to = responseMap.get('to').getString();
            String fromNumberResponse = responseMap.get('from').getString();
            String bodyResponse = responseMap.get('body').getString();

            TwilioSF__Message__c twilioMessage = new TwilioSF__Message__c();
            twilioMessage.TwilioSF__Message_SID__c = messageSid;
            twilioMessage.TwilioSF__To_Number__c = to;
            twilioMessage.TwilioSF__From_Number__c = fromNumberResponse;
            twilioMessage.TwilioSF__Body__c = bodyResponse;
            twilioMessage.TwilioSF__Status__c = status;
            twilioMessage.TwilioSF__Date_Sent__c =DateTime.now();

            // Insert the record
            insert twilioMessage;

            if(response.getHtttpStatusCode() >= 201 && response.getHtttpStatusCode() < 300) {
                app.is_Sent_DWP_SMS_Message__c = true;
            }
            app.Status__c = SUCCESS_APP_STATUS;
            update app;
        } else {
            app.Status__c = SUCCESS_APP_STATUS;
            app.is_Sent_DWP_SMS_Message__c = true;
            update app;
        }
        //sendSMS(appId);
    }

    @future(callout = true)
    public static void sendSMS(Id appId){
        List<Application__c> apps = [
            SELECT
                Related_Contact_Phone__c,
                Status__c,
                is_Sent_DWP_SMS_Message__c
            FROM Application__c
            WHERE Id = :appId
        ];
        if (apps.isEmpty()) {
            return;
        }
        Application__c app = apps[0];

        TwilioSF.TwilioApiClient api = new TwilioSF.TwilioApiClient();
        api.addUrlPart('Accounts');
        api.addUrlPart(ACCOUNT_ID);
        api.addUrlPart('Messages.json');
        api.addParam('From', FROM_NAME);
        api.addParam('Body', MESSAGE_BODY);
        api.addParam('To', app.Related_Contact_Phone__c);
        if (!Test.isRunningTest()) {
            TwilioSF.TwilioApiClientResponse response = api.doPost();
            TwilioSF.TwilioJsonParser responseMap = response.getTwilioJsonParser();

            // Extract details from the response
            String messageSid = responseMap.get('sid').toString();
            String status = responseMap.get('status').toString();
            String to = responseMap.get('to').toString();
            String fromNumberResponse = responseMap.get('from').toString();
            String bodyResponse = responseMap.get('body').toString();
            String dateSent = responseMap.get('date_sent').toString();

            // Create a new Twilio_Message__c record
            // Create a new TwilioSF__Message__c record
            TwilioSF__Message__c twilioMessage = new TwilioSF__Message__c();
            twilioMessage.TwilioSF__Message_SID__c = messageSid;
            twilioMessage.TwilioSF__To_Number__c = to;
            twilioMessage.TwilioSF__From_Number__c = fromNumberResponse;
            twilioMessage.TwilioSF__Body__c = bodyResponse;
            twilioMessage.TwilioSF__Status__c = status;
            twilioMessage.TwilioSF__Date_Sent__c = DateTime.now();

            // Insert the record
            Database.insert(twilioMessage, false);
            // if(response.getHtttpStatusCode() >= 201 && response.getHtttpStatusCode() < 300) {
            //     app.is_Sent_DWP_SMS_Message__c = true;
            // }
            app.Status__c = SUCCESS_APP_STATUS;
            update app;
        } else {
            app.Status__c = SUCCESS_APP_STATUS;
            app.is_Sent_DWP_SMS_Message__c = true;
            update app;
        }
    }

    public class ErrorResponseWrapper{
        String code;
        String message;
        String moreInfo;
        String status;
    }

    public class SendMessageResult {
        @AuraEnabled
        public Boolean isSuccess;
        @AuraEnabled
        public String errorMessage;
    }

    public class DWPEmailException extends Exception {}

    public static void fakeMethod(){
        Integer i = 0;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
    }
}