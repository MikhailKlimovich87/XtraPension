@isTest
private class BP_PortalApplicationHelperTest {

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

    private class PdfMock implements HttpCalloutMock {

        String recordId;

        public PdfMock(String recordId) {
            this.recordId = recordId;
        }

        public HTTPResponse respond(HTTPRequest req) {

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            res.setBody(JSON.serialize(new Map<String, Object>{
                'recordId' => recordId,
                'base64' => EncodingUtil.base64Encode(Blob.valueOf('PDF-DATA')),
                'fileType' => 'pdf',
                'fileName' => 'generated'
            }));

            return res;
        }
    }

    @isTest
    static void testCreateApplication_success() {

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
                Current_Address_Abroad_State_Name__c,
                Current_Address_Abroad_Country__c, 
                Current_Address_Abroad__Street__s, 
                Claimant_City__c,
                Eircode__c, 
                Current_Address_Abroad__CountryCode__s,
                toLabel(Current_Address_Abroad__CountryCode__s) CountryCode,
                Current_Address_Abroad__Latitude__s, 
                Current_Address_Abroad__Longitude__s, 
                Current_Address_Abroad__GeocodeAccuracy__s, 
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

        BP_RequestWrappers.ApplicationCreateDataWrapper wrapper =
            buildCreateWrapper();

        Test.startTest();
        Map<String, Object> result =
            BP_PortalApplicationHelper.createApplication(wrapper);
        Test.stopTest();

        System.assertEquals('success', result.get('status'));
    }

    @isTest
    static void testGetApplicationDetail_success() {

        Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];

        BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper =
            new BP_RequestWrappers.ApplicationDetailsDataWrapper(
                JSON.serialize(new Map<String,Object>{
                    'applicationId' => b.Id,
                    'currentStep' => 1,
                    'agent' => '',
                    'isAgentForm' => false,
                    'application' => new Map<String,Object>{
                        'contactCommunication' => new Map<String,Object>{
                            'firstName' => 'John',
                            'lastName' => 'Doe',
                            'tel' => '0700000000',
                            'email' => 'john@test.com',
                            'relationship' => 'Friend'
                        }
                    }
                })
            );

        Test.startTest();
        Map<String, Object> result =
            BP_PortalApplicationHelper.getApplicationDetail(wrapper);
        Test.stopTest();

