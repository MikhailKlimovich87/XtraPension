@isTest
public class AgentAuthLetterPdfHandlerTest {

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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
        TestDataFactory.createXtraPensionDataCustomSetting(true);
    }

    @IsTest
    static void generateAgentAuthLetterTest() {
        List<Application__c> testApps = [
            SELECT Id
            FROM Application__c
            LIMIT 1
        ];
        Application__c app = testApps[0];

		List<ContentDocumentLink> oldDocuments = [
            SELECT
                ContentDocument.Title,
                LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocument.Title LIKE '%AgentAuthLetter%' AND
                  LinkedEntityId = :app.Id
        ];
        Assert.areEqual(0, oldDocuments.size());
        Test.startTest();
        AgentAuthLetterPdfHandler.generateAgentAuthLetter(app.Id);
        Test.stopTest();
        List<ContentDocumentLink> newDocuments = [
            SELECT
                ContentDocument.Title,
                LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocument.Title LIKE '%AgentAuthLetter%' AND
                  LinkedEntityId = :app.Id
        ];
        Assert.areEqual(1, newDocuments.size());
    }

    @IsTest
    static void generateZipArchiveTest(){
        List<Application__c> testApps = [
            SELECT Id
            FROM Application__c
            LIMIT 1
        ];
        Application__c app = testApps[0];

        ContentVersion cv64_8 = new ContentVersion();
        cv64_8.Title = 'Test_64-8_ForSignature_completed';
        cv64_8.PathOnClient = 'Test_64-8_ForSignature_completed.pdf';
        cv64_8.VersionData = EncodingUtil.base64Decode(EncodingUtil.urlEncode('Unit Test ForSignature Body','UTF-8'));
        insert cv64_8;
        ContentDocumentLink cdl1 = new ContentDocumentLink(
            LinkedEntityId = app.Id,
            ContentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv64_8.Id].ContentDocumentId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert cdl1;

        ContentVersion cvAgentAuth = new ContentVersion();
        cvAgentAuth.Title = 'Test_AgentAuthLetter';
        cvAgentAuth.PathOnClient = 'Test_AgentAuthLetter.pdf';
        cvAgentAuth.VersionData = EncodingUtil.base64Decode(EncodingUtil.urlEncode('Unit Test ForSignature Body','UTF-8'));
        insert cvAgentAuth;
        ContentDocumentLink cdl2 = new ContentDocumentLink(
            LinkedEntityId = app.Id,
            ContentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cvAgentAuth.Id].ContentDocumentId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert cdl2;

		List<ContentDocumentLink> oldDocuments = [
            SELECT
                ContentDocument.Title,
                LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocument.Title LIKE '%_64-8_AgentAuth' AND
                  LinkedEntityId = :app.Id
        ];
        Assert.areEqual(0, oldDocuments.size());
        Test.startTest();
        AgentAuthLetterPdfHandler.generateZipArchive(app.Id);
        Test.stopTest();

		List<ContentDocumentLink> newDocuments = [
            SELECT
                ContentDocument.Title,
                LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocument.Title LIKE '%_64-8_AgentAuth' AND
                  LinkedEntityId = :app.Id
        ];
        Assert.areEqual(1, newDocuments.size());
    }

    @IsTest
    static void sendAgentAuthZipfileToFtp(){
        Test.setMock(HttpCalloutMock.class, new SFTPFileUploaderTest.SFTPFileUploaderHttpCalloutMock());
        List<Application__c> testAppsBeforeSendToFTP = [
            SELECT Id, X64_8_AgentLetter_FTP_Send_Date__c
            FROM Application__c
            LIMIT 1
        ];
        Application__c app = testAppsBeforeSendToFTP[0];

        ContentVersion cvAgentAuthZip = new ContentVersion();
        cvAgentAuthZip.Title = 'Test_64-8_AgentAuth';
        cvAgentAuthZip.PathOnClient = 'Test_64-8_AgentAuth.pdf';
        cvAgentAuthZip.VersionData = EncodingUtil.base64Decode(EncodingUtil.urlEncode('Unit Test ForSignature Body','UTF-8'));
        insert cvAgentAuthZip;
        ContentDocumentLink cdl1 = new ContentDocumentLink(
            LinkedEntityId = app.Id,
            ContentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cvAgentAuthZip.Id].ContentDocumentId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert cdl1;
        Assert.isNull(app.X64_8_AgentLetter_FTP_Send_Date__c);

        Test.startTest();
        AgentAuthLetterPdfHandler.sendAgentAuthZipfileToFtp(app.Id);
        Test.stopTest();
        List<Application__c> testAppsAfterSendToFTP = [
            SELECT Id, X64_8_AgentLetter_FTP_Send_Date__c
            FROM Application__c
            LIMIT 1
        ];
        Application__c currApp = testAppsAfterSendToFTP[0];
        Assert.isNotNull(currApp.X64_8_AgentLetter_FTP_Send_Date__c);
        Assert.areEqual(Date.today(), currApp.X64_8_AgentLetter_FTP_Send_Date__c);
    }
}