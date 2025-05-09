@isTest
public class HMRC_SMS_ScheduleDateTriggerTest {
    @TestSetup
    static void makeData(){
        TestDataFactory.createProductsWithPrices();
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, false);
        testApplication.Status__c = 'Posted';
        insert testApplication;
        TestDataFactory.createHMRCSMSScheduleDate(true);
    }

    @IsTest
    static void updateScheduleDateCheckboxTest(){
        List<HMRC_SMS_Schedule_Date__c> scheduleDates = [
            SELECT Is_Send_Messages__c
            FROM HMRC_SMS_Schedule_Date__c
        ];
        scheduleDates[0].Is_Send_Messages__c = true;
        Test.startTest();
        update scheduleDates;
        Test.stopTest();
    }
}