        System.assertEquals('success', result.get('status'));
    }

    @isTest
    static void testUpdate_step1() {

        Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];

        Map<String,Object> body = new Map<String,Object>{
            'applicationId' => b.Id,
            'currentStep' => 1,
            'agent' => '',
            'isAgentForm' => false,
            'application' => new Map<String,Object>{
                'contactCommunication' => new Map<String,Object>{
                    'firstName' => 'John',
                    'lastName' => 'Doe',
                    'tel' => '0700000000',
                    'email' => 'john@test.com',
                    'relationship' => 'Friend'
                }
            }
        };

        BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper =
            new BP_RequestWrappers.ApplicationDetailsDataWrapper(JSON.serialize(body));

        Test.startTest();
        Map<String,Object> result =
            BP_PortalApplicationHelper.updateApplicationDetails(wrapper);
        Test.stopTest();

        System.assertEquals('success', result.get('status'));
    }

    @isTest
    static void testUpdate_step2() {

        Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];

        Map<String,Object> body = new Map<String,Object>{
            'applicationId' => b.Id,
            'currentStep' => 2,
            'agent' => '',
            'isAgentForm' => false,
            'application' => new Map<String,Object>{
                'claimant' => new Map<String,Object>{
                    'title' => 'Mr',
                    'surname' => 'Smith',
                    'otherNames' => 'John',
                    'dob' => '1990-01-01T12:30:45Z',
                    'maidenName' => 'N/A',
                    'tel' => '0700000000',
                    'email' => 'john@test.com',
                    'maritalStatus' => 'Single',
                    'nationality' => 'GB',
                    'dateOfMarriage' => '2010-01-01T12:30:45Z',
                    'dateOfBereavement' => null,
                    'dateOfDivorce' => null,
                    'hasNino' => true,
                    'nino' => 'AB123456C',
                    'country' => 'GB',
                    'postcode' => 'SW1A 1AA',
                    'address1' => 'Street 1',
                    'address2' => 'Street 2',
                    'city' => 'London',
                    'everLivedUK' => true,
                    'livedUKFrom' => '2000-01-01T12:30:45Z',
                    'livedUKTo' => '2010-01-01T12:30:45Z',
                    'everWorkedUK' => true,
                    'workedUKFrom' => '2005-01-01T12:30:45Z',
                    'workedUKTo' => '2010-01-01T12:30:45Z',
                    'hasProofOfUKWork' => true,
                    'selfEmployedUK' => false,
                    'marriedWomansStamp' => false,
                    'mindedKids' => false,
                    'countriesLived' => new List<Object>(),
                    'ukCompanies' => new List<Object>(),
                    'children' => new List<Object>(),
                    'everWorkedUKuseSameDates' => false
                }
            }
        };

        BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper =
            new BP_RequestWrappers.ApplicationDetailsDataWrapper(JSON.serialize(body));

        Test.startTest();
        Map<String,Object> result =
            BP_PortalApplicationHelper.updateApplicationDetails(wrapper);
        Test.stopTest();

        System.assertEquals('success', result.get('status'));
    }

    @isTest
    static void testUpdate_step7_pdf() {

        Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new PdfMock(b.Id));

        Map<String,Object> body = new Map<String,Object>{
            'applicationId' => b.Id,
            'currentStep' => 7,
            'agent' => '',
            'isAgentForm' => false,
            'application' => new Map<String,Object>{
                'bank' => new Map<String,Object>{
                    'account' => '123456',
                    'accountOwnerName' => 'John Doe',
                    'accountType' => 'Personal',
                    'bankName' => 'Test Bank',
                    'iban' => 'GB00TEST',
                    'sortCode' => '00-00-00'
                }
            }
        };

        BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper =
            new BP_RequestWrappers.ApplicationDetailsDataWrapper(JSON.serialize(body));

        Test.startTest();
        Map<String,Object> result =
            BP_PortalApplicationHelper.updateApplicationDetails(wrapper);
        Test.stopTest();

        System.assertEquals('success', result.get('status'));
    }

    private static BP_RequestWrappers.ApplicationCreateDataWrapper buildCreateWrapper() {

        Map<String,Object> body = new Map<String,Object>{
            'id' => 'ch_123',
            'email' => 'test@test.com',
            'phone' => '0700000000',
            'name' => 'Test User',
            'currencyCode' => 'GBP',
            'firstName' => 'John',
            'lastName' => 'Doe',
            'paymentMethod' => 'card',
            'customer' => 'cus_123',
            'latest_charge' => 'lc_123',
            'howDidYouHearAboutUs' => 'Google',
            'agent' => 'None',
            'address' => new Map<String,Object>{
                'street' => 'Street 1, Street 2',
                'city' => 'London',
                'country' => 'GB',
                'postalCode' => 'SW1A 1AA'
            }
        };

        return new BP_RequestWrappers.ApplicationCreateDataWrapper(JSON.serialize(body));
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

        private class BankMock implements HttpCalloutMock {

        public HTTPResponse respond(HTTPRequest req) {

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{}');

            return res;
        }
    }


    @isTest
    static void testCreateApplication_null() {

        Test.startTest();

        Map<String,Object> result =
            BP_PortalApplicationHelper.createApplication(null);

        Test.stopTest();


        System.assertEquals(
            'error',
            result.get('status')
        );

        System.assertEquals(
            'Application data is empty',
            result.get('message')
        );
    }



    @isTest
    static void testGetApplicationFill_success() {

        Basic__c b = [
            SELECT Id
            FROM Basic__c
            LIMIT 1
        ];


        BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper =
            new BP_RequestWrappers.ApplicationDetailsDataWrapper(
                JSON.serialize(
                    new Map<String,Object>{
                        'applicationId' => b.Id
                    }
                )
            );


        Test.startTest();

        Map<String,Object> result =
            BP_PortalApplicationHelper.getApplicationFill(wrapper);

        Test.stopTest();


        System.assertEquals(
            'success',
            result.get('status')
        );
    }



    @isTest
    static void testGetApplicationFill_null() {

        Map<String,Object> result =
            BP_PortalApplicationHelper.getApplicationFill(null);


        System.assertEquals(
            'error',
            result.get('status')
        );
    }




    @isTest
    static void testValidateBank_null() {

        Map<String,Object> result =
            BP_PortalApplicationHelper.validateBank(null);


        System.assertEquals(
            'error',
            result.get('status')
        );
    }


    @isTest
    static void testValidateBank_success() {


        Basic__c b = [
            SELECT Id
            FROM Basic__c
            LIMIT 1
        ];



        BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper =
            new BP_RequestWrappers.ApplicationDetailsDataWrapper(
                JSON.serialize(
                    new Map<String,Object>{

                        'applicationId'=>b.Id,

                        'application'=>new Map<String,Object>{

                            'bank'=>new Map<String,Object>{
                                'account'=>'123456',
                                'iban'=>'GB123456',
                                'bic'=>'TESTGB',
                                'sortCode'=>'11-22-33'
                            }
                        }
                    }
                )
            );



        Test.setMock(
            HttpCalloutMock.class,
            new BankMock()
        );


        Test.startTest();

        Map<String,Object> result =
            BP_PortalApplicationHelper.validateBank(wrapper);

        Test.stopTest();



        System.assertEquals(
            'success',
            result.get('status')
        );
    }





    @isTest
    static void testGetApplicationEnvelopeFill_success() {


        Basic__c b = [
            SELECT Id
            FROM Basic__c
            LIMIT 1
        ];



        BP_RequestWrappers.ShortApplicationDataWrapper wrapper =
            new BP_RequestWrappers.ShortApplicationDataWrapper(
                JSON.serialize(
                    new Map<String,Object>{
                        'applicationId'=>b.Id
                    }
                )
            );



        Test.startTest();


        Map<String,Object> result =
            BP_PortalApplicationHelper.getApplicationEnvelopeFill(wrapper);


        Test.stopTest();



        System.assertEquals(
            'success',
            result.get('status')
        );
    }





    @isTest
    static void testFutureMethods() {


        Basic__c b = [
            SELECT Id
            FROM Basic__c
            LIMIT 1
        ];



        Test.startTest();


        BP_PortalApplicationHelper.paidEmail(b.Id);

        BP_PortalApplicationHelper.validateFile(b.Id);


        Test.stopTest();


        System.assert(true);
    }





    // @isTest
    // static void testGenerateFileFuture() {


    //     Basic__c b = [
    //         SELECT Id
    //         FROM Basic__c
    //         LIMIT 1
    //     ];



    //     Test.setMock(
    //         HttpCalloutMock.class,
    //         new PdfMock(b.Id)
    //     );



    //     Test.startTest();


    //     BP_PortalApplicationHelper.generateFile(b.Id);


    //     Test.stopTest();



    //     System.assert(true);
    // }





    @isTest
    static void testUpdateApplicationDetails_step9() {


        Basic__c b = [
            SELECT Id
            FROM Basic__c
            LIMIT 1
        ];



        Test.setMock(
            HttpCalloutMock.class,
            new PdfMock(b.Id)
        );



        Map<String,Object> body =
            new Map<String,Object>{

                'applicationId'=>b.Id,

                'currentStep'=>9,

                'application'=>new Map<String,Object>()
            };



        BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper =
            new BP_RequestWrappers.ApplicationDetailsDataWrapper(
                JSON.serialize(body)
            );



        Test.startTest();


        Map<String,Object> result =
            BP_PortalApplicationHelper.updateApplicationDetails(wrapper);


        Test.stopTest();



        System.assertEquals(
            'success',
            result.get('status')
        );
    }

    @isTest
    static void testUpdateApplicationDetailsEnvelope_null() {

        Map<String,Object> result =
            BP_PortalApplicationHelper.updateApplicationDetailsEnvelope(null);

        System.assertEquals('error', result.get('status'));
        System.assertEquals(
            'Application Id is null',
            result.get('message')
        );
    }


    @isTest
    static void testUpdateApplicationDetailsEnvelope_notFound() {

        BP_RequestWrappers.ShortApplicationDataWrapper wrapper =
            new BP_RequestWrappers.ShortApplicationDataWrapper(
                JSON.serialize(
                    new Map<String,Object>{
                        'applicationId' => 'a00000000000000AAA',
                        'isAutoSave' => false
                    }
                )
            );


        Map<String,Object> result =
            BP_PortalApplicationHelper.updateApplicationDetailsEnvelope(wrapper);


        System.assertEquals(
            'error',
            result.get('status')
        );

        System.assertEquals(
            'Not found application',
            result.get('message')
        );
    }



    @isTest
    static void testUpdateApplicationDetailsEnvelope_alreadyCreated() {

        Basic__c b = [
            SELECT Id
            FROM Basic__c
            LIMIT 1
        ];

        b.Is_envelope_created__c = true;
        update b;


        BP_RequestWrappers.ShortApplicationDataWrapper wrapper =
            new BP_RequestWrappers.ShortApplicationDataWrapper(
                JSON.serialize(
                    new Map<String,Object>{
                        'applicationId' => b.Id,
                        'isAutoSave' => false
                    }
                )
            );


        Map<String,Object> result =
            BP_PortalApplicationHelper.updateApplicationDetailsEnvelope(wrapper);


        System.assertEquals(
            'error',
            result.get('status')
        );

        System.assertEquals(
            'The form has already been successfully submitted',
            result.get('message')
        );
    }



    @isTest
    static void testUpdateApplicationDetailsEnvelope_trackA_success() {

        Basic__c b = [
            SELECT Id
            FROM Basic__c
            LIMIT 1
        ];


        Map<String,Object> body = new Map<String,Object>{
            'applicationId' => b.Id,
            'isAutoSave' => false,

            'application' => new Map<String,Object>{

                'track' => 'A',

                'client' => new Map<String,Object>{

                    'title' => 'Mr',
                    'firstName' => 'John',
                    'lastName' => 'Smith',
                    'email' => 'john@test.com',
                    'tel' => '0700000000',

                    'country' => 'GB',
                    'postcode' => 'SW1A 1AA',
                    'address1' => 'Street 1',
                    'address2' => 'Street 2',
                    'city' => 'London',

                    'pps' => '1234567',
                    'everLivedUK' => true,
                    'addressValidated' => true,
                    'verificationStatus' => 'Verified',
                    'wasCleansed' => true
                },

                'trackA' => new Map<String,Object>{
                    'nino' => 'AB123456C',
                    'hasNino' => 'Yes',
                    'isGettingUKStatePensionNow' => false
                }
            }
        };


        BP_RequestWrappers.ShortApplicationDataWrapper wrapper =
            new BP_RequestWrappers.ShortApplicationDataWrapper(
                JSON.serialize(body)
            );


        Test.startTest();

        Map<String,Object> result =
            BP_PortalApplicationHelper.updateApplicationDetailsEnvelope(wrapper);

        Test.stopTest();


        System.assertEquals(
            'success',
            result.get('status')
        );


        Basic__c updated = [
            SELECT
                Is_envelope_created__c,
                Track__c,
                First_Name__c,
                Last_Name__c,
                Claimant_nino__c,
                Claimant_hasNino__c
            FROM Basic__c
            WHERE Id = :b.Id
        ];


        System.assertEquals(true, updated.Is_envelope_created__c);
        System.assertEquals('A', updated.Track__c);
        System.assertEquals('John', updated.First_Name__c);
        System.assertEquals('Smith', updated.Last_Name__c);
        System.assertEquals('AB123456C', updated.Claimant_nino__c);
        System.assertEquals(true, updated.Claimant_hasNino__c);
    }

    @isTest
    static void testUpdateApplicationDetails_step3() {

        Basic__c b = [
            SELECT Id
            FROM Basic__c
            LIMIT 1
        ];

        Map<String,Object> body = new Map<String,Object>{
            'applicationId' => b.Id,
            'currentStep' => 3,
            'isAgentForm' => false,
            'application' => new Map<String,Object>{
                'partner' => new Map<String,Object>{
                    'title' => 'Mrs',
                    'surname' => 'Smith',
                    'otherNames' => 'Anna',
                    'firstName' => 'Anna',
                    'maidenName' => 'Brown',
                    'dob' => '1980-01-01T12:30:45Z',
                    'hasNino' => true,
                    'nino' => 'AB123456C',
                    'saveAsClaimant' => false,
                    'country' => 'GB',
                    'postcode' => 'SW1A1AA',
                    'address1' => 'Street 1',
                    'address2' => 'Street 2',
                    'city' => 'London',
                    'addressValidated' => true,
                    'verificationStatus' => 'Verified',
                    'wasCleansed' => true,
                    'everLivedUK' => true,
                    'everWorkedUK' => true,
                    'everLivedUKNotes' => 'Notes',
                    'claimingUKPension' =>  true,
                    'referenceOnAnyDWPLetters' =>  true
                }
            }
        };


        BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper =
            new BP_RequestWrappers.ApplicationDetailsDataWrapper(
                JSON.serialize(body)
            );


        Test.startTest();

        Map<String,Object> result =
            BP_PortalApplicationHelper.updateApplicationDetails(wrapper);

        Test.stopTest();


        System.assertEquals('success', result.get('status'));
    }



    @isTest
    static void testUpdateApplicationDetails_step4() {

        Basic__c b = [
            SELECT Id
            FROM Basic__c
            LIMIT 1
        ];


        Map<String,Object> body = new Map<String,Object>{
            'applicationId' => b.Id,
            'currentStep' => 4,
            'isAgentForm' => false,
            'application' => new Map<String,Object>{
                'claimantBenefits' => new Map<String,Object>{
                    'graduatedRetirement' =>  true,
                    'bereavement' =>  true,
                    'statePension' => true,
                    'widows' =>  true,
                    'isWaitingUkBenefits' => true,
                    'isWaitingUkBenefitsText' => 'Waiting'
                }
            }
        };


        BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper =
            new BP_RequestWrappers.ApplicationDetailsDataWrapper(
                JSON.serialize(body)
            );


        Test.startTest();

        Map<String,Object> result =
            BP_PortalApplicationHelper.updateApplicationDetails(wrapper);

        Test.stopTest();


        System.assertEquals('success', result.get('status'));
    }



    @isTest
    static void testUpdateApplicationDetails_step5() {

        Basic__c b = [
            SELECT Id
            FROM Basic__c
            LIMIT 1
        ];


        Map<String,Object> body = new Map<String,Object>{
            'applicationId' => b.Id,
            'currentStep' => 5,
            'isAgentForm' => false,
            'application' => new Map<String,Object>{
                'partnerBenefits' => new Map<String,Object>{
                    'graduatedRetirement' =>  true,
                    'bereavement' =>  true,
                    'statePension' =>  true,
                    'widows' =>  true,
                    'isWaitingUkBenefits' => false,
                    'isWaitingUkBenefitsText' => ''
                }
            }
        };


        BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper =
            new BP_RequestWrappers.ApplicationDetailsDataWrapper(
                JSON.serialize(body)
            );


        Test.startTest();

        Map<String,Object> result =
            BP_PortalApplicationHelper.updateApplicationDetails(wrapper);

        Test.stopTest();


        System.assertEquals('success', result.get('status'));
    }



    @isTest
    static void testUpdateApplicationDetails_step6() {

        Basic__c b = [
            SELECT Id
            FROM Basic__c
            LIMIT 1
        ];


        Map<String,Object> body = new Map<String,Object>{
            'applicationId' => b.Id,
            'currentStep' => 6,
            'isAgentForm' => false,
            'application' => new Map<String,Object>{
                'pension' => new Map<String,Object>{

                    'claimingFromToday' =>  true,
                    'deferredPension' =>  true,
                    'imprisonedSincePensionAge' =>  true,
                    'startDate' => '2025-01-01T12:30:45Z',
                    'workAfterPensionAge' =>  true,
                    'workInUKduring2years' =>  true,
                    'everSelfEmployedUKafter1978' =>  true,
                    'everPayReducedUKnino' =>  true
                }
            }
        };


        BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper =
            new BP_RequestWrappers.ApplicationDetailsDataWrapper(
                JSON.serialize(body)
            );


        Test.startTest();

        Map<String,Object> result =
            BP_PortalApplicationHelper.updateApplicationDetails(wrapper);

        Test.stopTest();


        System.assertEquals('success', result.get('status'));
    }

    @isTest
    static void testUpdateApplicationDetailsEnvelope_trackB_success() {

        Basic__c b = [
            SELECT Id
            FROM Basic__c
            LIMIT 1
        ];


        Map<String,Object> body = new Map<String,Object>{
            'applicationId' => b.Id,
            'isAutoSave' => false,

            'application' => new Map<String,Object>{

                'track' => 'B',

                'client' => new Map<String,Object>{
                    'title' => 'Mr',
                    'firstName' => 'John',
                    'lastName' => 'Smith',
                    'email' => 'john@test.com',
                    'tel' => '0700000000',
                    'country' => 'GB',
                    'postcode' => 'SW1A1AA',
                    'address1' => 'Street 1',
                    'city' => 'London',
                    'everLivedUK' => true
                },

                'trackB' => new Map<String,Object>{

                    'husbandAlive' => 'Yes',
                    'husbandHasNino' => 'Yes',
                    'youGettinStatePensionNow' => true,
                    'husbandGettinStatePensionNow' => false,

                    'husbandFirstName' => 'Peter',
                    'husbandOtherName' => 'Paul',
                    'husbandSurname' => 'Smith',

                    'husbandDob' => '1970-01-01T12:30:45Z',
                    'marriageDate' => '1990-01-01T12:30:45Z',
                    'husbandLeftUk' => '2010-01-01T12:30:45Z',

                    'sameAddress' => true,

                    'country' => 'GB',
                    'postcode' => 'SW1A1AA',
                    'address1' => 'Partner Street',
                    'address2' => 'Flat 1',
                    'city' => 'London',

                    'husbandHasNino' => 'Yes',
                    'husbandNino' => 'AB123456C',

                    'addressValidated' => true,
                    'verificationStatus' => 'Verified',
                    'wasCleansed' => true
                }
            }
        };


        BP_RequestWrappers.ShortApplicationDataWrapper wrapper =
            new BP_RequestWrappers.ShortApplicationDataWrapper(
                JSON.serialize(body)
            );


        Test.startTest();

        Map<String,Object> result =
            BP_PortalApplicationHelper.updateApplicationDetailsEnvelope(wrapper);

        Test.stopTest();


        System.assertEquals(
            'success',
            result.get('status')
        );


        Basic__c updated = [
            SELECT
                Is_envelope_created__c,
                Partner_First_Name__c,
                Partner_Surname__c,
                Partner_Nino__c,
                Is_Partner_alive__c
            FROM Basic__c
            WHERE Id = :b.Id
        ];


        System.assertEquals(true, updated.Is_envelope_created__c);
        System.assertEquals('Peter', updated.Partner_First_Name__c);
        System.assertEquals('Smith', updated.Partner_Surname__c);
        System.assertEquals('AB123456C', updated.Partner_Nino__c);
        System.assertEquals(true, updated.Is_Partner_alive__c);
    }



    @isTest
    static void testUpdateApplicationDetailsEnvelope_trackC_success() {

        Basic__c b = [
            SELECT Id
            FROM Basic__c
            LIMIT 1
        ];


        Map<String,Object> body = new Map<String,Object>{
            'applicationId' => b.Id,
            'isAutoSave' => false,

            'application' => new Map<String,Object>{

                'track' => 'C',

                'client' => new Map<String,Object>{
                    'title' => 'Mrs',
                    'firstName' => 'Anna',
                    'lastName' => 'Brown',
                    'email' => 'anna@test.com',
                    'tel' => '0700000000',
                    'country' => 'GB',
                    'postcode' => 'SW1A1AA',
                    'address1' => 'Street 1',
                    'city' => 'London',
                    'everLivedUK' => true
                },

                'trackC' => new Map<String,Object>{

                    'wifeDob' => '1975-01-01T12:30:45Z',

                    'marriageDate' => '1995-01-01T12:30:45Z',

                    'wifeLeftUK' => '2015-01-01T12:30:45Z',

                    'sameAddress' => false,

                    'country' => 'GB',
                    'postcode' => 'SW1A1AA',
                    'address1' => 'Partner Street',
                    'address2' => 'Flat 2',
                    'city' => 'London',

                    'wifeHasNino' => 'Yes',
                    'wifeNino' => 'AB654321C',

                    'addressValidated' => true,
                    'verificationStatus' => 'Verified',
                    'wasCleansed' => true
                }
            }
        };


        BP_RequestWrappers.ShortApplicationDataWrapper wrapper =
            new BP_RequestWrappers.ShortApplicationDataWrapper(
                JSON.serialize(body)
            );


        Test.startTest();

        Map<String,Object> result =
            BP_PortalApplicationHelper.updateApplicationDetailsEnvelope(wrapper);

        Test.stopTest();


        System.assertEquals(
            'success',
            result.get('status')
        );


        Basic__c updated = [
            SELECT
                Is_envelope_created__c,
                Partner_Nino__c,
                Partner_Country_Code__c,
                Partner_same_as_claimant__c
            FROM Basic__c
            WHERE Id = :b.Id
        ];


        System.assertEquals(true, updated.Is_envelope_created__c);
        System.assertEquals('AB654321C', updated.Partner_Nino__c);
        System.assertEquals('GB', updated.Partner_Country_Code__c);
        System.assertEquals(false, updated.Partner_same_as_claimant__c);
    }

    private class IntentMock implements HttpCalloutMock {
        private String intentStatus;
        private Integer intentAmount;

        IntentMock(String intentStatus, Integer intentAmount) {
            this.intentStatus = intentStatus;
            this.intentAmount = intentAmount;
        }

        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id":"ch_123","status":"' + intentStatus + '","amount":' + intentAmount
                + ',"amount_received":' + intentAmount + ',"currency":"eur","customer":"cus_123",'
                + '"card":{"brand":"visa","last4":"4242"}}');
            res.setStatusCode(200);
            return res;
        }
    }

    private static BP_RequestWrappers.ApplicationCreateDataWrapper wrapperWithAmount(Integer amount) {
        return new BP_RequestWrappers.ApplicationCreateDataWrapper(JSON.serialize(new Map<String, Object>{
            'id' => 'ch_123',
            'amount' => amount,
            'currencyCode' => 'EUR',
            'email' => 'new.client@test.com',
            'phone' => '0700000000',
            'name' => 'New Client',
            'firstName' => 'New',
            'lastName' => 'Client',
            'paymentMethod' => 'card',
            'customer' => 'cus_123',
            'address' => new Map<String, Object>{
                'street' => 'Street 1',
                'city' => 'Dublin',
                'country' => 'IE',
                'postalCode' => 'D01'
            }
        }));
    }

    @isTest
    static void testCreateApplication_rejectsPaymentThatDidNotSucceed() {
        Test.setMock(HttpCalloutMock.class, new IntentMock('requires_payment_method', 5000));
        Integer before = [SELECT COUNT() FROM Basic__c];

        Map<String, Object> result = BP_PortalApplicationHelper.createApplication(wrapperWithAmount(5000));

        System.assertEquals('error', result.get('status'));
        System.assertEquals(before, [SELECT COUNT() FROM Basic__c], 'No claim may be created for an unpaid intent');
    }

    @isTest
    static void testCreateApplication_rejectsAmountThatDoesNotMatchStripe() {
        Test.setMock(HttpCalloutMock.class, new IntentMock('succeeded', 5000));
        Integer before = [SELECT COUNT() FROM Basic__c];

        Map<String, Object> result = BP_PortalApplicationHelper.createApplication(wrapperWithAmount(1));

        System.assertEquals('error', result.get('status'));
        System.assertEquals(before, [SELECT COUNT() FROM Basic__c]);
    }

    @isTest
    static void testCreateApplication_isIdempotentOnTheStripeId() {
        Basic__c existing = [SELECT Id FROM Basic__c LIMIT 1];
        update new Basic__c(Id = existing.Id, Stripe_Transaction_Id__c = 'ch_123');
        Integer before = [SELECT COUNT() FROM Basic__c];

        Map<String, Object> result = BP_PortalApplicationHelper.createApplication(wrapperWithAmount(5000));

        System.assertEquals('success', result.get('status'));
        System.assertEquals(String.valueOf(existing.Id), result.get('applicationId'));
        System.assertEquals(before, [SELECT COUNT() FROM Basic__c], 'A retried payment must not create a second claim');
    }

    @isTest
