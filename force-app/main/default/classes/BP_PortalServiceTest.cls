@isTest
private class BP_PortalServiceTest {

   @TestSetup
    static void setup() {
        List<String> productNames = new List<String>{'Claim'};
        List<Product2> newProducts = new List<Product2>();
        for (String name : productNames) {
            newProducts.add(new Product2(
                Name = name,
                CurrencyIsoCode = 'EUR'
            ));
        }
        insert newProducts;
        Id pricebookId = Test.getStandardPricebookId();
        List<PriceBookEntry> testPriceBookEntries = new List<PriceBookEntry>();
        Integer counter = 100000;
        for (Product2 product : newProducts) {
            PriceBookEntry ret = new PriceBookEntry();
            ret.Pricebook2Id = pricebookId;
            ret.Product2Id = product.id;
            ret.UnitPrice = counter;
            ret.IsActive = true;
            ret.CurrencyIsoCode = 'EUR';
            testPriceBookEntries.add(ret);
            counter += 10000;
        }
        insert testPriceBookEntries;
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
        Basic__c testApplication = BP_TestDataFactory.createBasic(personContactId, true);
        Claimant_Child__c testChaild = BP_TestDataFactory.createChild(testApplication.Id, true);
        Claimant_Company__c testCompany = BP_TestDataFactory.createCompany(testApplication.Id, true);
        Claimant_Country_lived__c testCountryLived = BP_TestDataFactory.createCountryLived(testApplication.Id, true);
        Basic_Payment__c testPayment = BP_TestDataFactory.createBP_Payment(testApplication.Id, true, newProducts[0]);

        XtraPension_Data__c data = new XtraPension_Data__c(
            BP_Registration_template__c = 'TestTemplate',
            BP_Pdf_File_Link__c = 'test',
            BP_Pdf_File_IPC1394_Link__c = 'test',
            BP_PDF_IPCBR1_Wet__c = 'test',
            BP_PDF_IPC1394_Wet__c = 'test',
            BP_Form_Link__c = 'test'

        );
        insert data;
    }

