@isTest
public class TwilioMessageTriggerTest {

    @IsTest
    static void testGetMessageStatus(){
        TwilioSF__Message__c message = new TwilioSF__Message__c();
        message.TwilioSF__Body__c = 'This test message';
        message.TwilioSF__To_Number__c = '+11111236456';
        message.TwilioSF__Status__c = 'queued';
        insert message;
        Test.setMock(HttpCalloutMock.class, new TwilioMessageMock());
        Test.startTest();
            message.TwilioSF__Message_SID__c = 'SID111111111111';
            update message;
        Test.stopTest();
        List<TwilioSF__Message__c> testMessagesAfterUpdate = [
            SELECT
                TwilioSF__Message_SID__c,
                TwilioSF__Status__c
            FROM TwilioSF__Message__c
        ];
        TwilioSF__Message__c messageAfterUpdate = testMessagesAfterUpdate[0];
        System.assertNotEquals(message.TwilioSF__Status__c, messageAfterUpdate.TwilioSF__Status__c);
    }

    private class TwilioMessageMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            // Create a fake response
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{' +
                    '"status":"undelivered"' +
                '}');
            res.setStatusCode(200);
            return res;
        }
    }
}