static void testCreateApplication_blankPaymentIntentId() {
    BP_RequestWrappers.ApplicationCreateDataWrapper wrapper =
        new BP_RequestWrappers.ApplicationCreateDataWrapper(JSON.serialize(new Map<String,Object>{
            'id' => '',
            'email' => 'x@test.com',
            'firstName' => 'A',
            'lastName' => 'B'
        }));

    Test.startTest();
    Map<String,Object> result = BP_PortalApplicationHelper.createApplication(wrapper);
    Test.stopTest();

    System.assertEquals('error', result.get('status'));
    System.assertEquals('Payment intent id is required', result.get('message'));
}

@isTest
static void testCreateApplication_rejectsNullWrapper() {
    Test.startTest();
    Map<String,Object> result = BP_PortalApplicationHelper.createApplication(null);
    Test.stopTest();

    System.assertEquals('error', result.get('status'));
    System.assertEquals('Application data is empty', result.get('message'));
}


// ---------- createApplication: verifyStripePayment error paths ----------

private class StripeErrorMock implements HttpCalloutMock {
    private Integer statusCode;
    private String  body;
    StripeErrorMock(Integer statusCode, String body) {
        this.statusCode = statusCode;
        this.body = body;
    }
    public HTTPResponse respond(HTTPRequest req) {
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setStatusCode(statusCode == null ? 500 : statusCode);
        res.setBody(body == null ? '{}' : body);
        return res;
    }
}

