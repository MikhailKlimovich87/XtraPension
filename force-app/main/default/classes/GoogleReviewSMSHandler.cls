public class GoogleReviewSMSHandler {
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
    public static final String MESSAGE_BODY {
        get {
            if (MESSAGE_BODY == null) {
                MESSAGE_BODY =XtraPension_Data__c.getInstance().Google_Review_Message_Body__c;
            }
            return MESSAGE_BODY;
        }
        private set;
    }
    private static final EmailTemplate GOOGLE_REVIEW_TEMPLATE {
        get {
            if (GOOGLE_REVIEW_TEMPLATE == null) {
                List<EmailTemplate> emailTemplates = [
                    SELECT Id, Subject, Body
                    FROM EmailTemplate
                    WHERE DeveloperName = 'Google_Review'
                    WITH USER_MODE
                    LIMIT 1
                ];

                if (!emailTemplates.isEmpty()) {
                    GOOGLE_REVIEW_TEMPLATE = emailTemplates[0];
                }
            }
            return GOOGLE_REVIEW_TEMPLATE;
        }
        private set;
    }
    private static final OrgWideEmailAddress DEFAULT_ORG_WIDE_EMAIL_ADDRESS {
        get {
            if (DEFAULT_ORG_WIDE_EMAIL_ADDRESS == null) {
                List<OrgWideEmailAddress> orgWideEmailAddresses = [
                    SELECT Id, Address, DisplayName
                    FROM OrgWideEmailAddress
                    WHERE Address = 'clients@xtrapension.com'
                    WITH USER_MODE
                    LIMIT 1
                ];

                if (!orgWideEmailAddresses.isEmpty()) {
                    DEFAULT_ORG_WIDE_EMAIL_ADDRESS = orgWideEmailAddresses[0];
                }
            }
            return DEFAULT_ORG_WIDE_EMAIL_ADDRESS;
        }
        private set;
    }
    public static final String FROM_NAME = 'XtraPension';


    public static void sendGoogleReviewSMS() {
        Date todayDate = Date.today();
        for (Application__c app : [
            SELECT
                Id,
                Send_Google_Review_SMS__c,
                Google_Review_Send_Date__c,
                Google_Review_Send_Email_Date_1__c,
                Google_Review_Send_Email_Date_2__c
            FROM Application__c
            WHERE
                ((Send_Google_Review_SMS__c = true AND
                Google_Review_Send_Date__c = :todayDate) OR
                Google_Review_Send_Email_Date_1__c = :todayDate OR
                Google_Review_Send_Email_Date_2__c = :todayDate) AND
                Related_Contact_Phone__c != null
        ]) {
            if (app.Send_Google_Review_SMS__c == true && app.Google_Review_Send_Date__c == todayDate) {
                sendSMS(app.Id);
            }
            if (app.Google_Review_Send_Email_Date_1__c == todayDate || app.Google_Review_Send_Email_Date_2__c == todayDate) {
                sendEmail(app.Id);
            }
        }
    }

    @future(callout=true)
    private static void sendSMS(Id appId) {
        List<Application__c> apps = [
            SELECT Related_Contact_Phone__c
            FROM Application__c
            WHERE Id = :appId
        ];
        if (apps.isEmpty()) {
            return;
        }
        Application__c app = apps[0];
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.twilio.com/2010-04-01/Accounts/' + ACCOUNT_ID + '/Messages');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        Blob headerValue = Blob.valueOf(ACCOUNT_ID + ':' + TOKEN_ID);
        String authorizationHeader = 'BASIC ' + EncodingUtil.base64Encode(headerValue);
        req.setHeader('Authorization', authorizationHeader);
        req.setBody('To=' + EncodingUtil.urlEncode(app.Related_Contact_Phone__c,'UTF-8') + '&From=' + FROM_NAME + '&Body=' + MESSAGE_BODY);
        try {
            Http http = new Http();
            HTTPResponse res = http.send(req);
            if(res.getStatusCode() == 201) {
                System.debug('Twilio Success = ' + app.Related_Contact_Phone__c);
                System.debug('body === ' + res.getBody());
            } 
            else {
                System.debug('body === ' + res.getBody());
                System.debug('Twilio failed:' + app.Related_Contact_Phone__c);
                ErrorResponseWrapper erw =(ErrorResponseWrapper)json.deserialize(res.getBody(), ErrorResponseWrapper.class);
                System.debug('wilio error:' + erw.message);
            }
        } catch(Exception ex) {
            System.debug('Error message = ' + ex.getMessage());
        }
    }

    @future(callout=true)
    private static void sendEmail(Id appId) {
        List<Application__c> apps = [
            SELECT
                Id,
                Contact__c,
                Email__c
            FROM Application__c
            WHERE Id = :appId
        ];
        if (apps.isEmpty()) {
            return;
        }
        Application__c app = apps[0];
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setTargetObjectId(app.Contact__c);
        message.setUseSignature(false);
        message.setBccSender(false);
        message.setSaveAsActivity(true);
        message.setTreatTargetObjectAsRecipient(false);
        if (GOOGLE_REVIEW_TEMPLATE == null) {
            return;
        }
        message.setTemplateID(GOOGLE_REVIEW_TEMPLATE.Id);
        message.setWhatId(app.Id);
        if (DEFAULT_ORG_WIDE_EMAIL_ADDRESS == null ) {
           return;
        }
        message.setOrgWideEmailAddressId(DEFAULT_ORG_WIDE_EMAIL_ADDRESS.Id);
        message.toAddresses = new String[] { app.Email__c };
        Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
        Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
    }

    public class ErrorResponseWrapper{
        String code;
        String message;
        String moreInfo;
        String status;
    }
}