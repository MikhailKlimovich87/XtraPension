@isTest
public class ResendEstimateControllerTest {
    @TestSetup
    static void makeData(){
        TestDataFactory.createLead(true);
    }
    @IsTest
    static void resendEstimateEmailTest(){
        Test.setMock(HttpCalloutMock.class, new GetPdfDataMock());
        List<Lead> leads = [
            SELECT Id
            FROM Lead
        ];
        Lead testLead = leads[0];
        Test.startTest();
        String result = ResendEstimateController.resendEstimateEmail(testLead.Id);
        Test.stopTest();
        System.assertNotEquals(null, result);
        System.assertEquals('Estimate resend successfully', result);
    }

    private class GetPdfDataMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            // Create a fake response
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{' +
                    '"Status":"OK",' +
                    '"StatusCode":"200"' +
                '}');
            res.setStatusCode(200);
            return res;
        }
    }
}