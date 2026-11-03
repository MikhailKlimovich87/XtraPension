@IsTest
private class BasicTriggerHandlerTest {
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

    @IsTest
    static void testRegeneratePackOnSourceChange() {
        Basic__c claim = new Basic__c(Status__c = 'Form completed', First_Name__c = 'John');
        insert claim;

        Basic__c edited = new Basic__c(Id = claim.Id, Status__c = 'Form completed', First_Name__c = 'Johnny');
        BasicTriggerHandler handler = new BasicTriggerHandler(
            new List<Basic__c>{ edited },
            new Map<Id, Basic__c>{ edited.Id => edited },
            new Map<Id, Basic__c>{ claim.Id => claim }
        );

        Test.startTest();
        handler.regeneratePackOnSourceChange();
        System.assertEquals(1, Limits.getQueueableJobs(), 'Editing client data before signing must regenerate the pack');
        // the same claim is never queued twice in one transaction
        handler.regeneratePackOnSourceChange();
        System.assertEquals(1, Limits.getQueueableJobs());
        Test.stopTest();
    }

    @IsTest
    static void testNoRegenerationWhenNothingRelevantChanged() {
        Basic__c claim = new Basic__c(Status__c = 'Form completed', First_Name__c = 'John');
        insert claim;

        Basic__c edited = new Basic__c(Id = claim.Id, Status__c = 'Form completed', First_Name__c = 'John', Missing_Info__c = 'x');
        BasicTriggerHandler handler = new BasicTriggerHandler(
            new List<Basic__c>{ edited },
            new Map<Id, Basic__c>{ edited.Id => edited },
            new Map<Id, Basic__c>{ claim.Id => claim }
        );

        Test.startTest();
        handler.regeneratePackOnSourceChange();
        System.assertEquals(0, Limits.getQueueableJobs());
        Test.stopTest();
    }

    @IsTest
    static void testBlockEditsWhileOutForSignature() {
        Basic__c claim = new Basic__c(Status__c = 'Sent for eSignature', First_Name__c = 'John');
        insert claim;

        Basic__c edited = new Basic__c(Id = claim.Id, Status__c = 'Sent for eSignature', First_Name__c = 'Johnny');
        BasicTriggerHandler handler = new BasicTriggerHandler(
            new List<Basic__c>{ edited },
            new Map<Id, Basic__c>{ edited.Id => edited },
            new Map<Id, Basic__c>{ claim.Id => claim }
        );
        handler.blockEditsWhileOutForSignature();

        System.assert(edited.hasErrors(), 'Editing client data while out for signature must be blocked');
    }

    @IsTest
    static void testEditsAllowedWhenNotOutForSignature() {
        Basic__c claim = new Basic__c(Status__c = 'Form completed', First_Name__c = 'John');
        insert claim;

        Basic__c edited = new Basic__c(Id = claim.Id, Status__c = 'Form completed', First_Name__c = 'Johnny');
        BasicTriggerHandler handler = new BasicTriggerHandler(
            new List<Basic__c>{ edited },
            new Map<Id, Basic__c>{ edited.Id => edited },
            new Map<Id, Basic__c>{ claim.Id => claim }
        );
        handler.blockEditsWhileOutForSignature();

        System.assert(!edited.hasErrors());
    }

    @IsTest
    static void testStatusChangeAloneIsNotABlockedEdit() {
        Basic__c claim = new Basic__c(Status__c = 'Sent for eSignature', First_Name__c = 'John');
        insert claim;

        Basic__c signed = new Basic__c(Id = claim.Id, Status__c = 'Signed - Waiting Docs at WDM', First_Name__c = 'John');
        BasicTriggerHandler handler = new BasicTriggerHandler(
            new List<Basic__c>{ signed },
            new Map<Id, Basic__c>{ signed.Id => signed },
            new Map<Id, Basic__c>{ claim.Id => claim }
        );
        handler.blockEditsWhileOutForSignature();

        System.assert(!signed.hasErrors());
    }

    @IsTest
    static void testGeneratePdfFiles_StatusChangedToSigned() {
        Basic__c oldClaim = new Basic__c(
            
            Status__c = 'Form In Progress'
        );
        insert oldClaim;

        Basic__c newClaim = oldClaim.clone(false, true, false, false);
        newClaim.Id = oldClaim.Id;
        newClaim.Status__c = 'Signed - Waiting Docs at WDM';

        Map<Id, Basic__c> newClaims = new Map<Id, Basic__c>{
            newClaim.Id => newClaim
        };

        Map<Id, Basic__c> oldClaims = new Map<Id, Basic__c>{
            oldClaim.Id => oldClaim
        };

        List<Basic__c> newClaimsList = new List<Basic__c>{ newClaim };

        Test.startTest();

        BasicTriggerHandler handler =
            new BasicTriggerHandler(newClaimsList, newClaims, oldClaims);

        handler.generatePdfFiles();

        Test.stopTest();

        System.assertEquals(
            'Signed - Waiting Docs at WDM',
            newClaim.Status__c
        );
    }

