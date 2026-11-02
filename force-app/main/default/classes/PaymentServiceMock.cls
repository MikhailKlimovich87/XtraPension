@isTest
global class PaymentServiceMock implements HttpCalloutMock {
    global HTTPResponse respond(HTTPRequest req) {
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        if (req.getEndpoint().contains('/payment_methods/')) {
            res.setBody(
                '{"id":"pm_1245GFFuEghj4Gvbnjftg","card":{"brand":"visa","last4":"4242"}}'
            );
        } else {
            res.setBody(
                '{' +
                    '"id":"pi_3hjNHGnBjgkjhg1FD", ' +
                    '"object":"payment_intent", ' +
                    '"amount":"40000",' +
                    '"latest_charge":"ch_123456789",' +
                    '"payment_method":"pm_1245GFFuEghj4Gvbnjftg"' +
                '}'
            );
        }
        res.setStatusCode(200);
        return res;
    }
}