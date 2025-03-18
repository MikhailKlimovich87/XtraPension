@RestResource(urlMapping='/TwilioWebhookApi/*')
global class TwilioWebhookService {
	@HttpPost
    global static void invokeRestResponse() {
        String expectedSignature = RestContext.request.headers.get('X-Twilio-Signature');
        String url = 'https://' + RestContext.request.headers.get('Host') + '/services/apexrest' + RestContext.request.requestURI;
        Map <String, String> params = RestContext.request.params;
        system.debug('Return Response' + params);

        // Validate signature
    }
}