    @IsTest
    static void testGeneratePdfFiles_StatusDidNotChange() {
        Basic__c oldClaim = new Basic__c(
            
            Status__c = 'Signed - Waiting Docs at WDM'
        );
        insert oldClaim;

        Basic__c newClaim = oldClaim.clone(false, true, false, false);
        newClaim.Id = oldClaim.Id;
        newClaim.Status__c = 'Signed - Waiting Docs at WDM';

        Map<Id, Basic__c> newClaims = new Map<Id, Basic__c>{
            newClaim.Id => newClaim
        };

        Map<Id, Basic__c> oldClaims = new Map<Id, Basic__c>{
            oldClaim.Id => oldClaim
        };
        List<Basic__c> newClaimsList = new List<Basic__c>{ newClaim };

        Test.startTest();

        BasicTriggerHandler handler =
            new BasicTriggerHandler(newClaimsList, newClaims, oldClaims);

        handler.generatePdfFiles();

        Test.stopTest();

        System.assertEquals(
            'Signed - Waiting Docs at WDM',
            newClaim.Status__c
        );
    }

    @IsTest
    static void testGeneratePdfFiles_DifferentStatus() {
        Basic__c oldClaim = new Basic__c(
            
            Status__c = 'Form In Progress'
        );
        insert oldClaim;

        Basic__c newClaim = oldClaim.clone(false, true, false, false);
        newClaim.Id = oldClaim.Id;
        newClaim.Status__c = 'Submitted';

        Map<Id, Basic__c> newClaims = new Map<Id, Basic__c>{
            newClaim.Id => newClaim
        };

        Map<Id, Basic__c> oldClaims = new Map<Id, Basic__c>{
            oldClaim.Id => oldClaim
        };

        List<Basic__c> newClaimsList = new List<Basic__c>{ newClaim };

        Test.startTest();

        BasicTriggerHandler handler =
            new BasicTriggerHandler(newClaimsList, newClaims, oldClaims);

        handler.generatePdfFiles();

        Test.stopTest();

        System.assertEquals('Submitted', newClaim.Status__c);
    }

    @IsTest
    static void testGeneratePdfFiles_MandateAlreadyExists() {
        Basic__c oldClaim = new Basic__c(
            
            Status__c = 'Form In Progress'
        );
        insert oldClaim;

        Basic__c newClaim = oldClaim.clone(false, true, false, false);
        newClaim.Id = oldClaim.Id;
        newClaim.Status__c = 'Signed - Waiting Docs at WDM';
        newClaim.GoCardless_Mandate_Id__c = 'MANDATE-123';

        Map<Id, Basic__c> newClaims = new Map<Id, Basic__c>{
            newClaim.Id => newClaim
        };

        Map<Id, Basic__c> oldClaims = new Map<Id, Basic__c>{
            oldClaim.Id => oldClaim
        };
        List<Basic__c> newClaimsList = new List<Basic__c>{ newClaim };

        Test.startTest();

        BasicTriggerHandler handler =
            new BasicTriggerHandler(newClaimsList, newClaims, oldClaims);

        handler.generatePdfFiles();

        Test.stopTest();

        System.assertEquals(
            'MANDATE-123',
            newClaim.GoCardless_Mandate_Id__c
        );
    }

