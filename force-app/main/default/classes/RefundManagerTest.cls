@isTest
public class RefundManagerTest {
    @TestSetup
    static void makeData(){
        List<String> productNames = new List<String>{'Deposit', 'Application'};
        List<Product2> newProducts = new List<Product2>();
        for (String name : productNames) {
            newProducts.add(new Product2(
                Name = name
            ));
        }
        insert newProducts;
        Id pricebookId = Test.getStandardPricebookId();

        List<PriceBookEntry> testStandardPriceBookEntries = new List<PriceBookEntry>();
        Integer counter = 100000;
        for (Product2 product : newProducts) {
            PriceBookEntry ret = new PriceBookEntry();
            ret.Pricebook2Id = pricebookId;
            ret.Product2Id = product.id;
            ret.UnitPrice = counter;
            ret.IsActive = true;
            ret.CurrencyIsoCode = 'GBP';
            testStandardPriceBookEntries.add(ret);
            counter += 10000;
        }
        insert testStandardPriceBookEntries;
        TestDataFactory.createTestCountry(true);
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
        Refund__c testRefund = TestDataFactory.createRefund(personContactId, true);
    }

    @IsTest
    static void createRefundCase1() {
        Test.setMock(HttpCalloutMock.class, new PaymentMethodMock());
        RestRequest request = new RestRequest();
        RestResponse response = new RestResponse();
        request.requestURI = '/api/v2/form/create-refund';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf('{ '+
            '"id": "12345784521",' +
            '"amount": "35000",' +
            '"email": "test.user@gmail.com",' +
            '"phone": "+1505123456123",' +
            '"name": "A-000001",' +
            '"firstName": "FirstName",' +
            '"lastName": "SecondName",' +
            '"packageName": "Premier",' +
            '"paymentMethod": "Test123456789Z",' +
            '"customer": "custome123456123457",' +
            '"tax": true,' +
            '"address": {' +
                '"line1": "1245 Test Street",' +
                '"line2": "Test",' +
                '"postal_code": "12345",' +
                '"state": "County Dublin",' +
                '"city": "Dublin",' +
                '"country": "IE"' +
            '}' +
        '}');
        RestContext.request = request;
        RestContext.response= response;
        Test.startTest();
        RefundManager.createRefund();
        Test.stopTest();
        List<Refund__c> refunds = [
            SELECT
                Name,
                Phone__c,
                First_Name__c,
                Last_Name__c,
                Email__c
            FROM Refund__c
            WHERE Stripe_Transaction_Id__c = '12345784521'
        ];
        System.assertEquals(1, refunds.size(), 'Don\'t exist new Application');
        Refund__c testRefunds = refunds[0];
        System.assertEquals('+1505123456123', testRefunds.Phone__c, 'Wrong phone number');
        System.assertEquals('FirstName', testRefunds.First_Name__c, 'Wrong First Name');
        System.assertEquals('SecondName', testRefunds.Last_Name__c, 'Wrong Second Name');
        System.assertEquals('test.user@gmail.com', testRefunds.Email__c, 'Wrong Email');
    }

    private class PaymentMethodMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            // Create a fake response
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{' +
                    '"id":"pm124512451", ' +
                    '"card":{' +
                        '"brand":"visa", ' +
                        '"last4":"4242"' +
                    '}' +
                '}');
            res.setStatusCode(200);
            return res;
        }
    }
}