@isTest
static void testCreateApplication_stripeVerificationFails() {
    Test.setMock(HttpCalloutMock.class, new StripeErrorMock(500, '{"error":{"message":"boom"}}'));
    Integer before = [SELECT COUNT() FROM Basic__c];

    Test.startTest();
    Map<String,Object> result = BP_PortalApplicationHelper.createApplication(wrapperWithAmount(5000));
    Test.stopTest();

    System.assertEquals('error', result.get('status'));
    System.assert(((String) result.get('message')).contains('Payment could not be verified'));
    System.assertEquals(before, [SELECT COUNT() FROM Basic__c]);
}

@isTest
static void testCreateApplication_rejectsCurrencyMismatch() {
    // Stripe returns EUR, wrapper sends USD
    Test.setMock(HttpCalloutMock.class, new StripeErrorMock(200,
        '{"id":"pi_1","status":"succeeded","amount_received":5000,"currency":"eur","customer":"cus_123"}'
    ));

    BP_RequestWrappers.ApplicationCreateDataWrapper wrapper =
        new BP_RequestWrappers.ApplicationCreateDataWrapper(JSON.serialize(new Map<String,Object>{
            'id' => 'pi_1',
            'amount' => 5000,
            'currencyCode' => 'USD',
            'email' => 'x@test.com',
            'firstName' => 'A',
            'lastName' => 'B',
            'customer' => 'cus_123'
        }));

    Test.startTest();
    Map<String,Object> result = BP_PortalApplicationHelper.createApplication(wrapper);
    Test.stopTest();

    System.assertEquals('error', result.get('status'));
    System.assertEquals('Payment currency does not match', result.get('message'));
}

