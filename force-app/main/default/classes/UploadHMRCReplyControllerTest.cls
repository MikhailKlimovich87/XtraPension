@isTest
public class UploadHMRCReplyControllerTest {
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
    }

    @IsTest
    static void uploadFileTest() {
        List<Application__c> testApps = [
            SELECT
                Id,
                Years_Of_Work_In_The_UK__c,
                HMRC_Ref__c,
                HMRC_Reply_Status__c
            FROM Application__c
            LIMIT 1
        ];
        if (testApps.isEmpty()) {
            return;
        }
        Application__c currApp = testApps[0];
        UploadHMRCReplyController.RequestData data = new UploadHMRCReplyController.RequestData();
        data.recordId = currApp.Id;
        data.years = '5.2';
        data.typeOfReply = 'DWP';
        data.fileName = 'Test.pdf';
        data.fileData = 'Unit Test Attachment Body';
        data.ref = 'ICW/Test';

        String testCDL = UploadHMRCReplyController.uploadFile(data);
        Assert.isNotNull(testCDL);
        List<Application__c> testAppsAfterUpdate = [
            SELECT
                Id,
                Years_Of_Work_In_The_UK__c,
                HMRC_Ref__c,
                HMRC_Reply_Status__c
            FROM Application__c
            WHERE Id = :currApp.Id
            LIMIT 1
        ];
        Application__c currAppAfterUpdate = testAppsAfterUpdate[0];
        Assert.areNotEqual(currApp.Years_Of_Work_In_The_UK__c, currAppAfterUpdate.Years_Of_Work_In_The_UK__c);
        Assert.areNotEqual(currApp.HMRC_Ref__c, currAppAfterUpdate.HMRC_Ref__c);
        Assert.areNotEqual(currApp.HMRC_Reply_Status__c, currAppAfterUpdate.HMRC_Reply_Status__c);
        Assert.areEqual('DWP', currAppAfterUpdate.HMRC_Reply_Status__c);
        Assert.areEqual('ICW/Test', currAppAfterUpdate.HMRC_Ref__c);
        Assert.areEqual(5.2, currAppAfterUpdate.Years_Of_Work_In_The_UK__c);
    }
}