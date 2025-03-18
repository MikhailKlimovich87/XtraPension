public class HMRC_SMS_ScheduleDateTriggerHandler {
    public static final String ACCOUNT_ID = XtraPension_Data__c.getInstance().Twilio_Account__c;
    public static final String TOKEN_ID   = XtraPension_Data__c.getInstance().Twilio_Token__c;
    public static final String FROM_NAME = 'XtraPension';

    @future(callout=true)
    public static void sendMessage(List<String> phoneData, String messageBody) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.twilio.com/2010-04-01/Accounts/' + ACCOUNT_ID + '/Messages');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        Blob headerValue = Blob.valueOf(ACCOUNT_ID + ':' + TOKEN_ID);
        String authorizationHeader = 'BASIC ' + EncodingUtil.base64Encode(headerValue);
        req.setHeader('Authorization', authorizationHeader);
        for (String phone : phoneData) {
            if(phone != null) {
                req.setBody('To=' + EncodingUtil.urlEncode(phone,'UTF-8') + '&From=' + FROM_NAME + '&Body=' + messageBody);
                try {
                    Http http = new Http();
                    //if (Test.isRunningTest()) return;
                    HTTPResponse res = http.send(req);
                    System.debug(res.getBody());
                    if(res.getStatusCode() == 201) System.debug('@@@Twilio Success' + phone);
                    else {
                        System.debug('@@@Twilio failed' + phone);
                        ErrorResponseWrapper erw =(ErrorResponseWrapper)json.deserialize(res.getBody(), ErrorResponseWrapper.class);
                        System.debug('@@@Twilio error' + erw.message);
                    }
                } catch(Exception ex){
                    System.debug('Error message = ' + ex.getMessage());
                }
            }
        }
    }

    public class ErrorResponseWrapper{
        String code;
        String message;
        String moreInfo;
        String status;
    }
}