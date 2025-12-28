@isTest
public class CheckAgentDistributorScheduleHandlerTest {
    @TestSetup
    static void makeData(){
        List<Product2> products = TestDataFactory.createProductsWithPrices();
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
        List<Application__c> testApps = new List<Application__c>();
        Application__c testApplication1 = TestDataFactory.createApplication(personContactId, false);
        testApplication1.Check_Agent__c = 'Daniel';
        testApplication1.Status__c = 'Posted';
        testApps.add(testApplication1);
        Application__c testApplication2 = TestDataFactory.createApplication(personContactId, false);
        testApplication2.Check_Agent__c = 'Hannah';
        testApplication2.Status__c = 'Posted';
        testApps.add(testApplication2);
        Application__c testApplication3 = TestDataFactory.createApplication(personContactId, false);
        testApplication3.Check_Agent__c = 'Vince';
        testApplication3.Status__c = 'Posted';
        testApps.add(testApplication3);
        Application__c testApplication4 = TestDataFactory.createApplication(personContactId, false);
        testApplication4.Tracking_Number_Sent_Date__c = Date.today().addDays(-14);
        testApplication4.Status__c = 'Posted';
        testApps.add(testApplication4);
        Application__c testApplication5 = TestDataFactory.createApplication(personContactId, false);
        testApplication5.Check_Agent__c = 'Daniel';
        testApplication5.Status__c = 'Posted';
        testApps.add(testApplication5);
        insert testApps;
    }

    @IsTest
    static void methodName() {
        Date day2WeeksAgo = Date.today().addDays(-14);
        List<Application__c> appsBeforeExecuteTestMethod = [
            SELECT Check_Agent__c
            FROM Application__c
            WHERE Tracking_Number_Sent_Date__c = :day2WeeksAgo
        ];
        Assert.isNull(appsBeforeExecuteTestMethod[0].Check_Agent__c);
        Test.startTest();
        CheckAgentDistributorSchedulerHandler testHandler = new CheckAgentDistributorSchedulerHandler();
        testHandler.assignedCheckUser();
        Test.stopTest();
        List<Application__c> appsAfterExecuteTestMethod = [
            SELECT Check_Agent__c
            FROM Application__c
            WHERE Tracking_Number_Sent_Date__c = :day2WeeksAgo
        ];
        Assert.isNotNull(appsAfterExecuteTestMethod[0].Check_Agent__c);
        Map<String, Integer> testCheckAgentsByEmptyApps = new Map<String, Integer> {
            'Clydel' => 0,
            'Daniel' => 0,
            'Hannah' => 0,
            'Vince'  => 0
        };
        for(Application__c app : [
	        SELECT
    	        Name,
    	        Check_Agent__c,
                (SELECT Id FROM HMRC_Check_Requests__r)
            FROM Application__c
            WHERE (Status__c = 'Posted' OR
                   Status__c = '64-8 Bounce' OR
                   Status__c = 'HMRC Reply 1'  OR
                   Status__c = 'HMRC Reply 2'  OR
                   Status__c  = 'DWP Teleclaim' OR
                   Status__c = 'DWP 2 Emails Sent' OR
                   Status__c = 'XP Letter Sent') AND
                   Check_Agent__c != null
            ]) {
            if(app.HMRC_Check_Requests__r.size() == 0) {
    	        Integer countApps = testCheckAgentsByEmptyApps.get(app.Check_Agent__c);
    	        if (countApps == null ) testCheckAgentsByEmptyApps.put(app.Check_Agent__c, 1);
    	        else testCheckAgentsByEmptyApps.put(app.Check_Agent__c, ++countApps);
            }
        }
        Assert.areEqual(2, testCheckAgentsByEmptyApps.get('Daniel'));
        Assert.areEqual(1, testCheckAgentsByEmptyApps.get('Hannah'));
        Assert.areEqual(1, testCheckAgentsByEmptyApps.get('Clydel'));
        Assert.areEqual(1, testCheckAgentsByEmptyApps.get('Vince'));
    }
}