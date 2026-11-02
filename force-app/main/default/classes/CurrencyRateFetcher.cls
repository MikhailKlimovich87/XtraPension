public class CurrencyRateFetcher {

    @future(callout=true)
    public static void updateRates() {
        // 1. Build the Frankfurter API endpoint.
        // We request rates with GBP as the base currency for EUR and AUD.
        String endpoint = 'https://api.frankfurter.dev/v2/rates?base=GBP&quotes=EUR,AUD';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(20000);

        Http http = new Http();
        HttpResponse res;
        try {
            res = http.send(req);
        } catch (System.CalloutException e) {
            System.debug('Callout failed: ' + e.getMessage());
            return;
        }

        if (res.getStatusCode() != 200) {
            System.debug('API returned status: ' + res.getStatusCode() + ' body: ' + res.getBody());
            return;
        }

        // 2. Parse the JSON response using Apex's JSON deserialization.
        // The Frankfurter API returns a JSON array of rate objects.
        Decimal gbpToEur = null;
        Decimal gbpToAud = null;

        try {
            List<Object> ratesList = (List<Object>) JSON.deserializeUntyped(res.getBody());
            for (Object rateObj : ratesList) {
                Map<String, Object> rateMap = (Map<String, Object>) rateObj;
                String quote = (String) rateMap.get('quote');
                Decimal rate = (Decimal) rateMap.get('rate');

                if (quote == 'EUR') {
                    gbpToEur = rate;
                } else if (quote == 'AUD') {
                    gbpToAud = rate;
                }
            }
        } catch (Exception e) {
            System.debug('Failed to parse JSON: ' + e.getMessage());
            return;
        }

        if (gbpToEur == null || gbpToAud == null) {
            System.debug('Missing EUR or AUD rate in response. EUR: ' + gbpToEur + ', AUD: ' + gbpToAud);
            return;
        }

        // 3. Save into the custom object.
        // Frankfurter provides daily rates, so we use today's date.
        Date rateDate = Date.today();

        Daily_Exchange_Rate__c rec = new Daily_Exchange_Rate__c(
            Rate_Date__c   = rateDate,
            Date_Key__c    = String.valueOf(rateDate),
            GBP_to_EUR__c  = gbpToEur,
            GBP_to_AUD__c  = gbpToAud,
            Source__c      = 'Frankfurter API',
            Fetched_At__c  = Datetime.now()
        );

        try {
            upsert rec Daily_Exchange_Rate__c.Date_Key__c;
            System.debug('Saved Frankfurter rates for ' + rateDate + ' → EUR: ' + gbpToEur + ', AUD: ' + gbpToAud);
        } catch (DmlException e) {
            System.debug('DML failed: ' + e.getMessage());
        }
    }
}