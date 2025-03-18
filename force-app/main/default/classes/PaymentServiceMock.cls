@isTest
global class PaymentServiceMock implements HttpCalloutMock {
    global HTTPResponse respond(HTTPRequest req) {
        // Create a fake response
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setBody(
            '{' +
                '"id":"pi_3hjNHGnBjgkjhg1FD", ' +
                '"object":"payment_intent", ' +
                '"amount":"40000",' +
                '"payment_method":"pm_1245GFFuEghj4Gvbnjftg"' +
            '}');
        res.setStatusCode(200);
        return res;
    }
}