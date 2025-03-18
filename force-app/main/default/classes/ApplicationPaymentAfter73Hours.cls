public class ApplicationPaymentAfter73Hours {
    public static final String MOUNTLY_PRODUCT_NAME = 'Monthly Updates';
    @InvocableMethod
    public static List<Response> createPaymentAfter73Hours(List<Request> requestData) {
        List<Response> responseWrapper = new List<Response>();
        Response response =  new Response();
        Application__c currentApp = requestData[0]?.application;
        List<Payment__c> monthlyPayments = [
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
            WHERE Product__r.Name = :MOUNTLY_PRODUCT_NAME AND
                  Application__c = :currentApp.Id
        ];
        if (monthlyPayments.isEmpty()) {
            response.result = 'Don\'t exist all Monthly Updates payment for application';
            responseWrapper.add(response);
            return responseWrapper;
        }
        List<Payment__c> updatePayments = new List<Payment__c>();
        for (Integer i = 0; i < monthlyPayments.size(); i++) {
            if (i == 0) {
                List<Payment__c> payments = new List<Payment__c>();
                payments.add(monthlyPayments[i]);
                monthlyPayments[i].Number_Of_Payment__c = i + 1;
                updatePayments.add(monthlyPayments[i]);
                if ( monthlyPayments[i].Status__c != 'Paid') {
                    ApplicationService service = new ApplicationService();
                    service.executeStripePayment(payments);
                }
            } else {
                monthlyPayments[i].Status__c = 'Schedule';
                monthlyPayments[i].Payment_Date__c = Date.today().addMonths(i);
                monthlyPayments[i].Number_Of_Payment__c = i + 1;
                updatePayments.add(monthlyPayments[i]);
            }
        }
        try {
            update updatePayments;
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
        @InvocableVariable(label='Result of execution' required=true)
        public String result;
    }
}