@isTest
static void testCreateApplication_rejectsCustomerMismatch() {
    Test.setMock(HttpCalloutMock.class, new StripeErrorMock(200,
        '{"id":"pi_1","status":"succeeded","amount_received":5000,"currency":"eur","customer":"cus_REAL"}'
    ));

    BP_RequestWrappers.ApplicationCreateDataWrapper wrapper =
        new BP_RequestWrappers.ApplicationCreateDataWrapper(JSON.serialize(new Map<String,Object>{
            'id' => 'pi_1',
            'amount' => 5000,
            'currencyCode' => 'EUR',
            'email' => 'x@test.com',
            'firstName' => 'A',
            'lastName' => 'B',
            'customer' => 'cus_FAKE'
        }));

    Test.startTest();
    Map<String,Object> result = BP_PortalApplicationHelper.createApplication(wrapper);
    Test.stopTest();

    System.assertEquals('error', result.get('status'));
    System.assertEquals('Payment customer does not match', result.get('message'));
}


// ---------- createApplication: success path with proper stripe mock ----------

private class FullSuccessMock implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setStatusCode(200);

        String endpoint = req.getEndpoint();

        if (endpoint.contains('/payment_intents/')) {
            res.setBody('{"id":"pi_ok","status":"succeeded","amount_received":5000,'
                + '"currency":"eur","customer":"cus_ok","payment_method":"pm_ok",'
                + '"latest_charge":"ch_ok"}');
        } else if (endpoint.contains('/payment_methods/')) {
            res.setBody('{"id":"pm_ok","card":{"brand":"visa","last4":"4242"}}');
        } else {
            res.setBody('{}');
        }
        return res;
    }
}

