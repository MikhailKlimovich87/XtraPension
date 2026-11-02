public with sharing class TwilioSmsSender {

    public static final String ACCOUNT_ID =
        XtraPension_Data__c.getInstance().Twilio_Account__c;
    public static final String TOKEN_ID =
        XtraPension_Data__c.getInstance().Twilio_Token__c;
    public static final String FROM_NAME = 'XtraPension';
    public static final String TWILIO_FROM_NUMBER = '+19033076997';

    public static final Set<String> ALPHA_SENDER_COUNTRIES =
        new Set<String>{'AU', 'NZ', 'US', 'ZA'};

    /**
     * Sends an SMS through Twilio.
     * Returns null if phoneNumber is blank (no callout is attempted).
     */
    public static HttpResponse send(String message, String phoneNumber, String countryCode) {
        if (String.isBlank(phoneNumber)) {
            System.debug('TwilioSmsSender: phone number is blank, skipping callout.');
            return null;
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.twilio.com/2010-04-01/Accounts/'
                        + ACCOUNT_ID + '/Messages');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');

        String fromValue = ALPHA_SENDER_COUNTRIES.contains(countryCode)
                            ? TWILIO_FROM_NUMBER
                            : FROM_NAME;

        Blob headerValue = Blob.valueOf(ACCOUNT_ID + ':' + TOKEN_ID);
        req.setHeader('Authorization',
                      'BASIC ' + EncodingUtil.base64Encode(headerValue));

        req.setBody(
            'To='   + EncodingUtil.urlEncode(phoneNumber, 'UTF-8') +
            '&From=' + fromValue +
            '&Body=' + EncodingUtil.urlEncode(message, 'UTF-8')
        );

        return new Http().send(req);
    }
}