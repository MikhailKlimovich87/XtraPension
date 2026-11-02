@IsTest
private class BP_CheckBankTest {

    @testSetup
        static void setup() {

            Data8__c data8 = new Data8__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                BankAccountValidationURL__c = 'https://example.com/accountValidation',
                BankIBANValidation__c = 'https://example.com/ibanValidation',
                Username__c = 'testUser'
            );
            insert data8;

            GooglePlacesConfig__c config = new GooglePlacesConfig__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                Place_API_key__c = 'test-google-api-key'
            );

            insert config;
        }
private class BankValidationMock implements HttpCalloutMock {

    public HTTPResponse respond(HTTPRequest req) {

        HttpResponse res = new HttpResponse();
        res.setStatusCode(200);
        res.setHeader('Content-Type', 'application/json');

        // Google Places API
        if (req.getEndpoint() == 'https://places.googleapis.com/v1/places:searchText') {

            res.setBody(
                '{' +
                    '"places":[' +
                        '{' +
                            '"displayName":{"text":"Test Bank"},' +
                            '"formattedAddress":"Test Bank, Main Street, Dublin, D01 ABCD, Ireland",' +
                            '"postalAddress":{' +
                                '"addressLines":["Main Street","Dublin"],' +
                                '"postalCode":"D01 ABCD"' +
                            '},' +
                            '"types":["bank"]' +
                        '}' +
                    ']' +
                '}'
            );

            return res;
        }

        // Bank validation API
        res.setBody(
            '{' +
                '"Status":{' +
                    '"Success":true,' +
                    '"CreditsRemaining":100' +
                '},' +
                '"Valid":"Yes",' +
                '"SortCode":"123456",' +
                '"AccountNumber":"12345678",' +
                '"BICCode":"ABCDEFGH",' +
                '"IBAN":"IE29AIBK93115212345678",' +
                '"BranchName":"Main Branch",' +
                '"ShortBankName":"Test Bank",' +
                '"FullBankName":"Test Bank Ltd",' +
                '"AcceptsBACSPayments":true,' +
                '"AcceptsDirectDebitTransactions":true,' +
                '"AcceptsDirectCreditTransactions":true,' +
                '"AcceptsUnpaidChequeClaimTransactions":false,' +
                '"AcceptsBuildingSocietyCreditTransactions":false,' +
                '"AcceptsDividendInterestPaymentTransactions":true,' +
                '"AcceptsDirectDebitInstructionTransactions":true,' +
                '"AcceptsCHAPSPayments":true,' +
                '"AcceptsCheques":true,' +
                '"AcceptsFasterPayments":true,' +
                '"Address":{' +
                    '"Address":{' +
                        '"Lines":["Line1","Line2"]' +
                    '},' +
                    '"RawAddress":{' +
                        '"Organisation":"Test Org",' +
                        '"Postcode":"D01 ABCD",' +
                        '"Locality":"Dublin"' +
                    '}' +
                '}' +
            '}'
        );

        return res;
    }
}

    @IsTest
    static void testValidationBySortCode() {

        Test.setMock(HttpCalloutMock.class, new BankValidationMock());

        Map<String, String> input = new Map<String, String>{
            'sortCode' => '123456',
            'accountNumber' => '12345678'
        };

        Test.startTest();

        BP_CheckBank.BankAccountValidationResponseWrapper result =
            BP_CheckBank.validCheck(input);

        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals('Yes', result.Valid);
        System.assertEquals(true, result.Status.Success);
        System.assertEquals('123456', result.SortCode);
        System.assertEquals('12345678', result.AccountNumber);
    }

    @IsTest
    static void testValidationByIBAN() {

        Test.setMock(HttpCalloutMock.class, new BankValidationMock());

        Map<String, String> input = new Map<String, String>{
            'IBAN' => 'IE29AIBK93115212345678',
            'BIC' => 'ABCDEFGH'
        };

        Test.startTest();

        BP_CheckBank.BankAccountValidationResponseWrapper result =
            BP_CheckBank.validCheck(input);

        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals('Yes', result.Valid);
        System.assertEquals(true, result.Status.Success);
        System.assertEquals('IE29AIBK93115212345678', result.IBAN);
        System.assertEquals('ABCDEFGH', result.BICCode);
    }

    @IsTest
    static void testValidationWithOnlyIBAN() {

        Test.setMock(HttpCalloutMock.class, new BankValidationMock());

        Map<String, String> input = new Map<String, String>{
            'IBAN' => 'IE29AIBK93115212345678'
        };

        Test.startTest();

        BP_CheckBank.BankAccountValidationResponseWrapper result =
            BP_CheckBank.validCheck(input);

        Test.stopTest();

        System.assertEquals(true, result.Status.Success);
        System.assertEquals('Yes', result.Valid);
    }

    @IsTest
    static void testValidationWithOnlyBIC() {

        Test.setMock(HttpCalloutMock.class, new BankValidationMock());

        Map<String, String> input = new Map<String, String>{
            'BIC' => 'ABCDEFGH'
        };

        Test.startTest();

        BP_CheckBank.BankAccountValidationResponseWrapper result =
            BP_CheckBank.validCheck(input);

        Test.stopTest();

        System.assertEquals(true, result.Status.Success);
        System.assertEquals('Yes', result.Valid);
    }

    @IsTest
    static void testParseCacheData() {

        Bank_Address_Cache__c cacheData = new Bank_Address_Cache__c(
            Account__c = '12345678',
            Bank_Address__c = 'Main Street 10',
            Bank_City__c = 'Dublin',
            Bank_Name__c = 'Test Bank',
            Bank_Postcode__c = 'D01 ABCD',
            BIC_SWIFT__c = 'ABCDEFGH',
            IBAN__c = 'IE29AIBK93115212345678',
            Sort_Code__c = '123456',
            Branch_Name__c = 'Main Branch'
        );

        insert cacheData;

        Test.startTest();

        BP_CheckBank.BankAccountValidationResponseWrapper result =
            BP_CheckBank.parseCacheData(cacheData);

        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertNotEquals(null, result.Status);

        System.assertEquals(true, result.Status.Success);
        System.assertEquals('Cache', result.Valid);

        // 123456 -> 12-34-56
        System.assertEquals('12-34-56', result.SortCode);

        System.assertEquals('12345678', result.AccountNumber);
        System.assertEquals('ABCDEFGH', result.BICCode);
        System.assertEquals('IE29AIBK93115212345678', result.IBAN);
        System.assertEquals('Main Branch', result.BranchName);
        System.assertEquals('Test Bank', result.ShortBankName);

        System.assertNotEquals(null, result.Address);
        System.assertNotEquals(null, result.Address.RawAddress);

        System.assertEquals('D01 ABCD', result.Address.RawAddress.Postcode);
        System.assertEquals('Dublin', result.Address.RawAddress.Locality);
        System.assertEquals('Test Bank', result.Address.RawAddress.Organisation);
        System.assertEquals(
            'Main Street 10',
            result.Address.RawAddress.ThoroughfareName
        );
    }

    @IsTest
    static void testValidAUSCheckCacheNotFound() {

        Map<String, String> input = new Map<String, String>{
            'sortCode' => '999999'
        };

        Test.startTest();

        BP_CheckBank.BankAccountValidationResponseWrapper result =
            BP_CheckBank.validAUSCheck(input);

        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertNotEquals(null, result.Status);

        System.assertEquals(false, result.Status.Success);
        System.assertEquals('Try manually', result.Valid);
    }

}