    @isTest
    static void testCreateApplication() {

        Test.setMock(HttpCalloutMock.class, new PaymentMethodMock());
        RestRequest request = new RestRequest();
        RestResponse response = new RestResponse();
        request.requestURI = '/api/v1/payment/sendPaymentInfo';
        request.httpMethod = 'POST';


        Basic__c currentApplication = [SELECT Id, 
                Name, 
                Validation_Agent__c,
                CurrencyIsoCode,
                Stripe_Transaction_Id__c, 
                Stripe_Customer_Id__c, 
                Status__c, 
                Phone__c, 
                Payment_Method__c, 
                Last_Name__c, 
                First_Name__c, 
                Email__c, 
                Friend_Email__c,
                Friend_First_Name__c,
                Friend_Last_Name__c,
                Friend_Phone__c,
                Current_Address_Abroad_State__c, 
                Current_Address_Abroad_Country__c, 
                Claimant_City__c,
                Eircode__c, 
                Current_Address_Abroad_State_Name__c,
                Contact__c, 
                Full_Current_Ad__c, 
                Agent_Making_Sale__c, 
                Step__c, 
                Agent_Form_Step__c,
                Relationship__c,
                Claimant_title__c, 
                Current_Address_Abroad_Country_Name__c,
                Claimant_other_names__c, 
                Claimant_dob__c, 
                Claimant_maiden_Name__c,                 
                Claimant_marital_Status__c, 
                Claimant_nationality__c, 
                Claimant_date_Of_Marriage__c, 
                Claimant_date_Of_Bereavement__c, 
                Claimant_date_Of_Divorce__c, 
                Claimant_hasNino__c, 
                Claimant_nino__c, 
                Claimant_address1__c, 
                Claimant_address2__c, 
                Claimant_ever_Lived_UK__c, 
                Claimant_lived_UK_From__c, 
                Claimant_lived_UK_to__c, 
                Claimant_Ever_Worked_UK__c, 
                Claimant_worked_UK_From__c, 
                Claimant_worked_UK_To__c, 
                Claimant_has_Proof_Of_UK_Work__c, 
                Claimant_self_Employed_UK__c, 
                Claimant_Ever_Paid_Married_Woman_s_Stam__c, 
                Claimant_Minded_Kids__c,
                Claimant_Bereavement_Benefit__c,
                Claimant_Graduated_Retirement_Benefit__c,
                Claimant_State_Pension__c,
                Claimant_Widows_Benefit__c,
                Partner_Bereavement_Benefit__c,
                Partner_Graduated_Retirement_Benefit__c,
                Partner_State_Pension__c,
                Partner_Widows_Benefit__c,
                Partner_Address1__c,
                Partner_Address2__c,
                Partner_City__c,
                Partner_Country__c,
                Partner_Country_Code__c,
                Partner_DOB__c,
                Partner_Has_Nino__c,
                Partner_Maiden_Name__c,
                Partner_Nino__c,
                Partner_Other_Name__c,
                Partner_Postcode__c,
                Partner_same_as_claimant__c,
                Partner_Surname__c,
                Partner_Title__c,
                Pension_Claiming_from_Today__c,
                Pension_Deferred_Pension__c,
                Pension_Imprisoned_Since_Pension_Age__c,
                Pension_Start_Date__c,
                Bank_Account__c,
                Bank_Account_Owner_Name__c,
                Bank_Account_Type__c,
                Bank_IBAN__c,
                Bank_Name__c,
                Bank_Sort_Code__c,
                Bank_Country__c,
                Bank_Country_Code__c,
                Bank_Post_Code__c,
                Bank_City__c,
                Bank_Address__c,
                Bank_BIC__c,
                Pension_Work_After_Pension_Age__c,
                (SELECT Id, Basic__c, From_date__c, Name, Country_Type__c, Social_Security_Number__c, To_Date__c FROM ClaimantCountrieslived__r),
                (SELECT Id, Basic__c, Dob__c, Name, Minded_From__c, Minded_To__c, Nino__c  FROM Clamant_Children__r),
                (SELECT Id, Basic__c, Address1__c, Address2__c, City__c, Country__c, Country_Type__c, Name, From_Date__c, To_Date__c, Postcode__c  FROM Claimant_Companies__r)
                FROM Basic__c
                LIMIT 1
            ];

        Basic_Payment__c payment = [SELECT Id FROM Basic_Payment__c WHERE Basic__c =: currentApplication.Id LIMIT 1];

        request.requestBody = Blob.valueOf('{' +
            '"address": {' +
                '"country": "US",' +
                '"line1": "Test",' +
                '"city": "Test",' +
                '"state": "HI",' +
                '"postal_code": "04075",' +
                '"line2": null' +
            '},' +
            '"amount": 10000,' +
            '"customer": "cus__",' +
            '"email": "' + currentApplication.Email__c + '",' +
            '"id": "' + currentApplication.Id + '",' +
            '"lastName": "' + currentApplication.Last_Name__c + '",' +
            '"name": "' + currentApplication.First_Name__c + ' ' + currentApplication.Last_Name__c + '",' +
            '"paymentId": "' + payment.Id + '",' +
            '"paymentMethod": "' + currentApplication.Payment_Method__c + '",' +
            '"phone": "' + currentApplication.Phone__c + '"' +
        '}');

        Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];

        Map<String, Object> bodyMap = new Map<String, Object>{
            'id' => b.Id,
            'email' => 'test@test.com',
            'phone' => '123456',
            'currencyCode' => 'EUR',
            'name' => 'Test User',
            'firstName' => 'John',
            'lastName' => 'Doe',
            'paymentMethod' => 'card',
            'address' => new Map<String, Object>{
                'street' => 'Street 1',
                'city' => 'London',
                'postalCode' => 'SW1A 1AA',
                'country' => 'GB',
                'countryCode' => 'GB'
            }
        };

