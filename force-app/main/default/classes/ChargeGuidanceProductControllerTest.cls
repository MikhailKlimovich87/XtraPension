@isTest
public class ChargeGuidanceProductControllerTest {

    @TestSetup static void makeData() {
        List<Product2> products = TestDataFactory.createProductsWithPrices();
        Account account = TestDataFactory.createAccount(true);
        List<Contact> currentContact = [
            SELECT
                Id,
                AccountId
            FROM Contact
            WHERE AccountId = :account.Id
            LIMIT 1
        ];
        Id personContactId = currentContact[0].Id;
        Application__c application =  TestDataFactory.createApplication(personContactId, true);
        Order order = TestDataFactory.createOrder(application.Id, account.Id, true);
        TestDataFactory.createRelatedPaymentToApplication(products, application, order.Id, true);
    }

    @IsTest static void getApplicationTest() {
        List<Application__c> testApps = [
            SELECT Id
            FROM Application__c
            LIMIT 1
        ];
        Test.startTest();
        ChargeGuidanceProductController.ApplicationData resultData = ChargeGuidanceProductController.getApplication(testApps[0].Id);
        Test.stopTest();
        System.assertNotEquals(null, resultData.application, 'Don\'t exist new Application');
        System.assertEquals(false, resultData.allRelatedPayments.isEmpty(), 'Don\'t exist required Payments');
        System.assertEquals(4, resultData.allRelatedPayments.size(), 'Don\'t contains all nessasary Payments');
    }

    @IsTest static void chargeProductCase1Test() {
        List<Application__c> testApps = [
            SELECT Package_Name__c
            FROM Application__c
            LIMIT 1
        ];
        Application__c currentApplcation = testApps[0];
        ChargeGuidanceProductController.ChargeData testData = new ChargeGuidanceProductController.ChargeData();
        testData.recordId = '11111';
        testData.amount   = '10000';
        Test.startTest();
        ChargeGuidanceProductController.ChargeResult result = ChargeGuidanceProductController.chargeProduct(testData);
        Test.stopTest();
        System.assertNotEquals(null, result, 'Response don\'t contains result');
        System.assertEquals('Error', result.title, 'Result\'s Title is wrong');
        System.assertEquals('Don\'t exist NOT Paid payments', result.message, 'Result\'s Message is wrong');
        System.assertEquals('error', result.variant, 'Result\'s Variant is wrong');
    }

    @IsTest static void chargeProductCase2Test() {
        Test.setMock(HttpCalloutMock.class, new PaymentServiceMock());
        List<Application__c> testApps = [
            SELECT Package_Name__c
            FROM Application__c
            LIMIT 1
        ];
        Application__c currentApplcation = testApps[0];
        ChargeGuidanceProductController.ChargeData testData = new ChargeGuidanceProductController.ChargeData();
        testData.recordId = currentApplcation.Id;
        testData.amount   = '10000';
        Test.startTest();
        ChargeGuidanceProductController.ChargeResult result = ChargeGuidanceProductController.chargeProduct(testData);
        Test.stopTest();
        System.assertNotEquals(null, result, 'Response don\'t contains result');
        System.assertEquals('Success', result.title, 'Result\'s Title is wrong');
        System.assertEquals('You\'ve charged Success Product', result.message, 'Result\'s Message is wrong');
        System.assertEquals('success', result.variant, 'Result\'s Variant is wrong');
    }
}