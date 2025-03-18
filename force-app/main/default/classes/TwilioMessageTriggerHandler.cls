public class TwilioMessageTriggerHandler {
    public static String accountId = XtraPension_Data__c.getInstance().Twilio_Account__c;
    public static String tokenId   = XtraPension_Data__c.getInstance().Twilio_Token__c;

    @future(callout=true)
    public static void getMessageData(String messageSID, Id messageId) {
        Datetime myStartDateTime = Datetime.now();
        DateTime newDateTime = myStartDateTime.addSeconds(3);
        while (datetime.now() < newDateTime ) {}
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.twilio.com/2010-04-01/Accounts/' + accountId + '/Messages/' + messageSID + '.json');
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        Blob headerValue = Blob.valueOf(accountId + ':' + tokenId);
        String authorizationHeader = 'BASIC ' + EncodingUtil.base64Encode(headerValue);
        req.setHeader('Authorization', authorizationHeader);
        Http http = new Http();
        HTTPResponse httpResponse = http.send(req);
        if (httpResponse.getStatusCode() >= 200 && httpResponse.getStatusCode() < 300) {
			String responseBody = httpResponse.getBody();
            TwilioMessageWrapper responseData = (TwilioMessageWrapper) JSON.deserialize(responseBody, TwilioMessageWrapper.class);
            upsert new TwilioSF__Message__c(
                Id = messageId,
                TwilioSF__Status__c = responseData?.status
            );
		} else {
            return;
		}
    }

    public class TwilioMessageWrapper {
        public String status;
    }
}