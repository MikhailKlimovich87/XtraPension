public class ApplicationFlowHandler {
    public static final String APPLICATION_PRODUCT_NAME = 'Application';
    @InvocableMethod
    public static List<Response> createPaymentAfter72Hours(List<Sobject> applications) {
        List<Response> responseWrapper = new List<Response>();
        Response response =  new Response();
        Application__c currentApp = (Application__c) applications[0];
        List<Payment__c> applicationPayment = [
            SELECT
                Name,
                Product__r.Name,
                Status__c,
                Payment_Date__c
            FROM Payment__c
            WHERE
                Product__r.Name = :APPLICATION_PRODUCT_NAME AND
                Application__c = :currentApp.Id
            LIMIT 1
        ];
        if (applicationPayment.isEmpty()) {
            response.result = 'Don\'t exist Application payment for application';
            responseWrapper.add(response);
            return responseWrapper;
        }
        Payment__c currentPayment = applicationPayment[0];
        currentPayment.Status__c = 'Schedule';
        currentPayment.Payment_Date__c = Date.today();
        try {
            update currentPayment;
            response.result = 'Success';
            responseWrapper.add(response);
            return responseWrapper;
        } catch (Exception ex) {
            response.result = 'You have error in dml operation: ' + ex.getMessage();
            responseWrapper.add(response);
            return responseWrapper;
        }
    }

    public class Requests {
        @InvocableVariable(label = 'Current Application' required = true)
        public List<Sobject> applications;
    }
    public class Response {
        @InvocableVariable(label = 'Result of execution' required = true)
        public String result;
    }
}