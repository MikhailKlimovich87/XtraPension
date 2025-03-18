public class BlanketSMSQueueable implements Queueable, Database.AllowsCallouts {
    public String bodyMessage;
    public String phoneNumber;
    public String accountId;
    public String tokenId;
    public final String FROM_NAME = 'XtraPension';

    public BlanketSMSQueueable(String message, String phoneData) {
        this.bodyMessage = message;
        this.phoneNumber = phoneData;
        this.accountId   = XtraPension_Data__c.getInstance().Twilio_Account__c;
        this.tokenId     = XtraPension_Data__c.getInstance().Twilio_Token__c;
    }

    public void execute(QueueableContext context) {
        // TwilioSF.TwilioApiClient api = new TwilioSF.TwilioApiClient();
        // api.addUrlPart('Accounts');
        // api.addUrlPart(accountId);
        // api.addUrlPart('Messages.json');
        // api.addParam('From','XtraPension');
        // api.addParam('Body', bodyMessage);
        // api.addParam('To', phoneNumber);
        // if (!Test.isRunningTest()) {
        //     TwilioSF.TwilioApiClientResponse response = api.doPost();
        // }
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.twilio.com/2010-04-01/Accounts/' + accountId + '/Messages');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        Blob headerValue = Blob.valueOf(accountId + ':' + tokenId);
        String authorizationHeader = 'BASIC ' + EncodingUtil.base64Encode(headerValue);
        req.setHeader('Authorization', authorizationHeader);
        req.setBody('To=' + EncodingUtil.urlEncode(phoneNumber,'UTF-8') + '&From=' + FROM_NAME + '&Body=' + bodyMessage);
        System.debug('req.getBody() === ' + req.getBody());
        Http http = new Http();
        // if (!Test.isRunningTest()) {
        //     HTTPResponse res = http.send(req);
        // }
    }
}