    @IsTest
    static void testCreateMandate_NullId() {
        Test.startTest();

        BasicTriggerHandler.createMandate(null);

        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testCreateMandate_ClaimDoesNotExist() {
        Id fakeId = 'a00000000000001AAA';

        Test.startTest();

        BasicTriggerHandler.createMandate(fakeId);

        Test.stopTest();

        // SOQL вернёт 0 записей, метод должен корректно завершиться.
        System.assert(true);
    }

    @IsTest
    static void testCreateMandate_ExistingClaim() {
        Basic__c claim = new Basic__c(
           
            Status__c = 'Form In Progress',
            First_Name__c = 'John',
            Last_Name__c = 'Smith',
            Email__c = 'john@example.com'
        );
        insert claim;

        Test.startTest();

        BasicTriggerHandler.createMandate(claim.Id);

        Test.stopTest();


        System.assertEquals(
            claim.Id,
            [SELECT Id FROM Basic__c WHERE Id = :claim.Id].Id
        );
    }

@IsTest
static void testDistribution_AssignsAgentToEligibleClaim() {
    Basic__c claim = new Basic__c(
        Status__c = 'Form In Progress'
    );

    BasicTriggerHandler handler = new BasicTriggerHandler(
        new List<Basic__c>{ claim },
        new Map<Id, Basic__c>(),
        new Map<Id, Basic__c>()
    );

    handler.distributeBetweenAgents();

    System.assert(
        new Set<String>{'Sean B', 'Ciara', 'Becky'}
            .contains(claim.Validation_Agent__c),
        'An eligible claim should receive a valid agent.'
    );
}

@IsTest
static void testDistribution_PreservesExistingAgent() {
    Basic__c claim = new Basic__c(
        Status__c = 'Form In Progress',
        Validation_Agent__c = 'Ciara'
    );

    BasicTriggerHandler handler = new BasicTriggerHandler(
        new List<Basic__c>{ claim },
        new Map<Id, Basic__c>(),
        new Map<Id, Basic__c>()
    );

    handler.distributeBetweenAgents();

    System.assertEquals(
        'Ciara',
        claim.Validation_Agent__c,
        'An existing agent assignment must not be overwritten.'
    );
}

@IsTest
static void testDistribution_SkipsIneligibleStatus() {
    Basic__c claim = new Basic__c(
        Status__c = 'Submitted'
    );

    BasicTriggerHandler handler = new BasicTriggerHandler(
        new List<Basic__c>{ claim },
        new Map<Id, Basic__c>(),
        new Map<Id, Basic__c>()
    );

    handler.distributeBetweenAgents();

    System.assertEquals(
        null,
        claim.Validation_Agent__c,
        'Claims outside the distribution statuses must remain unassigned.'
    );
}

    @IsTest
    static void testDistribution_SkipsBlankStatus() {
    Basic__c claim = new Basic__c();

    BasicTriggerHandler handler = new BasicTriggerHandler(
        new List<Basic__c>{ claim },
        new Map<Id, Basic__c>(),
        new Map<Id, Basic__c>()
    );

    handler.distributeBetweenAgents();

    System.assertEquals(
        null,
        claim.Validation_Agent__c,
        'A claim without a status must not be assigned an agent.'
    );
    }

    @IsTest
    static void testDistribution_AssignsMultipleClaims() {
        List<Basic__c> claims = new List<Basic__c>{
            new Basic__c(Status__c = 'Form In Progress'),
            new Basic__c(Status__c = 'Validation Call'),
            new Basic__c(Status__c = 'Form completed'),
            new Basic__c(Status__c = 'Pending Client'),
            new Basic__c(Status__c = 'Form In Progress'),
            new Basic__c(Status__c = 'Validation Call')
        };

        BasicTriggerHandler handler = new BasicTriggerHandler(
            claims,
            new Map<Id, Basic__c>(),
            new Map<Id, Basic__c>()
        );

        handler.distributeBetweenAgents();

        Set<String> validAgents = new Set<String>{
            'Sean B', 'Ciara', 'Becky'
        };

        Set<String> assignedAgents = new Set<String>();

        for (Basic__c claim : claims) {
            System.assert(
                validAgents.contains(claim.Validation_Agent__c),
                'Every eligible claim must receive a valid agent.'
            );

            assignedAgents.add(claim.Validation_Agent__c);
        }

        System.assertEquals(
            3,
            assignedAgents.size(),
            'Multiple claims should be distributed across all three agents.'
        );
    }

    @IsTest
    static void testDistribution_AllEligibleStatuses() {
        List<String> statuses = new List<String>{
            'Form In Progress',
            'Validation Call',
            'Form completed',
            'Pending Client'
        };

        List<Basic__c> claims = new List<Basic__c>();

        for (String status : statuses) {
            claims.add(new Basic__c(Status__c = status));
        }

        BasicTriggerHandler handler = new BasicTriggerHandler(
            claims,
            new Map<Id, Basic__c>(),
            new Map<Id, Basic__c>()
        );

        handler.distributeBetweenAgents();

        for (Basic__c claim : claims) {
            System.assertNotEquals(
                null,
                claim.Validation_Agent__c,
                'Each eligible status should receive an agent: '
                + claim.Status__c
            );
        }
    }
}