@isTest
static void testCreateApplication_fullSuccessPath() {
    Test.setMock(HttpCalloutMock.class, new FullSuccessMock());
    Integer before = [SELECT COUNT() FROM Basic__c];

    BP_RequestWrappers.ApplicationCreateDataWrapper wrapper =
        new BP_RequestWrappers.ApplicationCreateDataWrapper(JSON.serialize(new Map<String,Object>{
            'id' => 'pi_ok',
            'amount' => 5000,
            'currencyCode' => 'EUR',
            'email' => 'brand.new@test.com',
            'phone' => '0700000000',
            'name' => 'New Client',
            'firstName' => 'New',
            'lastName' => 'Client',
            'paymentMethod' => 'pm_ok',
            'customer' => 'cus_ok',
            'latest_charge' => 'ch_ok',
            'agent' => 'None',
            'address' => new Map<String,Object>{
                'street' => 'Street 1, Street 2',
                'city' => 'Dublin',
                'country' => 'IE',
                'state' => 'Dublin',
                'postalCode' => 'D01'
            }
        }));

    Test.startTest();
    Map<String,Object> result = BP_PortalApplicationHelper.createApplication(wrapper);
    Test.stopTest();

    System.assertEquals('success', result.get('status'));
    System.assertNotEquals(null, result.get('applicationId'));
    System.assertEquals(before + 1, [SELECT COUNT() FROM Basic__c]);
}


