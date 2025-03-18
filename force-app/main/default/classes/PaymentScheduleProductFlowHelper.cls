public class PaymentScheduleProductFlowHelper {
    public class Request {
        @InvocableVariable(required = true)
        public List<Payment__c> payment;
    }

    public class Response {
        @InvocableVariable(label = 'Result of execution' required = true)
        public String result;
    }

    @InvocableMethod
    public static List<Response> paySchedulePayment(List<Request> requestData) {
        List<Response> responseData = new List<Response>();
        Response response = new Response();
        ApplicationService service = new ApplicationService();
        List<Payment__c> schedulePayments = requestData[0].payment;
        if (schedulePayments.isEmpty()) {
            response.result = 'Error';
            responseData.add(response);
            return responseData;
        }
        List<Payment__c> paymentsWithRelatedObjects = [
            SELECT
                Name,
                Product__r.Name,
                Customer_Id__c,
                Payment_Method__c,
                Amount__c,
                Application__r.Email__c,
                Tax_VAT__c,
                CurrencyIsoCode
            FROM Payment__c
            WHERE Id IN :schedulePayments
        ];
        if (paymentsWithRelatedObjects.isEmpty()) {
            response.result = 'Error';
            responseData.add(response);
            return responseData;
        }
        service.executeStripePayment(paymentsWithRelatedObjects);

        response.result = 'Success';
        responseData.add(response);
        return responseData;
    }
}