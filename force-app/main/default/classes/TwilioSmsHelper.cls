public class TwilioSmsHelper {
    public Application__c app;
    private SMSWrapper wrapper;
    public static final XtraPension_Data__c TWILIO_DATA {
        get {
            if (TWILIO_DATA == null) {
                TWILIO_DATA = XtraPension_Data__c.getInstance();
            }
            return TWILIO_DATA;
        }
        private set;
    }

    public TwilioSmsHelper(Application__c currApp, SMSWrapper messageInfo) {
        this.app = currApp;
        this.wrapper = messageInfo;
    }

    public class SMSWrapper {
        public String body;
        public String to;
        public String fromData;
    }

    public void sendMessage() {
        String body = 'To=' + EncodingUtil.urlEncode(wrapper.to, 'UTF-8') +
                      '&From=' + EncodingUtil.urlEncode(wrapper.fromData, 'UTF-8') +
                      '&Body=' + wrapper.body;
        HttpResponse response = send(body);
        Map<String, Object> respornseBody = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());
        TwilioSF__Message__c message = new TwilioSF__Message__c();
        if (response.getStatusCode() >= 201 && response.getStatusCode() < 300) {
            message.TwilioSF__Message_SID__c = (String)respornseBody.get('sid');
            message.TwilioSF__Date_Sent__c = Datetime.now();
            message.TwilioSF__Status__c = (String)respornseBody.get('status');
            message.TwilioSF__Direction__c = (String)respornseBody.get('direction');
            message.TwilioSF__Error_Code__c = (String)respornseBody.get('error_code');
            message.TwilioSF__API_Failure_Message__c = (String)respornseBody.get('error_message');
            message.TwilioSF__Resource_Location__c = (String)respornseBody.get('uri');
        } else {
            message.TwilioSF__To_Number__c = wrapper.to;
            message.TwilioSF__From_Number__c = wrapper.fromData;
            message.TwilioSF__Date_Sent__c = Datetime.now();
            message.TwilioSF__Status__c = 'failed';
            message.TwilioSF__Direction__c = 'outbound-api';
            message.TwilioSF__Error_Code__c = String.valueOf(respornseBody.get('code'));
            message.TwilioSF__API_Failure_Message__c = (String)respornseBody.get('message');
        }

        if (message != null) {
            message.TwilioSF__SF_Parent_Record_Id__c = app.Contact__c;
            message.TwilioSF__Body__c = wrapper.body;
            message.TwilioSF__To_Number__c = wrapper.to;
            message.TwilioSF__From_Number__c = wrapper.fromData;
            message.Application__c = app.Id;
            insert message;
        }
    }

    private HttpResponse send(String bodyMessage) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(TWILIO_DATA.Twilio_Endpoint__c + TWILIO_DATA.Twilio_Account__c + '/Messages.json');
        request.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        Blob headerValue = Blob.valueOf(TWILIO_DATA.Twilio_Account__c + ':' + TWILIO_DATA.Twilio_Token__c);
        String authorizationHeader = 'BASIC ' + EncodingUtil.base64Encode(headerValue);
        request.setHeader('Authorization', authorizationHeader);
        request.setMethod('POST');
        request.setBody(bodyMessage);
        Http http = new Http();

        return http.send(request);
    }
}