// ---------- getApplicationDetail: error paths ----------

@isTest
static void testGetApplicationDetail_nullWrapper() {
    Test.startTest();
    Map<String,Object> result = BP_PortalApplicationHelper.getApplicationDetail(null);
    Test.stopTest();

    System.assertEquals('error', result.get('status'));
    System.assertEquals('Application Id is null', result.get('message'));
}

@isTest
static void testGetApplicationDetail_notFound() {
    BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper =
        new BP_RequestWrappers.ApplicationDetailsDataWrapper(JSON.serialize(new Map<String,Object>{
            'applicationId' => 'a00000000000000AAA'
        }));

    Test.startTest();
    Map<String,Object> result = BP_PortalApplicationHelper.getApplicationDetail(wrapper);
    Test.stopTest();

    System.assertEquals('error', result.get('status'));
    System.assertEquals('Not found application', result.get('message'));
}

// ---------- updateApplicationDetails: error paths ----------

@isTest
static void testUpdateApplicationDetails_nullWrapper() {
    Test.startTest();
    Map<String,Object> result = BP_PortalApplicationHelper.updateApplicationDetails(null);
    Test.stopTest();

    System.assertEquals('error', result.get('status'));
    System.assertEquals('Input data is null', result.get('message'));
}

@isTest
static void testUpdateApplicationDetails_notFound() {
    BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper =
        new BP_RequestWrappers.ApplicationDetailsDataWrapper(JSON.serialize(new Map<String,Object>{
            'applicationId' => 'a00000000000000AAA',
            'currentStep' => 1
        }));

    Test.startTest();
    Map<String,Object> result = BP_PortalApplicationHelper.updateApplicationDetails(wrapper);
    Test.stopTest();

    System.assertEquals('error', result.get('status'));
    System.assertEquals('Not found application', result.get('message'));
}

// ---------- getApplicationEnvelopeFill: error paths ----------

@isTest
static void testGetApplicationEnvelopeFill_nullWrapper() {
    Test.startTest();
    Map<String,Object> result = BP_PortalApplicationHelper.getApplicationEnvelopeFill(null);
    Test.stopTest();

    System.assertEquals('error', result.get('status'));
    System.assertEquals('Application Id is null', result.get('message'));
}

