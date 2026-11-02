@isTest
public class CurrencyRateSchedulerTest {
    private class HmrcExchangeRateMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/xml');
            res.setStatusCode(200);
            String xmlBody = '<?xml version="1.0" encoding="UTF-8"?>' +
                '<exchangeRates>' +
                    '<exchangeRate>' +
                        '<currencyCode>EUR</currencyCode>' +
                        '<rateNew>0.85</rateNew>' +
                    '</exchangeRate>' +
                    '<exchangeRate>' +
                        '<currencyCode>AUD</currencyCode>' +
                        '<rateNew>1.65</rateNew>' +
                    '</exchangeRate>' +
                    '<exchangeRate>' +
                        '<currencyCode>USD</currencyCode>' +
                        '<rateNew>1.25</rateNew>' +
                    '</exchangeRate>' +
                '</exchangeRates>';
            res.setBody(xmlBody);
            return res;
        }
    }

    @isTest
    static void currencyRateScheduleTest() {
        Test.setMock(HttpCalloutMock.class, new HmrcExchangeRateMock());
        Test.startTest();
        CurrencyRateScheduler testScheduler = new CurrencyRateScheduler();
        String cronEspression = '0 0 23 * * ?';
		Id jobId = System.schedule('Test get Currency Rates', cronEspression, testScheduler);
        Test.stopTest();
        CronTrigger ct = [
            SELECT
                Id,
                CronExpression,
                TimesTriggered,
                NextFireTime
            FROM CronTrigger
            WHERE id = :jobId];

        System.assertNotEquals(null, ct);
        System.assertEquals('0 0 23 * * ?', ct.CronExpression);
        System.assertEquals(0, ct.TimesTriggered);
    }
}