        runTest('/api/v4/application/create', bodyMap, 200);
    }

    @isTest
    static void testGetDetails() {

        Test.setMock(HttpCalloutMock.class, new PaymentMethodMock());
        RestRequest request = new RestRequest();
        RestResponse response = new RestResponse();
        request.requestURI = '/api/v1/payment/sendPaymentInfo';
        request.httpMethod = 'POST';


        Basic__c currentApplication = [SELECT Id, 
                Name, 
                Validation_Agent__c,
                CurrencyIsoCode,
                Stripe_Transaction_Id__c, 
                Stripe_Customer_Id__c, 
                Status__c, 
                Phone__c, 
                Payment_Method__c, 
                Last_Name__c, 
                First_Name__c, 
                Email__c, 
                Friend_Email__c,
                Friend_First_Name__c,
                Friend_Last_Name__c,
                Friend_Phone__c,
                Current_Address_Abroad_State__c, 
                Current_Address_Abroad_Country__c, 
                Claimant_City__c,
                Eircode__c, 
                Current_Address_Abroad_State_Name__c,
                Contact__c, 
                Full_Current_Ad__c, 
                Agent_Making_Sale__c, 
                Step__c, 
                Agent_Form_Step__c,
                Relationship__c,
                Claimant_title__c, 
                Current_Address_Abroad_Country_Name__c,
                Claimant_other_names__c, 
                Claimant_dob__c, 
                Claimant_maiden_Name__c,                 
                Claimant_marital_Status__c, 
                Claimant_nationality__c, 
                Claimant_date_Of_Marriage__c, 
                Claimant_date_Of_Bereavement__c, 
                Claimant_date_Of_Divorce__c, 
                Claimant_hasNino__c, 
                Claimant_nino__c, 
                Claimant_address1__c, 
                Claimant_address2__c, 
                Claimant_ever_Lived_UK__c, 
                Claimant_lived_UK_From__c, 
                Claimant_lived_UK_to__c, 
                Claimant_Ever_Worked_UK__c, 
                Claimant_worked_UK_From__c, 
                Claimant_worked_UK_To__c, 
                Claimant_has_Proof_Of_UK_Work__c, 
                Claimant_self_Employed_UK__c, 
                Claimant_Ever_Paid_Married_Woman_s_Stam__c, 
                Claimant_Minded_Kids__c,
                Claimant_Bereavement_Benefit__c,
                Claimant_Graduated_Retirement_Benefit__c,
                Claimant_State_Pension__c,
                Claimant_Widows_Benefit__c,
                Partner_Bereavement_Benefit__c,
                Partner_Graduated_Retirement_Benefit__c,
                Partner_State_Pension__c,
                Partner_Widows_Benefit__c,
                Partner_Address1__c,
                Partner_Address2__c,
                Partner_City__c,
                Partner_Country__c,
                Partner_Country_Code__c,
                Partner_DOB__c,
                Partner_Has_Nino__c,
                Partner_Maiden_Name__c,
                Partner_Nino__c,
                Partner_Other_Name__c,
                Partner_Postcode__c,
                Partner_same_as_claimant__c,
                Partner_Surname__c,
                Partner_Title__c,
                Pension_Claiming_from_Today__c,
                Pension_Deferred_Pension__c,
                Pension_Imprisoned_Since_Pension_Age__c,
                Pension_Start_Date__c,
                Bank_Account__c,
                Bank_Account_Owner_Name__c,
                Bank_Account_Type__c,
                Bank_IBAN__c,
                Bank_Name__c,
                Bank_Sort_Code__c,
                Bank_Country__c,
                Bank_Country_Code__c,
                Bank_Post_Code__c,
                Bank_City__c,
                Bank_Address__c,
                Bank_BIC__c,
                Pension_Work_After_Pension_Age__c,
                (SELECT Id, Basic__c, From_date__c, Name, Country_Type__c, Social_Security_Number__c, To_Date__c FROM ClaimantCountrieslived__r),
                (SELECT Id, Basic__c, Dob__c, Name, Minded_From__c, Minded_To__c, Nino__c  FROM Clamant_Children__r),
                (SELECT Id, Basic__c, Address1__c, Address2__c, City__c, Country__c, Country_Type__c, Name, From_Date__c, To_Date__c, Postcode__c  FROM Claimant_Companies__r)
                FROM Basic__c
                LIMIT 1
            ];

        Basic_Payment__c payment = [SELECT Id FROM Basic_Payment__c WHERE Basic__c =: currentApplication.Id LIMIT 1];

        request.requestBody = Blob.valueOf('{' +
            '"address": {' +
                '"country": "US",' +
                '"line1": "Test",' +
                '"city": "Test",' +
                '"state": "HI",' +
                '"postal_code": "04075",' +
                '"line2": null' +
            '},' +
            '"amount": 10000,' +
            '"customer": "cus__",' +
            '"email": "' + currentApplication.Email__c + '",' +
            '"id": "' + currentApplication.Id + '",' +
            '"lastName": "' + currentApplication.Last_Name__c + '",' +
            '"name": "' + currentApplication.First_Name__c + ' ' + currentApplication.Last_Name__c + '",' +
            '"paymentId": "' + payment.Id + '",' +
            '"paymentMethod": "' + currentApplication.Payment_Method__c + '",' +
            '"phone": "' + currentApplication.Phone__c + '"' +
        '}');

        Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];

        Map<String, Object> bodyMap = new Map<String, Object>{
            'applicationId' => b.Id,
            'currentStep' => 1,
            'agent' => '',
            'isAgentForm' => false,
            'application' => new Map<String, Object>{
                'claimant' => new Map<String, Object>()
            }
        };

        runTest('/api/v4/application/details', bodyMap, 200);
    }

    @isTest
    static void testUpdateDetails() {

        Test.setMock(HttpCalloutMock.class, new PaymentMethodMock());
        RestRequest request = new RestRequest();
        RestResponse response = new RestResponse();
        request.requestURI = '/api/v1/payment/sendPaymentInfo';
        request.httpMethod = 'POST';


        Basic__c currentApplication = [SELECT Id, 
                Name, 
                Validation_Agent__c,
                CurrencyIsoCode,
                Stripe_Transaction_Id__c, 
                Stripe_Customer_Id__c, 
                Status__c, 
                Phone__c, 
                Payment_Method__c, 
                Last_Name__c, 
                First_Name__c, 
                Email__c, 
                Friend_Email__c,
                Friend_First_Name__c,
                Friend_Last_Name__c,
                Friend_Phone__c,
                Current_Address_Abroad_State__c, 
                Current_Address_Abroad_Country__c, 
                Claimant_City__c,
                Eircode__c, 
                Current_Address_Abroad_State_Name__c,
                Contact__c, 
                Full_Current_Ad__c, 
                Agent_Making_Sale__c, 
                Step__c, 
                Agent_Form_Step__c,
                Relationship__c,
                Claimant_title__c, 
                Current_Address_Abroad_Country_Name__c,
                Claimant_other_names__c, 
                Claimant_dob__c, 
                Claimant_maiden_Name__c,                 
                Claimant_marital_Status__c, 
                Claimant_nationality__c, 
                Claimant_date_Of_Marriage__c, 
                Claimant_date_Of_Bereavement__c, 
                Claimant_date_Of_Divorce__c, 
                Claimant_hasNino__c, 
                Claimant_nino__c, 
                Claimant_address1__c, 
                Claimant_address2__c, 
                Claimant_ever_Lived_UK__c, 
                Claimant_lived_UK_From__c, 
                Claimant_lived_UK_to__c, 
                Claimant_Ever_Worked_UK__c, 
                Claimant_worked_UK_From__c, 
                Claimant_worked_UK_To__c, 
                Claimant_has_Proof_Of_UK_Work__c, 
                Claimant_self_Employed_UK__c, 
                Claimant_Ever_Paid_Married_Woman_s_Stam__c, 
                Claimant_Minded_Kids__c,
                Claimant_Bereavement_Benefit__c,
                Claimant_Graduated_Retirement_Benefit__c,
                Claimant_State_Pension__c,
                Claimant_Widows_Benefit__c,
                Partner_Bereavement_Benefit__c,
                Partner_Graduated_Retirement_Benefit__c,
                Partner_State_Pension__c,
                Partner_Widows_Benefit__c,
                Partner_Address1__c,
                Partner_Address2__c,
                Partner_City__c,
                Partner_Country__c,
                Partner_Country_Code__c,
                Partner_DOB__c,
                Partner_Has_Nino__c,
                Partner_Maiden_Name__c,
                Partner_Nino__c,
                Partner_Other_Name__c,
                Partner_Postcode__c,
                Partner_same_as_claimant__c,
                Partner_Surname__c,
                Partner_Title__c,
                Pension_Claiming_from_Today__c,
                Pension_Deferred_Pension__c,
                Pension_Imprisoned_Since_Pension_Age__c,
                Pension_Start_Date__c,
                Bank_Account__c,
                Bank_Account_Owner_Name__c,
                Bank_Account_Type__c,
                Bank_IBAN__c,
                Bank_Name__c,
                Bank_Sort_Code__c,
                Bank_Country__c,
                Bank_Country_Code__c,
                Bank_Post_Code__c,
                Bank_City__c,
                Bank_Address__c,
                Bank_BIC__c,
                Pension_Work_After_Pension_Age__c,
                Partner_Ever_Lived_UK__c,
                (SELECT Id, Basic__c, From_date__c, Name, Country_Type__c, Social_Security_Number__c, To_Date__c FROM ClaimantCountrieslived__r),
                (SELECT Id, Basic__c, Dob__c, Name, Minded_From__c, Minded_To__c, Nino__c  FROM Clamant_Children__r),
                (SELECT Id, Basic__c, Address1__c, Address2__c, City__c, Country__c, Country_Type__c, Name, From_Date__c, To_Date__c, Postcode__c  FROM Claimant_Companies__r)
                FROM Basic__c
                LIMIT 1
            ];

        Basic_Payment__c payment = [SELECT Id FROM Basic_Payment__c WHERE Basic__c =: currentApplication.Id LIMIT 1];

        request.requestBody = Blob.valueOf('{' +
            '"address": {' +
                '"country": "US",' +
                '"line1": "Test",' +
                '"city": "Test",' +
                '"state": "HI",' +
                '"postal_code": "04075",' +
                '"line2": null' +
            '},' +
            '"amount": 10000,' +
            '"customer": "cus__",' +
            '"email": "' + currentApplication.Email__c + '",' +
            '"id": "' + currentApplication.Id + '",' +
            '"lastName": "' + currentApplication.Last_Name__c + '",' +
            '"name": "' + currentApplication.First_Name__c + ' ' + currentApplication.Last_Name__c + '",' +
            '"paymentId": "' + payment.Id + '",' +
            '"paymentMethod": "' + currentApplication.Payment_Method__c + '",' +
            '"phone": "' + currentApplication.Phone__c + '"' +
        '}');

        Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];

        Map<String, Object> bodyMap = new Map<String, Object>{
            'applicationId' => b.Id,
            'currentStep' => 3,
            'agent' => '',
            'isAgentForm' => false,

            'application' => new Map<String, Object>{

                'contactCommunication' => new Map<String, Object>{
                    'firstName' => 'John',
                    'lastName' => 'Doe',
                    'tel' => '123456',
                    'email' => 'test@test.com',
                    'relationship' => 'friend'
                },

                'claimant' => new Map<String, Object>{
                    'title' => 'Mr',
                    'surname' => 'Test',
                    'otherNames' => 'Tester',
                    'dob' => '1990-01-01T12:30:45Z',
                    'maidenName' => '',
                    'tel' => '123',
                    'email' => 'test@test.com',
                    'maritalStatus' => 'single',
                    'nationality' => 'GB',
                    'dateOfMarriage' => '',
                    'dateOfBereavement' => '',
                    'dateOfDivorce' => '',
                    'hasNino' => false,
                    'nino' => '',

                    'country' => 'GB',
                    'postcode' => 'SW1A1AA',
                    'address1' => 'Street 1',
                    'address2' => '',
                    'city' => 'London',

                    'everLivedUK' => false,
                    'livedUKFrom' => '',
                    'livedUKTo' => '',
                    'everWorkedUK' => false,
                    'workedUKFrom' => '',
                    'workedUKTo' => '',
                    'hasProofOfUKWork' => false,
                    'selfEmployedUK' => false,
                    'marriedWomansStamp' => false,
                    'mindedKids' => false,


                    'children' => new List<Object>{
                        new Map<String, Object>{
                            'name' => 'Child 1',
                            'dob' => '2015-01-01T12:30:45Z',
                            'mindedFromDate' => '2016-01-01T12:30:45Z',
                            'mindedToDate' => '2017-01-01T12:30:45Z',
                            'nino' => 'AA123'
                        }
                    },

                    'ukCompanies' => new List<Object>{
                        new Map<String, Object>{
                            'name' => 'Company 1',
                            'address1' => 'Addr1',
                            'address2' => 'Addr2',
                            'city' => 'London',
                            'country' => 'GB',
                            'postcode' => '12345',
                            'fromDate' => '2010-01-01T12:30:45Z',
                            'toDate' => '2012-01-01T12:30:45Z'
                        }
                    },

                    'countriesLived' => new List<Object>{
                        new Map<String, Object>{
                            'name' => 'GB',
                            'fromDate' => '2000-01-01T12:30:45Z',
                            'toDate' => '2005-01-01T12:30:45Z',
                            'socialSecurityNumber' => 'SSN123'
                        }
                    }
                },

                'claimantBenefits' => new Map<String, Object>{
                    'bereavement' => false,
                    'graduatedRetirement' => false,
                    'statePension' => true,
                    'widows' => false
                },

                'partnerBenefits' => new Map<String, Object>{
                    'bereavement' => false,
                    'graduatedRetirement' => false,
                    'statePension' => false,
                    'widows' => false
                },

                'partner' => new Map<String, Object>{
                    'title' => 'Mrs',
                    'surname' => 'Test',
                    'otherNames' => 'Partner',
                    'dob' => '1991-01-01T12:30:45Z',
                    'maidenName' => '',
                    'hasNino' => false,
                    'nino' => '',
                    'saveAsClaimant' => false,
                    'country' => 'GB',
                    'postcode' => 'SW1A1AA',
                    'address1' => 'Street',
                    'address2' => '',
                    'city' => 'London',
                    'everLivedUK' => false,
                    'everWorkedUK' => false,
                    'everLivedUKNotes' => '',
                    'firstName' => 'Test',
                    'claimingUKPension' => false,
                    'referenceOnAnyDWPLetters' => 'test'
                },

                'pension' => new Map<String, Object>{
                    'claimingFromToday' => true,
                    'startDate' => '2025-01-01T12:30:45Z',
                    'workAfterPensionAge' => false,
                    'deferredPension' => false,
                    'imprisonedSincePensionAge' => false
                },

                'bank' => new Map<String, Object>{
                    'account' => '12345678',
                    'accountOwnerName' => 'John Doe',
                    'accountType' => 'personal',
                    'bankName' => 'Test Bank',
                    'iban' => 'GB29NWBK60161331926819',
                    'sortCode' => '12-34-56'
                }
            }
        };

        runTest('/api/v4/application/details-update', bodyMap, 200);
    }

    @isTest
    static void testInvalid() {
        runTest('/api/v4/unknown', new Map<String, Object>(), 400);
    }

    private static void runTest(String uri, Object body, Integer expectedStatus) {

        RestRequest req = new RestRequest();
        req.requestUri = uri;
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(body));

        RestResponse res = new RestResponse();

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        BP_PortalService.postRouter();
        Test.stopTest();

        System.assertEquals(
            expectedStatus,
            RestContext.response.statusCode,
            'Failed for endpoint: ' + uri + ' response: ' + RestContext.response.responseBody
        );
    }

    private class PaymentMethodMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            // Create a fake response
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{' +
                    '"id":"pm124512451", ' +
                    '"status":"succeeded", ' +
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