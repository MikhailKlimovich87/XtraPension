@isTest
global class GeneratePDFMock implements HttpCalloutMock {
    global HTTPResponse respond(HTTPRequest req) {
        // Create a fake response
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setBody(
            '{' +
                '"status":"Success", ' +
                '"result":{' +
                    '"application":"qYAbjAbasdZDAaDSZadDS", ' +
                    '"agent":"QASDzAZASdQaASDWAadAdsqwed"' +
                '}' +
            '}');
        res.setStatusCode(200);
        return res;
    }

}