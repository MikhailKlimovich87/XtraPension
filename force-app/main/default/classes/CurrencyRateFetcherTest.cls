@isTest
private class CurrencyRateFetcherTest {

    /**
     * Mock that returns a valid Frankfurter JSON response with EUR and AUD rates.
     */
    private class FrankfurterSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            String jsonBody = '[' +
                '{"date":"2026-10-27","base":"GBP","quote":"EUR","rate":0.85},' +
                '{"date":"2026-10-27","base":"GBP","quote":"AUD","rate":1.65}' +
            ']';
            res.setBody(jsonBody);
            return res;
        }
    }

    /**
     * Mock that returns a 500 HTTP error.
     */
    private class HttpErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('Internal Server Error');
            return res;
        }
    }

    /**
     * Mock that returns malformed JSON.
     */
    private class MalformedJsonMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{not valid json');
            return res;
        }
    }

    /**
     * Mock that returns JSON missing the required currencies.
     */
    private class MissingCurrenciesMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('[' +
                '{"date":"2026-10-27","base":"GBP","quote":"USD","rate":1.25}' +
            ']');
            return res;
        }
    }

    /**
     * Test a successful callout and record creation.
     */
    @isTest
    static void testUpdateRatesSuccess() {
        Test.setMock(HttpCalloutMock.class, new FrankfurterSuccessMock());

        Test.startTest();
        CurrencyRateFetcher.updateRates();
        Test.stopTest();

        List<Daily_Exchange_Rate__c> rates = [
            SELECT Id, Rate_Date__c, GBP_to_EUR__c, GBP_to_AUD__c, Source__c, Fetched_At__c
            FROM Daily_Exchange_Rate__c
        ];

        System.assertEquals(1, rates.size(), 'One exchange rate record should be created.');

        Daily_Exchange_Rate__c rec = rates[0];
        System.assertEquals(Date.today(), rec.Rate_Date__c, 'Rate date should be today.');
        System.assertEquals(0.85, rec.GBP_to_EUR__c, 'GBP to EUR rate should match the mock.');
        System.assertEquals(1.65, rec.GBP_to_AUD__c, 'GBP to AUD rate should match the mock.');
        System.assertEquals('Frankfurter API', rec.Source__c, 'Source should be set correctly.');
        System.assertNotEquals(null, rec.Fetched_At__c, 'Fetched timestamp should be set.');
    }

    /**
     * Test that a non-200 HTTP response results in no record being created.
     */
    @isTest
    static void testUpdateRatesHttpError() {
        Test.setMock(HttpCalloutMock.class, new HttpErrorMock());

        Test.startTest();
        CurrencyRateFetcher.updateRates();
        Test.stopTest();

        List<Daily_Exchange_Rate__c> rates = [SELECT Id FROM Daily_Exchange_Rate__c];
        System.assertEquals(0, rates.size(), 'No record should be created on HTTP error.');
    }

    /**
     * Test that a malformed JSON response results in no record being created.
     */
    @isTest
    static void testUpdateRatesMalformedJson() {
        Test.setMock(HttpCalloutMock.class, new MalformedJsonMock());

        Test.startTest();
        CurrencyRateFetcher.updateRates();
        Test.stopTest();

        List<Daily_Exchange_Rate__c> rates = [SELECT Id FROM Daily_Exchange_Rate__c];
        System.assertEquals(0, rates.size(), 'No record should be created on malformed JSON.');
    }

    /**
     * Test that a response missing the required currencies results in no record.
     */
    @isTest
    static void testUpdateRatesMissingCurrencies() {
        Test.setMock(HttpCalloutMock.class, new MissingCurrenciesMock());

        Test.startTest();
        CurrencyRateFetcher.updateRates();
        Test.stopTest();

        List<Daily_Exchange_Rate__c> rates = [SELECT Id FROM Daily_Exchange_Rate__c];
        System.assertEquals(0, rates.size(), 'No record should be created if EUR or AUD is missing.');
    }

    /**
     * Test the upsert behavior on a second call (record should be updated, not duplicated).
     */
    @isTest
    static void testUpdateRatesUpsert() {
        Test.setMock(HttpCalloutMock.class, new FrankfurterSuccessMock());

        Test.startTest();
        // Call the method twice inside a single start/stop block.
        // This will execute the @future method twice and verify upsert logic.
        CurrencyRateFetcher.updateRates();
        CurrencyRateFetcher.updateRates();
        Test.stopTest();

        List<Daily_Exchange_Rate__c> rates = [SELECT Id FROM Daily_Exchange_Rate__c];
        System.assertEquals(1, rates.size(), 'Second call should upsert, not create a duplicate.');
    }
}