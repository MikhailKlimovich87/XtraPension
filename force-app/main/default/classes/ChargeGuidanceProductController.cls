public class ChargeGuidanceProductController {
    public static final String GUIDANCE_PRODUCT_NAME = 'Success';

    @AuraEnabled(cacheable = true)
    public static ApplicationData getApplication (String recordId) {
        ApplicationData resultData = new ApplicationData();
        List<Application__c> applications = [
            SELECT
                HMRC_Reply_Status__c,
                Status__c,
                Package_Name__c,
                Live_In_The_EU__c,
                CurrencyIsoCode,
                (
                    SELECT
                        Product_Name__c,
                        Status__c,
                        Amount__c,
                        Payment_Date__c
                    FROM Payments__r
                )
            FROM Application__c
            WHERE Id = :recordId
        ];
        if (!applications.isEmpty()) {
            Application__c currentApp = applications[0];
            resultData.application = currentApp;
            resultData.allRelatedPayments = currentApp?.Payments__r.size() > 0 ? currentApp?.Payments__r : null;
            resultData.currencyCode = currentApp.CurrencyIsoCode;
            return resultData;
        } else return null;
    }

    @AuraEnabled
    public static ChargeResult chargeProduct(ChargeData productInfo) {
        ChargeResult result = new ChargeResult();
        List<Payment__c> applicationPayments = [
            SELECT
                Name,
                Product__r.Name,
                Status__c,
                Payment_Date__c,
                Customer_Id__c,
                Payment_Method__c,
                Amount__c,
                Application__r.Email__c,
                Tax_VAT__c,
                CurrencyIsoCode
            FROM Payment__c
            WHERE Application__c = :(productInfo.recordId) AND
                  Status__c != 'Paid'
        ];
        if (applicationPayments.isEmpty()) {
            result.message = 'Don\'t exist NOT Paid payments';
            result.title   = 'Error';
            result.variant = 'error';
            return result;
        }
        Map<String, Payment__c> productNameByPayment = new Map<String, Payment__c>();
        for (Payment__c payment : applicationPayments) {
            productNameByPayment.put(payment.Product__r.Name, Payment);
        }
        try {
            Payment__c successProduct = productNameByPayment.get(GUIDANCE_PRODUCT_NAME);
            if (successProduct == null) {
                result.message = 'Don\'t exist Success payment for application';
                result.title   = 'Error';
                result.variant = 'error';
                return result;
            }
            List<Payment__c> updatePayments = new List<Payment__c>();
            successProduct.Amount__c = Decimal.valueOf(productInfo.amount);
            updatePayments.add(successProduct);
            List<Payment__c> paidPayment = new List<Payment__c>();
            paidPayment.add(successProduct);
            ApplicationService service = new ApplicationService();
            service.executeStripePayment(paidPayment);
            for (Payment__c payment : applicationPayments) {
                if (payment.Product__r.Name != GUIDANCE_PRODUCT_NAME) {
                    payment.Status__c = 'Cancel';
                    updatePayments.add(payment);
                }
            }
            if (!updatePayments.isEmpty()) {
                update updatePayments;
            }
            result.title = 'Success';
            result.variant = 'success';
            result.message = 'You\'ve charged Success Product';
            return result;
        } catch (Exception ex) {
            result.message = 'You didn\'t charge Success Product. Error is ' + ex.getMessage();
            result.title   = 'Error';
            result.variant = 'error';
            return result;
        }
    }

    public class ChargeResult {
        @AuraEnabled
        public String title {get; set;}
        @AuraEnabled
        public String message {get; set;}
        @AuraEnabled
        public String variant {get; set;}
    }

    public class ApplicationData {
        @AuraEnabled
        public Application__c application {get; set;}
        @AuraEnabled
        public List<Payment__c> allRelatedPayments {get; set;}
        @AuraEnabled
        public String currencyCode {get; set;}
    }

    public class ChargeData {
        @AuraEnabled
        public String recordId {get; set;}
        @AuraEnabled
        public String amount {get; set;}
    }
}