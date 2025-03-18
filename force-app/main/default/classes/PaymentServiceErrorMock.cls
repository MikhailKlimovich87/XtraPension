@isTest
global class PaymentServiceErrorMock implements HttpCalloutMock {
    global HTTPResponse respond(HTTPRequest req) {
        // Create a fake response
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setBody(
            '{' +
                '"error":' +
                        '{' +
                            '"message":"Test error" ' +
                        '}' +
            '}');
        res.setStatusCode(400);
        return res;
    }
}