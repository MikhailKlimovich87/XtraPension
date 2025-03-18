public class ApplicationPaymentAfter72Hours {
    public static final String APPLICATION_PRODUCT_NAME = 'Application';
    @InvocableMethod
    public static List<Response> createPaymentAfter72Hours(List<Request> requestData) {
        List<Response> responseWrapper = new List<Response>();
        Response response =  new Response();
        Application__c currentApp = requestData[0]?.application;
        List<Payment__c> applicationPayment = [
            SELECT
                Name,
                Product__r.Name,
                Status__c,
                Payment_Date__c,
                Customer_Id__c,
                Payment_Method__c,
                Amount__c,
                Application__r.Email__c,
                Tax_VAT__c
            FROM Payment__c
            WHERE Product__r.Name = :APPLICATION_PRODUCT_NAME AND
                  Application__c = :currentApp.Id AND
                  Status__c != 'Paid'
            LIMIT 1
        ];
        if (applicationPayment.isEmpty()) {
            response.result = 'Don\'t exist Application payment for application';
            responseWrapper.add(response);
            return responseWrapper;
        }
        Payment__c currentPayment = applicationPayment[0];
        try {
            List<Payment__c> payments = new List<Payment__c>();
            payments.add(currentPayment);
            ApplicationService service = new ApplicationService();
            service.executeStripePayment(payments);
            response.result = 'Success';
            responseWrapper.add(response);
            return responseWrapper;
        } catch (Exception ex) {
            response.result = 'You have error in dml operation: ' + ex.getMessage();
            responseWrapper.add(response);
            return responseWrapper;
        }
    }

    public class Request {
        @InvocableVariable(required = true)
        public Application__c application;
    }
    public class Response {
        @InvocableVariable(label = 'Result of execution' required = true)
        public String result;
    }
}