public class SendGoogleReviewSmsController {
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
    public static final String FROM_NAME = 'XtraPension';

    @AuraEnabled(cacheable=false)
    public static SendSmsResult sendGoogleReviewMessage(Id appId) {
        SendSmsResult result = new SendSmsResult();
        List<Application__c> apps = [
            SELECT Related_Contact_Phone__c
            FROM Application__c
            WHERE Id = :appId
        ];
        if (apps.isEmpty()) {
            result.message = 'Can\'t find necessary application!';
            result.title = 'Error!';
            result.variant = 'error';
            return result;
        }
        Application__c app = apps[0];
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.twilio.com/2010-04-01/Accounts/' + ACCOUNT_ID + '/Messages.json');
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
                TwilioResult resultSendMessage = (TwilioResult) JSON.deserialize(res.getBody(), TwilioResult.class);
                createTwilioMessage(resultSendMessage);
                result.message = 'You\'ve successfully send sms message!';
                result.title = 'Success result';
                result.variant = 'success';
                return result;
            }
            else {
                TwilioResult resultSendMessage = (TwilioResult) JSON.deserialize(res.getBody(), TwilioResult.class);
                createTwilioMessage(resultSendMessage);
                result.message = 'Message wasn\'t sent. Error: ' + res.getBody();
                result.title = 'Error!';
                result.variant = 'error';
                return result;
            }
        } catch(Exception ex) {
            result.message = 'Message wasn\'t sent. Error: ' + ex.getMessage();
            result.title = 'Error!';
            result.variant = 'error';
            return result;
        }


    }

    private static void createTwilioMessage(TwilioResult result) {
        TwilioSF__Message__c message = new TwilioSF__Message__c();
        message.TwilioSF__Message_SID__c = result.sid;
        message.TwilioSF__Body__c = MESSAGE_BODY;
        message.TwilioSF__To_Number__c = result.to;
        message.TwilioSF__From_Number__c = FROM_NAME;
        message.TwilioSF__Status__c = result.status;

        if (message != null) {
            insert message;
        }
    }


    public class SendSmsResult {
        @AuraEnabled
        public String title {get; set;}
        @AuraEnabled
        public String message {get; set;}
        @AuraEnabled
        public String variant {get; set;}
    }

    private class TwilioResult {
        private String sid {get; set;}
        private String status {get; set;}
        private String to {get; set;}
    }
}