@isTest
static void testGetApplicationEnvelopeFill_notFound() {
    BP_RequestWrappers.ShortApplicationDataWrapper wrapper =
        new BP_RequestWrappers.ShortApplicationDataWrapper(JSON.serialize(new Map<String,Object>{
            'applicationId' => 'a00000000000000AAA'
        }));

    Test.startTest();
    Map<String,Object> result = BP_PortalApplicationHelper.getApplicationEnvelopeFill(wrapper);
    Test.stopTest();

    System.assertEquals('error', result.get('status'));
    System.assertEquals('Not found application', result.get('message'));
}

@isTest
static void testGetApplicationEnvelopeFill_alreadyCreated() {
    Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];
    update new Basic__c(Id = b.Id, Is_envelope_created__c = true);

    BP_RequestWrappers.ShortApplicationDataWrapper wrapper =
        new BP_RequestWrappers.ShortApplicationDataWrapper(JSON.serialize(new Map<String,Object>{
            'applicationId' => b.Id
        }));

    Test.startTest();
    Map<String,Object> result = BP_PortalApplicationHelper.getApplicationEnvelopeFill(wrapper);
    Test.stopTest();

    System.assertEquals('error', result.get('status'));
    System.assertEquals('The form has already been successfully submitted', result.get('message'));
}


// ---------- getApplicationFill: not found ----------

@isTest
static void testGetApplicationFill_notFound() {
    BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper =
        new BP_RequestWrappers.ApplicationDetailsDataWrapper(JSON.serialize(new Map<String,Object>{
            'applicationId' => 'a00000000000000AAA'
        }));

    Test.startTest();
    Map<String,Object> result = BP_PortalApplicationHelper.getApplicationFill(wrapper);
    Test.stopTest();

    System.assertEquals('error', result.get('status'));
    System.assertEquals('Not found application', result.get('message'));
}


// ---------- validateBank: validation branches ----------

@isTest
static void testValidateBank_sortCodeMissing() {
    Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];

    BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper =
        new BP_RequestWrappers.ApplicationDetailsDataWrapper(JSON.serialize(new Map<String,Object>{
            'applicationId' => b.Id,
            'application' => new Map<String,Object>{
                'bank' => new Map<String,Object>{
                    'account' => '12345678'
                    // no sortCode, no bic, no iban
                }
            }
        }));

    Test.startTest();
    Map<String,Object> result = BP_PortalApplicationHelper.validateBank(wrapper);
    Test.stopTest();

    System.assertEquals('error', result.get('status'));
    System.assertEquals('Sort code missing', result.get('message'));
}

@isTest
static void testValidateBank_accountNumberMissing() {
    Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];

    BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper =
        new BP_RequestWrappers.ApplicationDetailsDataWrapper(JSON.serialize(new Map<String,Object>{
            'applicationId' => b.Id,
            'application' => new Map<String,Object>{
                'bank' => new Map<String,Object>{
                    'sortCode' => '11-22-33'
                    // no account, no bic, no iban
                },
                'claimant' => new Map<String,Object>{
                    'country' => 'GB'
                }
            }
        }));

    Test.startTest();
    Map<String,Object> result = BP_PortalApplicationHelper.validateBank(wrapper);
    Test.stopTest();

    System.assertEquals('error', result.get('status'));
    System.assertEquals('Account number missing', result.get('message'));
}

@isTest
static void testValidateBank_bicOrIbanMissing() {
    Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];

    BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper =
        new BP_RequestWrappers.ApplicationDetailsDataWrapper(JSON.serialize(new Map<String,Object>{
            'applicationId' => b.Id,
            'application' => new Map<String,Object>{
                'bank' => new Map<String,Object>{
                    'account' => '12345678'
                    // all other fields blank
                },
                'claimant' => new Map<String,Object>{
                    'country' => 'GB'
                }
            }
        }));

    Test.startTest();
    Map<String,Object> result = BP_PortalApplicationHelper.validateBank(wrapper);
    Test.stopTest();

    System.assertEquals('error', result.get('status'));
    System.assertEquals('Sort code missing', result.get('message'));
}

@isTest
static void testValidateBank_auCountrySuccess() {
    Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];

    BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper =
        new BP_RequestWrappers.ApplicationDetailsDataWrapper(JSON.serialize(new Map<String,Object>{
            'applicationId' => b.Id,
            'application' => new Map<String,Object>{
                'bank' => new Map<String,Object>{
                    'account' => '12345678',
                    'bic' => 'TESTAU',
                    'sortCode' => '11-22-33'
                },
                'claimant' => new Map<String,Object>{
                    'country' => 'AU'
                }
            }
        }));

    Test.setMock(HttpCalloutMock.class, new BankMock());

    Test.startTest();
    Map<String,Object> result = BP_PortalApplicationHelper.validateBank(wrapper);
    Test.stopTest();

    System.assertEquals('success', result.get('status'));
}



// ---------- updateApplicationDetailsEnvelope: null wrapper ----------

@isTest
static void testUpdateApplicationDetailsEnvelope_nullWrapper() {
    Test.startTest();
    Map<String,Object> result =
        BP_PortalApplicationHelper.updateApplicationDetailsEnvelope(null);
    Test.stopTest();

    System.assertEquals('error', result.get('status'));
    System.assertEquals('Application Id is null', result.get('message'));
}

}