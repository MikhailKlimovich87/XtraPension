@IsTest
private class BP_RegeneratePackQueueableTest {

    @TestSetup
    static void setup() {
        TestDataFactory.createTestCountry(true);
        Account acc = TestDataFactory.createAccount(true);
        Contact con = [SELECT Id FROM Contact WHERE AccountId = :acc.Id LIMIT 1];
        Basic__c app = BP_TestDataFactory.createBasic(con.Id, true);
        BP_TestDataFactory.createChild(app.Id, true);
        BP_TestDataFactory.createCompany(app.Id, true);
        BP_TestDataFactory.createCountryLived(app.Id, true);
    }

    @IsTest
    static void stepsWithoutExistingDocumentsDoNothing() {
        Basic__c claim = [SELECT Id FROM Basic__c LIMIT 1];

        Test.startTest();
        new BP_RegeneratePackQueueable(claim.Id, 2).execute(null);
        new BP_RegeneratePackQueueable(claim.Id, 4).execute(null);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Application_Form_Error__c]);
    }

    @IsTest
    static void failedStepIsLoggedAndDoesNotThrow() {
        Basic__c claim = [SELECT Id FROM Basic__c LIMIT 1];

        Test.startTest();
        // No PDF service endpoint is configured in this org-less test, so the step fails
        new BP_RegeneratePackQueueable(claim.Id, 1).execute(null);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Application_Form_Error__c]);
    }

    @IsTest
    static void queueableIsEnqueuedForAClaim() {
        Basic__c claim = [SELECT Id FROM Basic__c LIMIT 1];

        Test.startTest();
        Id jobId = System.enqueueJob(new BP_RegeneratePackQueueable(claim.Id));
        Test.stopTest();

        System.assertNotEquals(null, jobId);
    }
}