public class MassSendSmsQueueable implements Queueable, Database.AllowsCallouts {
    public String message;
    public String phoneNumber;
    public static final String ACCOUNT_ID = XtraPension_Data__c.getInstance().Twilio_Account__c;
    public static final String TOKEN_ID   = XtraPension_Data__c.getInstance().Twilio_Token__c;
    public static final String FROM_NAME = 'XtraPension';

    public MassSendSmsQueueable(String messageBody, String phoneData) {
        this.message = messageBody;
        this.phoneNumber = phoneData;
    }

    public void execute(QueueableContext context) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.twilio.com/2010-04-01/Accounts/' + ACCOUNT_ID + '/Messages');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        Blob headerValue = Blob.valueOf(ACCOUNT_ID + ':' + TOKEN_ID);
        String authorizationHeader = 'BASIC ' + EncodingUtil.base64Encode(headerValue);
        req.setHeader('Authorization', authorizationHeader);
        req.setBody('To=' + EncodingUtil.urlEncode(phoneNumber,'UTF-8') + '&From=' + FROM_NAME + '&Body=' + message);
        try {
            Http http = new Http();
            HTTPResponse res = http.send(req);
            System.debug(res.getBody());
        } catch(Exception ex){
            System.debug('Error message = ' + ex.getMessage());
        }
    }
}