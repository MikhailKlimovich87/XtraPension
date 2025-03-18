@isTest
global class CustomerStripeMock implements HttpCalloutMock {
    global HTTPResponse respond(HTTPRequest req) {
        // Create a fake response
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setBody(
            '{' +
                '"id":"cus_asdfABjgkjhg1FD", ' +
                '"object":"customer", ' +
                '"email":"john.snow@test.com",' +
                '"phone":"+123451245"' +
            '}');
        res.setStatusCode(200);
        return res;
    }
}