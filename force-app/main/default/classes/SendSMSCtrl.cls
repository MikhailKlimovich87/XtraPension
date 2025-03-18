public class SendSMSCtrl {
    @AuraEnabled
    public static String sendSMS(String phoneNo, String smsBody, String fromPhNumber){
        String accountSid = 'ACd3a3ae56a2cbc17f1d4275a2e9156bef'; // you can put ACCOUNT SID from twilio account
        String token = 'ad9e1712fa403e5c52049ed3519aadc8'; // you can put AUTH TOKEN from twilio account
        String endPoint = 'https://api.twilio.com/2010-04-01/Accounts/' + accountSid + '/SMS/Messages.json';
        Blob creds = Blob.valueOf(accountSid + ':' + token);
        HttpRequest req = new HttpRequest();
        Http http = new Http();
        HTTPResponse res = new HTTPResponse();
        req.setEndpoint(endPoint);
        req.setMethod('POST');
        String VERSION  = '3.2.0';
        req.setHeader('X-Twilio-Client', 'salesforce-' + VERSION);
        req.setHeader('User-Agent', 'twilio-salesforce/' + VERSION);
        req.setHeader('Accept', 'application/json');
        req.setHeader('Accept-Charset', 'utf-8');
        req.setHeader('Authorization', 'Basic '+EncodingUtil.base64Encode(creds));
        req.setBody(
            'To=' + EncodingUtil.urlEncode(phoneNo, 'UTF-8') +
            '&From=' + EncodingUtil.urlEncode(fromPhNumber,'UTF-8') +
            '&Body=' + smsBody
        );
        res = http.send(req);
        System.debug(res.getBody());

       if(res.getStatusCode() == 201) {
           return 'SMS Sent Successfully';
       } else {
            System.debug('Error');
            return 'Error';
           /*errorWrapper er = (errorWrapper)json.deserialize(res.getBody(), errorWrapper.class);
           throw newMessageException('Error : ' + er.message);*/
       }
    }

    public class errorWrapper{
       String code;
       String message;
       String moreInfo;
       String status;
   }

    private static AuraHandledException newMessageException(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}