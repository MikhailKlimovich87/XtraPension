public class BulkUpdateStripePaymentIntentsBatch implements Database.Batchable<BulkUpdateStripePaymentIntentsBatch.PaymentDataWrapper>, Database.AllowsCallouts {

    private DateTime startDateTime;
    private DateTime endDateTime;

    public BulkUpdateStripePaymentIntentsBatch() {
        DateTime now = DateTime.now();
        this.startDateTime = DateTime.newInstanceGmt(now.yearGmt(), now.monthGmt(), 1, 0, 0, 0);
        this.endDateTime = DateTime.newInstanceGmt(now.yearGmt(), now.monthGmt(), now.dayGmt(), 23, 59, 59);
    }

    public BulkUpdateStripePaymentIntentsBatch(DateTime startDateTime, DateTime endDateTime) {
        this.startDateTime = startDateTime;
        this.endDateTime = endDateTime;
    }

    public class ResponseDataWrapper {
        public List<PaymentDataWrapper> data;
    }

    public class PaymentDataWrapper {
        public String customer;
        public String id;    
    }

    public class CustomerDataWrapper {
        public String id;
        public String email;
    }

    public Iterable<PaymentDataWrapper> start(Database.BatchableContext bc) {
        DateTime startDate = this.startDateTime;
        DateTime endDate = this.endDateTime;

        if (startDate == null || endDate == null) {
            DateTime now = DateTime.now();
            DateTime defaultStart = DateTime.newInstanceGmt(now.yearGmt(), now.monthGmt(), 1, 0, 0, 0);
            DateTime defaultEnd = DateTime.newInstanceGmt(now.yearGmt(), now.monthGmt(), now.dayGmt(), 23, 59, 59);
            startDate = startDate == null ? defaultStart : startDate;
            endDate = endDate == null ? defaultEnd : endDate;
        }

        Long startTimestamp = startDate.getTime() / 1000;
        Long endTimestamp = endDate.getTime() / 1000;

        Map<String, String> requestParams = new Map<String, String>();
        requestParams.put('query','created>='+startTimestamp+' AND created<='+endTimestamp+' AND metadata["AppNo"]:null');
        requestParams.put('limit','100');
	    StripeApiHandler.StripeAPIResponseWrapper requestResult = StripeApiHandler.requestStripeApi(
		    'payment_intents/search',
		    'GET',
		    requestParams
	    );
        ResponseDataWrapper wrapper = (ResponseDataWrapper) JSON.deserialize(requestResult.responseBody, ResponseDataWrapper.class);
        return wrapper.data == null
                    ? new List<PaymentDataWrapper>()
                    : wrapper.data;
    }

    // Execute method processing the custom objects
    public void execute(Database.BatchableContext bc, List<PaymentDataWrapper> scope) {
        if (scope.size() == 0) return;
        PaymentDataWrapper currentItem = scope[0];
        List<Payment__c> payments = [
            SELECT Name, Customer_Id__c, Application_Name__c
            FROM Payment__c
            WHERE Customer_Id__c = :currentItem.customer
        ];
        if (payments.size() == 0) {
            StripeApiHandler.StripeAPIResponseWrapper getCustomerRequestResult = StripeApiHandler.requestStripeApi(
                'customers/' + currentItem.customer,
                'GET',
                new Map<String, String>()
            );
            if (getCustomerRequestResult != null && String.isNotBlank(getCustomerRequestResult.responseBody)) {
                CustomerDataWrapper customerData = (CustomerDataWrapper) JSON.deserialize(getCustomerRequestResult.responseBody, CustomerDataWrapper.class);
                if (customerData != null && String.isNotBlank(customerData.email)) {
                    List<Application__c> apps = [
                        SELECT Name
                        FROM Application__c
                        WHERE Email__c = :customerData.email
                        LIMIT 1
                    ];
                    if (!apps.isEmpty()) {
                        Map<String, String> requestParams = new Map<String, String>();
                        requestParams.put('metadata[AppNo]', apps[0].Name);
                        StripeApiHandler.StripeAPIResponseWrapper requestResult = StripeApiHandler.requestStripeApi(
                            'payment_intents/' + currentItem.id,
                            'POST',
                            requestParams
                        );
                    }
                }
            }
        } else {
            String applicationName = payments[0].Application_Name__c;
            Map<String, String> requestParams = new Map<String, String>();
            requestParams.put('metadata[AppNo]', applicationName);
            StripeApiHandler.StripeAPIResponseWrapper requestResult = StripeApiHandler.requestStripeApi(
                'payment_intents/' + currentItem.id,
                'POST',
                requestParams
            );
        }
    }

    public void finish(Database.BatchableContext bc) {
        // Post-processing
    }
}