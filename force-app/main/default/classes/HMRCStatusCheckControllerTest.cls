@isTest
public class HMRCStatusCheckControllerTest {
    @TestSetup
    static void makeData() {
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
        testApplication.Status__c = 'HMRC Reply 1';
        testApplication.Amount_PH_Responses__c = 2;
        testApplication.C3__c = true;
        testApplication.Work_Item__c = true;
        testApplication.DWP__c = true;
        testApplication.Sent_to__c = 'Agent';
        insert testApplication;
    }

    @IsTest
    static void getRepeatedAppsTest() {
        Test.startTest();
        HMRCStatusCheckController.GetDataWrapper testWrapper = HMRCStatusCheckController.getRepeatedApps();
        Test.stopTest();
        Assert.isNotNull(testWrapper);
        Assert.areEqual(1, testWrapper.repeatedApps.size());
    }

    @IsTest
    static void updateCurrentApplicationTestCase1() {
        List<Application__c> testAppsBeforeUpdate =[
            SELECT C2__c
            FROM Application__c
        ];
        Application__c appBeforeUpdate = testAppsBeforeUpdate[0];
        HMRCStatusCheckController.ChangeDataWrapper wrapper = new HMRCStatusCheckController.ChangeDataWrapper();
        wrapper.fieldName = 'C2__c';
        wrapper.newFieldValue = 'true';
        wrapper.appId = appBeforeUpdate.Id;
        Test.startTest();
        HMRCStatusCheckController.ResultUpdateWrapper result = HMRCStatusCheckController.updateCurrentApplication(wrapper);
        Test.stopTest();
        List<Application__c> testAppsAfterUpdate =[
            SELECT C2__c
            FROM Application__c
        ];
        Application__c appAfterUpdate = testAppsAfterUpdate[0];
        Assert.areNotEqual(appAfterUpdate.C2__c, appBeforeUpdate.C2__c);
        Assert.isNotNull(result);
        Assert.isTrue(result.isSuccess);
        Assert.isFalse(result.isError);
    }

    @IsTest
    static void updateCurrentApplicationTestCase2() {
        List<Application__c> testAppsBeforeUpdate =[
            SELECT Sent_Date__c
            FROM Application__c
        ];
        Application__c appBeforeUpdate = testAppsBeforeUpdate[0];
        HMRCStatusCheckController.ChangeDataWrapper wrapper = new HMRCStatusCheckController.ChangeDataWrapper();
        wrapper.fieldName = 'Sent_Date__c';
        wrapper.newFieldValue = String.valueOf(Date.newInstance(2016, 12, 9));
        wrapper.appId = appBeforeUpdate.Id;
        Test.startTest();
        HMRCStatusCheckController.ResultUpdateWrapper result = HMRCStatusCheckController.updateCurrentApplication(wrapper);
        Test.stopTest();
        List<Application__c> testAppsAfterUpdate =[
            SELECT Sent_Date__c
            FROM Application__c
        ];
        Application__c appAfterUpdate = testAppsAfterUpdate[0];
        Assert.areNotEqual(appAfterUpdate.Sent_Date__c, appBeforeUpdate.Sent_Date__c);
        Assert.isNotNull(result);
        Assert.isTrue(result.isSuccess);
        Assert.isFalse(result.isError);
    }

    @IsTest
    static void updateCurrentApplicationTestCase3() {
        HMRCStatusCheckController.ChangeDataWrapper wrapper;
        Test.startTest();
        HMRCStatusCheckController.ResultUpdateWrapper result = HMRCStatusCheckController.updateCurrentApplication(wrapper);
        Test.stopTest();
        Assert.isTrue(result.isError);
        Assert.isFalse(result.isSuccess);
        Assert.areEqual('Input data is empty', result.errorMessage);
    }
}