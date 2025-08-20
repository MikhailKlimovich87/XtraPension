public class HMRC_SMS_ScheduleDateTriggerHandler {
    public static final String ACCOUNT_ID = XtraPension_Data__c.getInstance().Twilio_Account__c;
    public static final String TOKEN_ID   = XtraPension_Data__c.getInstance().Twilio_Token__c;
    public static final String FROM_NAME = 'XtraPension';

    @future(callout=true)
    public static void sendMessage(String clientsInfo, String messageBody) {
        List<ClientInfo> phoneData = (List<ClientInfo>)System.JSON.deserialize(clientsInfo, List<ClientInfo>.class);
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.twilio.com/2010-04-01/Accounts/' + ACCOUNT_ID + '/Messages');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        Blob headerValue = Blob.valueOf(ACCOUNT_ID + ':' + TOKEN_ID);
        String authorizationHeader = 'BASIC ' + EncodingUtil.base64Encode(headerValue);
        req.setHeader('Authorization', authorizationHeader);
        for (ClientInfo info : phoneData) {
            if(info.phone != null && info.countryCode != null) {
                String fromData = info.countryCode == 'AU' || info.countryCode == 'NZ' || info.countryCode == 'US' || info.countryCode == 'CA' || info.countryCode == 'ZA' ? '+19033076997' : FROM_NAME;
                req.setBody('To=' + EncodingUtil.urlEncode(info.phone,'UTF-8') + '&From=' + fromData + '&Body=' + messageBody);
                try {
                    Http http = new Http();
                    //if (Test.isRunningTest()) return;
                    HTTPResponse res = http.send(req);
                    System.debug(res.getBody());
                    if(res.getStatusCode() == 201) System.debug('@@@Twilio Success' + info.phone);
                    else {
                        System.debug('@@@Twilio failed' + info.phone);
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

    public class ClientInfo{
        public String phone;
        public String countryCode;
    }
}