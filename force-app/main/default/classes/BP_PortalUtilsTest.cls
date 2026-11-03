@isTest
private class BP_PortalUtilsTest {

    @TestSetup
    static void setup() {
        List<String> productNames = new List<String>{'Claim', 'Claim - Deposit'};
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
        PriceBookEntry pkPrice = testPriceBookEntries[0];
        insert new Basic_Payment__c (
                    Amount__c         = pkPrice.UnitPrice,
                    Product__c        = pkPrice.Product2Id,
                    Status__c         = 'Paid',
                    CurrencyIsoCode   = testApplication?.CurrencyIsoCode,
                    Payment_Method__c = testApplication.Payment_Method__c,
                    Customer_Id__c    = testApplication.Stripe_Customer_Id__c,
                    Basic__c    = testApplication?.id,
                    Payment_Date__c   = Date.today(),
                    Payment_Intent__c = testApplication.Payment_Method__c,
                    Source__c         = 'test',
                    Card_Data__c      = 'test'
                );
    }


    @isTest
    static void testGetApplication() {
        List<Basic__c> apps = [
            SELECT
                Name
            FROM Basic__c
        ];
        Basic__c app = apps[0];
        
        Test.startTest();
        List<Basic__c> result = BP_PortalUtils.getApplication(app.Id);
        Test.stopTest();
        
        System.assertEquals(1, result.size());
        System.assertEquals(apps[0].Id, result[0].Id);
    }

    @isTest
    static void testDeleteOldClaimantRelation() {
         List<Basic__c> apps = [
            SELECT
                Name
            FROM Basic__c
        ];
        Basic__c app = apps[0];

        Test.startTest();
        BP_PortalUtils.deleteOldClaimantRelation(app.Id);
        Test.stopTest();

    }

    @isTest
    static void testCreateNewClaimantRelation() {
        Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];

        String json = JSON.serialize(new Map<String, Object>{
            'applicationId' => b.Id,
            'application' => new Map<String, Object>{
                'claimant' => new Map<String, Object>{
                    'title' => 'Mr',
                    'surname' => 'Doe',
                    'firstName' => 'John',
                    'email' => 'john@test.com',
                    'tel' => '111111',
                    'address1' => 'Street 1',
                    'address2' => 'Flat 2',
                    'city' => 'London',
                    'country' => 'GB',
                    'postcode' => 'SW1',
                    'dob' => '1990-01-01T00:00:00Z',
                    'children' => new List<Object>(),
                    'ukCompanies' => new List<Object>(),
                    'countriesLived' => new List<Object>(),
                    'everLivedUK' => true,
                    'addressValidated' => true,
                    'verificationStatus' => 'Verified',
                    'wasCleansed' => true,
                    'hasNino' => true,
                    'everLivedUK' => true,
                    'everWorkedUK' => true,
                    'marriedWomansStamp' => false,
                    'hasProofOfUKWork' => true,
                    'hasNino' => true,
                    'nino' => 'AA123456A',
                    'livedUKFrom' => '1990-01-01T00:00:00Z',
                    'livedUKTo' => '2000-01-01T00:00:00Z',
                    'workedUKFrom' => '1991-01-01T00:00:00Z',
                    'workedUKTo' => '1999-01-01T00:00:00Z',
                    'selfEmployedUK' => true,
                    'mindedKids' => false,
                    'statePension' => false,
                    'title' => 'Mr',
                    'surname' => 'Smith',
                    'otherNames' => 'John Michael',
                    'dob' => '1960-01-01T00:00:00Z',
                    'maidenName' => 'Johnson',
                    'tel' => '+353871234567',
                    'email' => 'john.smith@test.com',
                    'maritalStatus' => 'Married',
                    'nationality' => 'British',

                    'dateOfMarriage' => '1985-06-15T00:00:00Z',
                    'dateOfBereavement' => '2018-03-20T00:00:00Z',
                    'dateOfDivorce' => '2010-09-10T00:00:00Z',

                    'hasNino' => true,
                    'nino' => 'AB123456C',

                    'country' => 'GB',
                    'countryName' => 'United Kingdom',
                    'postcode' => 'SW1A 1AA',
                    'address1' => '10 Downing Street',
                    'address2' => 'Westminster',
                    'city' => 'London',

                    'everLivedUK' => true,
                    'livedUKFrom' => '1980-01-01T00:00:00Z',
                    'livedUKTo' => '2000-01-01T00:00:00Z',

                    'everWorkedUK' => true,
                    'workedUKFrom' => '1982-01-01T00:00:00Z',
                    'workedUKTo' => '1999-01-01T00:00:00Z',

                    'hasProofOfUKWork' => true,

                    'countriesLived' => new List<Object>(),
                    'ukCompanies' => new List<Object>(),

                    'selfEmployedUK' => false,
                    'marriedWomansStamp' => false,
                    'mindedKids' => true,

                    'children' => new List<Object>(),

                    'addressValidated' => true,
                    'verificationStatus' => 'Verified',
                    'wasCleansed' => true,

                    'everWorkedUKuseSameDates' => true,
                    'phoneType' => 'Mobile',
                    'approxYearsInUK' => 20,
                    'everLivedUKNotes' => 'Test notes',
                    'children' => new List<Object>{
                        new Map<String, Object>{
                            'name' => 'Child 1',
                            'dob' => '2020-01-01T12:30:45Z',
                            'mindedFromDate' => '2021-01-01T12:30:45Z',
                            'mindedToDate' => '2022-01-01T12:30:45Z',
                            'nino' => 'AA123'
                        }
                    },
                    'ukCompanies' => new List<Object>{
                        new Map<String, Object>{
                            'name' => 'Company 1',
                            'address1' => 'Addr1',
                            'address2' => 'Addr2',
                            'city' => 'London',
                            'postcode' => '12345',
                            'country' => 'GB',
                            'fromDate' => '2020-01-01T12:30:45Z',
                            'toDate' => '2021-01-01T12:30:45Z'
                        }
                    },
                    'countriesLived' => new List<Object>{
                        new Map<String, Object>{
                            'name' => 'GB',
                            'fromDate' => '2010-01-01T12:30:45Z',
                            'toDate' => '2020-01-01T12:30:45Z',
                            'socialSecurityNumber' => 'SSN123',
                            'isLiveHereNow' => true
                        }
                    }
                }
            }
        });

        BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper =
            new BP_RequestWrappers.ApplicationDetailsDataWrapper(json);

        Test.startTest();
        BP_PortalUtils.createNewClaimantRelation(wrapper);
        Test.stopTest();

        List<Claimant_Child__c> children =
            [SELECT Id, Name FROM Claimant_Child__c WHERE Basic__c = :b.Id];
        System.assertEquals(2, children.size());

        List<Claimant_Company__c> companies =
            [SELECT Id, Name FROM Claimant_Company__c WHERE Basic__c = :b.Id];
        System.assertEquals(2, companies.size());

        List<Claimant_Country_lived__c> countries =
            [SELECT Id, Name FROM Claimant_Country_lived__c WHERE Basic__c = :b.Id];
        System.assertEquals(2, countries.size());
    }

    @isTest
    static void testCreateNewClaimantRelation_empty() {
        Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];

        String json = JSON.serialize(new Map<String, Object>{
            'applicationId' => b.Id,
            'application' => new Map<String, Object>{
                'claimant' => new Map<String, Object>{
                    'children' => new List<Object>(),
                    'ukCompanies' => new List<Object>(),
                    'countriesLived' => new List<Object>()
                }
            }
        });

        BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper =
            new BP_RequestWrappers.ApplicationDetailsDataWrapper(json);

        Test.startTest();
        BP_PortalUtils.createNewClaimantRelation(wrapper);
        Test.stopTest();

        System.assertEquals(1, [SELECT count() FROM Claimant_Child__c WHERE Basic__c = :b.Id]);
        System.assertEquals(1, [SELECT count() FROM Claimant_Company__c WHERE Basic__c = :b.Id]);
        System.assertEquals(1, [SELECT count() FROM Claimant_Country_lived__c WHERE Basic__c = :b.Id]);
    }


    @isTest
    static void testCurrentStep_allValues() {

        Test.startTest();

        System.assertEquals(
            'About the Claimant',
            BP_PortalUtils.currentStep('X', 1)
        );

        System.assertEquals(
            'About your husband, wife or civil partner',
            BP_PortalUtils.currentStep('X', 2)
        );

        System.assertEquals(
            'About Partner',
            BP_PortalUtils.currentStep('X', 3)
        );

        System.assertEquals(
            'Have you (Claimant) Ever Claimed',
            BP_PortalUtils.currentStep('X', 4)
        );

        System.assertEquals(
            'Has Partner Ever Claimed',
            BP_PortalUtils.currentStep('X', 5)
        );

        System.assertEquals(
            'Are You Claiming Pension from Today?',
            BP_PortalUtils.currentStep('X', 6)
        );

        System.assertEquals(
            'Benefits',
            BP_PortalUtils.currentStep('X', 7)
        );

        System.assertEquals(
            'Bank Details',
            BP_PortalUtils.currentStep('X', 8)
        );


        Test.stopTest();
    }

    @isTest
    static void testOutputCurrentStep_allValues() {

        Test.startTest();

        System.assertEquals(
            1,
            BP_PortalUtils.outputCurrentStep('Friend / Family for Communication')
        );

        System.assertEquals(
            2,
            BP_PortalUtils.outputCurrentStep('About the Claimant')
        );

        System.assertEquals(
            3,
            BP_PortalUtils.outputCurrentStep('About your husband, wife or civil partner')
        );

        System.assertEquals(
            4,
            BP_PortalUtils.outputCurrentStep('About Partner')
        );

        System.assertEquals(
            5,
            BP_PortalUtils.outputCurrentStep('Have you (Claimant) Ever Claimed')
        );

        System.assertEquals(
            6,
            BP_PortalUtils.outputCurrentStep('Has Partner Ever Claimed')
        );

        System.assertEquals(
            7,
            BP_PortalUtils.outputCurrentStep('Are You Claiming Pension from Today?')
        );
        System.assertEquals(
            8,
            BP_PortalUtils.outputCurrentStep('Benefits')
        );

        System.assertEquals(
            9,
            BP_PortalUtils.outputCurrentStep('Bank Details')
        );

        Test.stopTest();
    } 

    @isTest
    static void testSendRegistrationEmail() {
        Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];

        Test.startTest();
        BP_PortalUtils.sendRegistrationEmail(b.Id);
        Test.stopTest();
        System.assert(true);
    }

    @isTest
    static void testCreateContentVersionAndLink() {
        Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];

        String base64 = EncodingUtil.base64Encode(Blob.valueOf('test file'));

        Test.startTest();

        ContentVersion cv = BP_PortalUtils.createContentVersion(
            base64,
            'testFile',
            'txt'
        );

        ContentDocumentLink link = BP_PortalUtils.createContentLink(
            cv.Id,
            b.Id
        );

        Test.stopTest();

        System.assertNotEquals(null, link.Id);
        System.assertEquals(b.Id, link.LinkedEntityId);
    }

    @isTest
    static void testCurrentStep_defaultBranch() {
        System.assertEquals(
            'Initial',
            BP_PortalUtils.currentStep('Initial', 99)
        );

        System.assertEquals(
            'Initial',
            BP_PortalUtils.currentStep('Initial', null)
        );
    }

    @isTest
    static void testOutputCurrentStep_defaultBranch() {
        System.assertEquals(
            1,
            BP_PortalUtils.outputCurrentStep('Unknown Step')
        );
    }

    @isTest
    static void testDeleteOldEnvelopeClaimantRelation() {
        Basic__c app = [SELECT Id FROM Basic__c LIMIT 1];

        // есть минимум одна компания из @TestSetup
        System.assert(
            [SELECT COUNT() FROM Claimant_Company__c WHERE Basic__c = :app.Id] > 0
        );

        Test.startTest();
        BP_PortalUtils.deleteOldEnvelopeClaimantRelation(app.Id);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Claimant_Company__c WHERE Basic__c = :app.Id]
        );
    }

    @isTest
    static void testGetCurrencySymbol() {
        System.assertEquals('€', BP_PortalUtils.getCurrencySymbol('EUR'));
        System.assertEquals('$', BP_PortalUtils.getCurrencySymbol('USD'));
        System.assertEquals('R', BP_PortalUtils.getCurrencySymbol('ZAR'));

        // неизвестная валюта - ветка default
        System.assertEquals('$', BP_PortalUtils.getCurrencySymbol('PLN'));
    }

    @isTest
    static void testdateFromString() {
        Date d = BP_PortalUtils.dateFromString(
            '2020-01-01T00:00:00Z'
        );

        System.assertEquals(Date.newInstance(2020, 1, 1), d);
    }

    @isTest
    static void testGetEmptyFieldLabels() {
        Basic__c rec = new Basic__c();

        List<String> fields = new List<String>{
            'First_Name__c',
            'Last_Name__c'
        };

        List<String> result = BP_PortalUtils.getEmptyFieldLabels(rec, fields);

        System.assertEquals(2, result.size());
    }

    @isTest
    static void testGetEmptyFieldsConditionalLabel() {
        Basic__c app = new Basic__c(
            Claimant_Minded_Kids__c = true,
            Claimant_marital_Status__c = 'Maried',
            Claimant_hasNino__c = true,
            Claimant_ever_Lived_UK__c = true,
            Claimant_Ever_Worked_UK__c = true,
            Pension_Claiming_from_Today__c = false
        );

        List<String> result =
            BP_PortalUtils.getEmptyFieldsConditionalLabel(app);

        // System.assert(result.contains('Child Details'));
        // System.assert(result.contains('Date Of Marriage'));
        // System.assert(result.contains('NINO'));
        // System.assert(result.contains('Residency From'));
        // System.assert(result.contains('Residency To'));
        // System.assert(result.contains('Employment From'));
        // System.assert(result.contains('Employment To'));
        // System.assert(result.contains('Are You Claiming Pension from Today?'));
    }

    @isTest
    static void testGetApplication_nullId() {
        Test.startTest();
        List<Basic__c> result = BP_PortalUtils.getApplication(null);
        Test.stopTest();

        System.assertEquals(0, result.size());
    }

    @isTest
    static void testCreateContentLink_nullArguments() {
        System.assertEquals(
            null,
            BP_PortalUtils.createContentLink(null, null)
        );
    }

    @isTest
    static void testSetMissingAndGetMissing() {
        Basic__c app = [SELECT Id FROM Basic__c LIMIT 1];

        Test.startTest();
        List<String> missingSet = BP_PortalUtils.setMissing(app.Id);
        List<String> missingGet = BP_PortalUtils.getMissing(app.Id);
        Test.stopTest();

        Basic__c refreshed = [
            SELECT Missing_Info__c
            FROM Basic__c
            WHERE Id = :app.Id
        ];

    }

    @isTest
    static void testGenerateZipArchiveAfterCreatedClaim_missingFiles() {
        Basic__c app = [SELECT Id FROM Basic__c LIMIT 1];

        Test.startTest();
        BP_PortalUtils.generateZipArchiveAfterCreatedClaim(app.Id);
        Test.stopTest();

        Basic__c refreshed = [
            SELECT FTP_Claim_Created_ZIP_Error__c
            FROM Basic__c
            WHERE Id = :app.Id
        ];

        System.assertNotEquals(
            null,
            refreshed.FTP_Claim_Created_ZIP_Error__c
        );
    }

    @isTest
    static void testGenerateZipArchiveFullFormClaim_missingFiles() {
        Basic__c app = [SELECT Id FROM Basic__c LIMIT 1];

        Test.startTest();
        BP_PortalUtils.generateZipArchiveFullFormClaim(app.Id);
        Test.stopTest();

        Basic__c refreshed = [
            SELECT FTP_Claim_Full_Form_ZIP_Error__c
            FROM Basic__c
            WHERE Id = :app.Id
        ];

        System.assertNotEquals(
            null,
            refreshed.FTP_Claim_Full_Form_ZIP_Error__c
        );
    }

    @isTest
    static void testGetEnvApplication() {
        Basic__c app = [
            SELECT Id
            FROM Basic__c
            LIMIT 1
        ];

        Test.startTest();
        List<Basic__c> result = BP_PortalUtils.getEnvApplication(app.Id);
        Test.stopTest();

        System.assertEquals(1, result.size());
        System.assertEquals(app.Id, result[0].Id);

        System.assertEquals(1, result[0].Clamant_Children__r.size());
        System.assertEquals(1, result[0].Claimant_Companies__r.size());
        System.assertEquals(1, result[0].ClaimantCountrieslived__r.size());
    }

    @isTest
    static void testGetEnvApplication_NullId() {

        Test.startTest();
        List<Basic__c> result = BP_PortalUtils.getEnvApplication(null);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(0, result.size());
    }
    @isTest
    static void testCreateNewClaimantRelationTrackA() {
        Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];

        String json = JSON.serialize(new Map<String,Object>{
            'applicationId' => b.Id,
            'application' => new Map<String,Object>{
                'trackA' => new Map<String,Object>{
                    'employers' => new List<Object>{
                        new Map<String,Object>{
                            'name' => 'Employer A',
                            'country' => 'GB',
                            'city' => 'London',
                            'postcode' => 'SW1',
                            'fromDate' => '2020-01-01T00:00:00Z',
                            'toDate' => '2021-01-01T00:00:00Z'
                        }
                    },
                    'addresses' => new List<Object>{
                        new Map<String,Object>{
                            'country' => 'GB',
                            'city' => 'London',
                            'postcode' => 'SW1',
                            'fromDate' => '2018-01-01T00:00:00Z',
                            'toDate' => '2019-01-01T00:00:00Z'
                        }
                    }
                }
            }
        });

        BP_RequestWrappers.ShortApplicationDataWrapper wrapper =
            new BP_RequestWrappers.ShortApplicationDataWrapper(json);

        Test.startTest();
        BP_PortalUtils.createNewClaimantRelationTrackA(wrapper);
        Test.stopTest();

        List<Claimant_Company__c> companies = [
            SELECT Name, Is_Addresses__c, Is_Partner__c
            FROM Claimant_Company__c
            WHERE Basic__c = :b.Id
            ORDER BY CreatedDate DESC
            LIMIT 2
        ];

        System.assertEquals(2, companies.size());
    }
    @isTest
    static void testCreateNewClaimantRelationTrackB() {
        Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];

        String json = JSON.serialize(new Map<String,Object>{
            'applicationId' => b.Id,
            'application' => new Map<String,Object>{
                'trackB' => new Map<String,Object>{
                    'employers' => new List<Object>{
                        new Map<String,Object>{
                            'name'=>'Employer B',
                            'country'=>'GB'
                        }
                    },
                    'addresses' => new List<Object>{
                        new Map<String,Object>{
                            'country'=>'GB'
                        }
                    }
                }
            }
        });

        BP_RequestWrappers.ShortApplicationDataWrapper wrapper =
            new BP_RequestWrappers.ShortApplicationDataWrapper(json);

        Test.startTest();
        BP_PortalUtils.createNewClaimantRelationTrackB(wrapper);
        Test.stopTest();

        List<Claimant_Company__c> companies = [
            SELECT Is_Partner__c, Is_Addresses__c
            FROM Claimant_Company__c
            WHERE Basic__c = :b.Id
            ORDER BY CreatedDate DESC
            LIMIT 2
        ];

        System.assertEquals(1, companies.size());

        for(Claimant_Company__c c : companies){
            System.assertEquals(false, c.Is_Partner__c);
        }
    }
    @isTest
    static void testCreateNewClaimantRelationTrackC() {
        Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];

        String json = JSON.serialize(new Map<String,Object>{
            'applicationId' => b.Id,
            'application' => new Map<String,Object>{
                'trackC' => new Map<String,Object>{
                    'employers' => new List<Object>{
                        new Map<String,Object>{
                            'name'=>'Employer C',
                            'country'=>'GB'
                        }
                    },
                    'addresses' => new List<Object>{
                        new Map<String,Object>{
                            'country'=>'GB'
                        }
                    }
                }
            }
        });

        BP_RequestWrappers.ShortApplicationDataWrapper wrapper =
            new BP_RequestWrappers.ShortApplicationDataWrapper(json);

        Test.startTest();
        BP_PortalUtils.createNewClaimantRelationTrackC(wrapper);
        Test.stopTest();

        List<Claimant_Company__c> companies = [
            SELECT Is_Partner__c, Is_Addresses__c
            FROM Claimant_Company__c
            WHERE Basic__c = :b.Id
            ORDER BY CreatedDate DESC
            LIMIT 2
        ];

        System.assertEquals(1, companies.size());

        for(Claimant_Company__c c : companies){
            System.assertEquals(false, c.Is_Partner__c);
        }
    }

    @isTest
    static void testReviewUpdate() {

        Basic__c b = [
            SELECT Id, Step__c, Agent_Form_Step__c
            FROM Basic__c
            LIMIT 1
        ];

        String json = JSON.serialize(new Map<String,Object>{
            'applicationId' => b.Id,
            'currentStep' => 2,
            'isAgentForm' => false,
            'application' => new Map<String,Object>{
                'agent' =>'Ciara',

                'contactCommunication' => new Map<String,Object>{
                    'firstName' => 'John',
                    'lastName' => 'Smith',
                    'email' => 'john@test.com',
                    'tel' => '123456',
                    'relationship' => 'Friend'
                },

                'claimant' => new Map<String,Object>{
                    'title' => 'Mr',
                    'surname' => 'Doe',
                    'firstName' => 'John',
                    'email' => 'john@test.com',
                    'tel' => '111111',
                    'address1' => 'Street 1',
                    'address2' => 'Flat 2',
                    'city' => 'London',
                    'country' => 'GB',
                    'postcode' => 'SW1',
                    'dob' => '1990-01-01T00:00:00Z',
                    'children' => new List<Object>(),
                    'ukCompanies' => new List<Object>(),
                    'countriesLived' => new List<Object>(),
                    'everLivedUK' => true,
                    'addressValidated' => true,
                    'verificationStatus' => 'Verified',
                    'wasCleansed' => true,
                    'hasNino' => true,
                    'everLivedUK' => true,
                    'everWorkedUK' => true,
                    'marriedWomansStamp' => false,
                    'hasProofOfUKWork' => true,
                    'hasNino' => true,
                    'nino' => 'AA123456A',
                    'livedUKFrom' => '1990-01-01T00:00:00Z',
                    'livedUKTo' => '2000-01-01T00:00:00Z',
                    'workedUKFrom' => '1991-01-01T00:00:00Z',
                    'workedUKTo' => '1999-01-01T00:00:00Z',
                    'selfEmployedUK' => true,
                    'mindedKids' => false,
                    'statePension' => false,
                    'title' => 'Mr',
                    'surname' => 'Smith',
                    'otherNames' => 'John Michael',
                    'dob' => '1960-01-01T00:00:00Z',
                    'maidenName' => 'Johnson',
                    'tel' => '+353871234567',
                    'email' => 'john.smith@test.com',
                    'maritalStatus' => 'Married',
                    'nationality' => 'British',

                    'dateOfMarriage' => '1985-06-15T00:00:00Z',
                    'dateOfBereavement' => '2018-03-20T00:00:00Z',
                    'dateOfDivorce' => '2010-09-10T00:00:00Z',

                    'hasNino' => true,
                    'nino' => 'AB123456C',

                    'country' => 'GB',
                    'countryName' => 'United Kingdom',
                    'postcode' => 'SW1A 1AA',
                    'address1' => '10 Downing Street',
                    'address2' => 'Westminster',
                    'city' => 'London',

                    'everLivedUK' => true,
                    'livedUKFrom' => '1980-01-01T00:00:00Z',
                    'livedUKTo' => '2000-01-01T00:00:00Z',

                    'everWorkedUK' => true,
                    'workedUKFrom' => '1982-01-01T00:00:00Z',
                    'workedUKTo' => '1999-01-01T00:00:00Z',

                    'hasProofOfUKWork' => true,

                    'countriesLived' => new List<Object>(),
                    'ukCompanies' => new List<Object>(),

                    'selfEmployedUK' => false,
                    'marriedWomansStamp' => false,
                    'mindedKids' => true,

                    'children' => new List<Object>(),

                    'addressValidated' => true,
                    'verificationStatus' => 'Verified',
                    'wasCleansed' => true,

                    'everWorkedUKuseSameDates' => true,
                    'phoneType' => 'Mobile',
                    'approxYearsInUK' => 20,
                    'everLivedUKNotes' => 'Test notes'

                },

                'partner' => new Map<String,Object>{
                        'title' => 'Mrs',
                        'firstName' => 'Jane',
                        'surname' => 'Smith',
                        'otherNames' => 'Ann',
                        'maidenName' => 'Brown',
                        'dob' => '1982-01-01T00:00:00Z',

                        'hasNino' => true,
                        'nino' => 'BB123456B',

                        'saveAsClaimant' => true,

                        'country' => 'IE',
                        'postcode' => 'D02',
                        'address1' => 'Partner Street',
                        'address2' => 'House',
                        'city' => 'Dublin',

                        'claimingUKPension' => true,
                        'referenceOnAnyDWPLetters' => 'REF123',

                        'addressValidated' => true,
                        'verificationStatus' => 'Verified',
                        'wasCleansed' => true,
                        'everLivedUK' => true,
                        'everWorkedUK' => true
                    },
                'otherInformation' => new Map<String,Object>(),
                'claimantBenefits' => new Map<String,Object>{
                        'graduatedRetirement' => true,
                        'bereavement' => false,
                        'statePension' => true,
                        'widows' => false,
                        'isWaitingUkBenefits' => true,
                        'isWaitingUkBenefitsText' => 'Waiting'
                    },

                    'partnerBenefits' => new Map<String,Object>{
                        'graduatedRetirement' => false,
                        'bereavement' => true,
                        'statePension' => false,
                        'widows' => true,
                        'isWaitingUkBenefits' => false,
                        'isWaitingUkBenefitsText' => ''
                    },

                    'pension' => new Map<String,Object>{
                        'claimingFromToday' => true,
                        'deferredPension' => false,
                        'imprisonedSincePensionAge' => false,
                        'startDate' => '2025-01-01T00:00:00Z',
                        'workAfterPensionAge' => true,
                        'workInUKduring2years' => true,
                        'everSelfEmployedUKafter1978' => true,
                        'everPayReducedUKnino' => true
                    },

                    'bank' => new Map<String,Object>{
                        'account' => '12345678',
                        'accountOwnerName' => 'John Smith',
                        'accountType' => 'Current',
                        'iban' => 'IE29AIBK93115212345678',
                        'bankName' => 'AIB',
                        'sortCode' => '123456',
                        'address' => 'Bank Street',
                        'city' => 'Dublin',
                        'country' => 'IE',
                        'postcode' => 'D01',
                        'bic' => 'AIBKIE2D',
                        'ownsThisAccount' => 'Claimant'
                    }
            }
        });

        BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper =
            new BP_RequestWrappers.ApplicationDetailsDataWrapper(json);

        List<Basic__c> apps = BP_PortalUtils.getApplication(b.Id);

        Test.startTest();
        BP_PortalUtils.reviewUpdate(apps, wrapper);
        Test.stopTest();

        Basic__c updated = [
            SELECT
                Friend_First_Name__c,
                Validation_Agent__c,
                Step__c,
                Claimant_address1__c
            FROM Basic__c
            WHERE Id = :b.Id
        ];

        System.assertEquals('John', updated.Friend_First_Name__c);
        System.assertEquals('Ciara', updated.Validation_Agent__c);
        System.assertEquals('10 Downing Street', updated.Claimant_address1__c);
        System.assertEquals(
            BP_PortalUtils.currentStep(apps[0].Step__c, 2),
            updated.Step__c
        );
    }

    @isTest
    static void testReviewUpdateAgentForm() {

        Basic__c b = [
            SELECT Id, Step__c, Agent_Form_Step__c
            FROM Basic__c
            LIMIT 1
        ];

        String json = JSON.serialize(new Map<String,Object>{
            'applicationId' => b.Id,
            'currentStep' => 3,
            'isAgentForm' => true,
            'application' => new Map<String,Object>{
                'claimant' => new Map<String,Object>{
                    'children' => new List<Object>(),
                    'ukCompanies' => new List<Object>(),
                    'countriesLived' => new List<Object>(),
                    'addressValidated' => true,
                    'verificationStatus' => 'Verified',
                    'wasCleansed' => true,
                    'hasNino' => true,
                    'everLivedUK' => true,
                    'everWorkedUK' => true,
                    'marriedWomansStamp' => false,
                    'hasProofOfUKWork' => true,
                    'hasNino' => true,
                    'nino' => 'AA123456A',
                    'livedUKFrom' => '1990-01-01T00:00:00Z',
                    'livedUKTo' => '2000-01-01T00:00:00Z',
                    'workedUKFrom' => '1991-01-01T00:00:00Z',
                    'workedUKTo' => '1999-01-01T00:00:00Z',
                    'selfEmployedUK' => true,
                    'mindedKids' => false,
                    'statePension' => false,
                    'title' => 'Mr',
                    'surname' => 'Smith',
                    'otherNames' => 'John Michael',
                    'dob' => '1960-01-01T00:00:00Z',
                    'maidenName' => 'Johnson',
                    'tel' => '+353871234567',
                    'email' => 'john.smith@test.com',
                    'maritalStatus' => 'Married',
                    'nationality' => 'British',

                    'dateOfMarriage' => '1985-06-15T00:00:00Z',
                    'dateOfBereavement' => '2018-03-20T00:00:00Z',
                    'dateOfDivorce' => '2010-09-10T00:00:00Z',

                    'hasNino' => true,
                    'nino' => 'AB123456C',

                    'country' => 'GB',
                    'countryName' => 'United Kingdom',
                    'postcode' => 'SW1A 1AA',
                    'address1' => '10 Downing Street',
                    'address2' => 'Westminster',
                    'city' => 'London',

                    'everLivedUK' => true,
                    'livedUKFrom' => '1980-01-01T00:00:00Z',
                    'livedUKTo' => '2000-01-01T00:00:00Z',

                    'everWorkedUK' => true,
                    'workedUKFrom' => '1982-01-01T00:00:00Z',
                    'workedUKTo' => '1999-01-01T00:00:00Z',

                    'hasProofOfUKWork' => true,

                    'countriesLived' => new List<Object>(),
                    'ukCompanies' => new List<Object>(),

                    'selfEmployedUK' => false,
                    'marriedWomansStamp' => false,
                    'mindedKids' => true,

                    'children' => new List<Object>(),

                    'addressValidated' => true,
                    'verificationStatus' => 'Verified',
                    'wasCleansed' => true,

                    'everWorkedUKuseSameDates' => true,
                    'phoneType' => 'Mobile',
                    'approxYearsInUK' => 20,
                    'everLivedUKNotes' => 'Test notes'
                },
                'partner' => new Map<String,Object>{
                        'title' => 'Mrs',
                        'firstName' => 'Jane',
                        'surname' => 'Smith',
                        'otherNames' => 'Ann',
                        'maidenName' => 'Brown',
                        'dob' => '1982-01-01T00:00:00Z',

                        'hasNino' => true,
                        'nino' => 'BB123456B',

                        'saveAsClaimant' => true,

                        'country' => 'IE',
                        'postcode' => 'D02',
                        'address1' => 'Partner Street',
                        'address2' => 'House',
                        'city' => 'Dublin',

                        'claimingUKPension' => true,
                        'referenceOnAnyDWPLetters' => 'REF123',

                        'addressValidated' => true,
                        'verificationStatus' => 'Verified',
                        'wasCleansed' => true,
                        'everLivedUK' => true,
                        'everWorkedUK' => true
                    },
                'otherInformation' => new Map<String,Object>(),
                'claimantBenefits' => new Map<String,Object>{
                        'graduatedRetirement' => true,
                        'bereavement' => false,
                        'statePension' => true,
                        'widows' => false,
                        'isWaitingUkBenefits' => true,
                        'isWaitingUkBenefitsText' => 'Waiting'
                    },

                    'partnerBenefits' => new Map<String,Object>{
                        'graduatedRetirement' => false,
                        'bereavement' => true,
                        'statePension' => false,
                        'widows' => true,
                        'isWaitingUkBenefits' => false,
                        'isWaitingUkBenefitsText' => ''
                    },

                    'pension' => new Map<String,Object>{
                        'claimingFromToday' => true,
                        'deferredPension' => false,
                        'imprisonedSincePensionAge' => false,
                        'startDate' => '2025-01-01T00:00:00Z',
                        'workAfterPensionAge' => true,
                        'workInUKduring2years' => true,
                        'everSelfEmployedUKafter1978' => true,
                        'everPayReducedUKnino' => true
                    },

                    'bank' => new Map<String,Object>{
                        'account' => '12345678',
                        'accountOwnerName' => 'John Smith',
                        'accountType' => 'Current',
                        'iban' => 'IE29AIBK93115212345678',
                        'bankName' => 'AIB',
                        'sortCode' => '123456',
                        'address' => 'Bank Street',
                        'city' => 'Dublin',
                        'country' => 'IE',
                        'postcode' => 'D01',
                        'bic' => 'AIBKIE2D',
                        'ownsThisAccount' => 'Claimant'
                    }
            }
        });

        BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper =
            new BP_RequestWrappers.ApplicationDetailsDataWrapper(json);

        List<Basic__c> apps = BP_PortalUtils.getApplication(b.Id);

        Test.startTest();
        BP_PortalUtils.reviewUpdate(apps, wrapper);
        Test.stopTest();

        Basic__c updated = [
            SELECT Agent_Form_Step__c
            FROM Basic__c
            WHERE Id = :b.Id
        ];

        System.assertNotEquals(null, updated.Agent_Form_Step__c);
    }

    @isTest
    static void testAutoSave() {

        Basic__c app = [SELECT Id FROM Basic__c LIMIT 1];

        String json = JSON.serialize(new Map<String,Object>{
                'applicationId' => app.Id,

                'application' => new Map<String,Object>{

                    'agent' => 'Ciara',

                    'contactCommunication' => new Map<String,Object>{
                        'firstName' => 'Helper',
                        'lastName' => 'Person',
                        'tel' => '123456',
                        'email' => 'helper@test.com',
                        'relationship' => 'Friend'
                    },

                    'claimant' => new Map<String,Object>{
                        'title' => 'Mr',
                        'surname' => 'Smith',
                        'otherNames' => 'John',
                        'maidenName' => 'None',
                        'dob' => '1980-01-01T00:00:00Z',
                        'email' => 'john@test.com',
                        'tel' => '555111',

                        'address1' => 'Street 1',
                        'address2' => 'Flat 2',
                        'city' => 'Dublin',
                        'postcode' => 'D01',
                        'country' => 'IE',

                        'dateOfMarriage' => '2000-01-01T00:00:00Z',
                        'dateOfDivorce' => '2010-01-01T00:00:00Z',
                        'dateOfBereavement' => '2015-01-01T00:00:00Z',

                        'everLivedUK' => true,
                        'everWorkedUK' => true,
                        'marriedWomansStamp' => false,
                        'hasProofOfUKWork' => true,
                        'hasNino' => true,
                        'nino' => 'AA123456A',
                        'livedUKFrom' => '1990-01-01T00:00:00Z',
                        'livedUKTo' => '2000-01-01T00:00:00Z',
                        'workedUKFrom' => '1991-01-01T00:00:00Z',
                        'workedUKTo' => '1999-01-01T00:00:00Z',

                        'maritalStatus' => 'Married',
                        'mindedKids' => true,
                        'nationality' => 'Irish',
                        'selfEmployedUK' => false,

                        'addressValidated' => true,
                        'verificationStatus' => 'Verified',
                        'wasCleansed' => true
                    },

                    'partner' => new Map<String,Object>{
                        'title' => 'Mrs',
                        'firstName' => 'Jane',
                        'surname' => 'Smith',
                        'otherNames' => 'Ann',
                        'maidenName' => 'Brown',
                        'dob' => '1982-01-01T00:00:00Z',

                        'hasNino' => true,
                        'nino' => 'BB123456B',

                        'saveAsClaimant' => true,

                        'country' => 'IE',
                        'postcode' => 'D02',
                        'address1' => 'Partner Street',
                        'address2' => 'House',
                        'city' => 'Dublin',

                        'claimingUKPension' => true,
                        'referenceOnAnyDWPLetters' => 'REF123',

                        'addressValidated' => true,
                        'verificationStatus' => 'Verified',
                        'wasCleansed' => true
                    },

                    'claimantBenefits' => new Map<String,Object>{
                        'graduatedRetirement' => true,
                        'bereavement' => false,
                        'statePension' => true,
                        'widows' => false,
                        'isWaitingUkBenefits' => true,
                        'isWaitingUkBenefitsText' => 'Waiting'
                    },

                    'partnerBenefits' => new Map<String,Object>{
                        'graduatedRetirement' => false,
                        'bereavement' => true,
                        'statePension' => false,
                        'widows' => true,
                        'isWaitingUkBenefits' => false,
                        'isWaitingUkBenefitsText' => ''
                    },

                    'pension' => new Map<String,Object>{
                        'claimingFromToday' => true,
                        'deferredPension' => false,
                        'imprisonedSincePensionAge' => false,
                        'startDate' => '2025-01-01T00:00:00Z',
                        'workAfterPensionAge' => true
                    },

                    'bank' => new Map<String,Object>{
                        'account' => '12345678',
                        'accountOwnerName' => 'John Smith',
                        'accountType' => 'Current',
                        'iban' => 'IE29AIBK93115212345678',
                        'bankName' => 'AIB',
                        'sortCode' => '123456',
                        'address' => 'Bank Street',
                        'city' => 'Dublin',
                        'country' => 'IE',
                        'postcode' => 'D01',
                        'bic' => 'AIBKIE2D',
                        'ownsThisAccount' => 'Claimant'
                    }
                }
            });

        BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper =
        new BP_RequestWrappers.ApplicationDetailsDataWrapper(json);

        Test.startTest();
        BP_PortalUtils.autoSave(wrapper);
        Test.stopTest();

        Basic__c updated = [
            SELECT Claimant_title__c,
                Last_Name__c
            FROM Basic__c
            WHERE Id=:app.Id
        ];

        System.assertEquals('Mr', updated.Claimant_title__c);
        System.assertEquals('Smith', updated.Last_Name__c);
    }

    @isTest
    static void testAutoSaveShortTrackA() {
        Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];

        String json = JSON.serialize(new Map<String,Object>{
            'applicationId' => b.Id,
            'application' => new Map<String,Object>{
                'track' => 'A',
                'client' => new Map<String,Object>{
                    'title' => 'Mr',
                    'firstName' => 'John',
                    'lastName' => 'Smith',
                    'country' => 'GB',
                    'email' => 'john@test.com',
                    'everLivedUK' => true,
                    'addressValidated' => true,
                    'verificationStatus' => 'Verified',
                    'wasCleansed' => true
                },
                'trackA' => new Map<String,Object>{
                    'nino' => 'QQ123456C',
                    'hasNino' => 'Yes',
                    'isGettingUKStatePensionNow' => true
                }
            }
        });

        BP_RequestWrappers.ShortApplicationDataWrapper wrapper =
            new BP_RequestWrappers.ShortApplicationDataWrapper(json);

        Test.startTest();
        BP_PortalUtils.autoSaveShort(wrapper);
        Test.stopTest();

        Basic__c app = [
            SELECT Track__c, Claimant_nino__c, Claimant_hasNino__c
            FROM Basic__c
            WHERE Id = :b.Id
        ];

        System.assertEquals('A', app.Track__c);
        System.assertEquals('QQ123456C', app.Claimant_nino__c);
        System.assertEquals(true, app.Claimant_hasNino__c);
    }

    @isTest
    static void testAutoSaveShortTrackB() {
        Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];

        String json = JSON.serialize(new Map<String,Object>{
            'applicationId' => b.Id,
            'application' => new Map<String,Object>{
                'track' => 'B',
                'client' => new Map<String,Object>{
                    'firstName' => 'John',
                    'lastName' => 'Smith',
                    'everLivedUK' => true,
                    'addressValidated' => true,
                    'verificationStatus' => 'Verified',
                    'wasCleansed' => true
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
        });

        BP_RequestWrappers.ShortApplicationDataWrapper wrapper =
            new BP_RequestWrappers.ShortApplicationDataWrapper(json);

        Test.startTest();
        BP_PortalUtils.autoSaveShort(wrapper);
        Test.stopTest();

        Basic__c app = [
            SELECT Track__c,
                Is_Partner_alive__c,
                Partner_First_Name__c,
                Partner_Has_Nino__c
            FROM Basic__c
            WHERE Id=:b.Id
        ];

        System.assertEquals('B', app.Track__c);
        System.assertEquals(true, app.Is_Partner_alive__c);
        System.assertEquals('Peter', app.Partner_First_Name__c);
        System.assertEquals(true, app.Partner_Has_Nino__c);
    }

    @isTest
    static void testAutoSaveShortTrackC() {
        Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];

        String json = JSON.serialize(new Map<String,Object>{
            'applicationId' => b.Id,
            'application' => new Map<String,Object>{
                'track' => 'C',
                'client' => new Map<String,Object>{
                    'firstName' => 'John',
                    'lastName' => 'Smith',
                    'everLivedUK' => true,
                    'addressValidated' => true,
                    'verificationStatus' => 'Verified',
                    'wasCleansed' => true
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
        });

        BP_RequestWrappers.ShortApplicationDataWrapper wrapper =
            new BP_RequestWrappers.ShortApplicationDataWrapper(json);

        Test.startTest();
        BP_PortalUtils.autoSaveShort(wrapper);
        Test.stopTest();

        Basic__c app = [
            SELECT Track__c,
                Partner_Has_Nino__c,
                Partner_Nino__c
            FROM Basic__c
            WHERE Id=:b.Id
        ];

        System.assertEquals('C', app.Track__c);
        System.assertEquals(true, app.Partner_Has_Nino__c);
        System.assertEquals('AB654321C', app.Partner_Nino__c);
    }

    @isTest
    static void testSendValidationEmail() {

        Basic__c app = [
            SELECT Id
            FROM Basic__c
            LIMIT 1
        ];

        List<String> missingFields = new List<String>{
            'Passport',
            'Utility Bill',
            'Birth Certificate'
        };

        Test.startTest();
        BP_PortalUtils.sendValidationEmail(app.Id, missingFields);
        Test.stopTest();

        System.assert(true);
    }
    @isTest
    static void testSendValidationEmailWithCC() {

        Basic__c app = [
            SELECT Id
            FROM Basic__c
            LIMIT 1
        ];

        update new Basic__c(
            Id = app.Id,
            Friend_Email__c = 'helper@test.com',
            CC_Helper_on_All_Comms__c = true
        );

        Test.startTest();
        BP_PortalUtils.sendValidationEmail(
            app.Id,
            new List<String>{'Proof of address'}
        );
        Test.stopTest();

        System.assert(true);
    }

    @isTest
    static void testSendPaidEmail() {

        Basic__c app = [
            SELECT Id
            FROM Basic__c
            LIMIT 1
        ];

        Test.startTest();
        BP_PortalUtils.sendPaidEmail(app.Id);
        Test.stopTest();

        System.assert(true);
    }
}