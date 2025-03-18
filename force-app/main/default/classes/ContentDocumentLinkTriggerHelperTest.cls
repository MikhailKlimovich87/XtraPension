@IsTest
private with sharing class ContentDocumentLinkTriggerHelperTest {

    private static final String firstFileName = 'First Form_completed.pdf';

    @TestSetup
    private static void initData() {

        Application__c application = new Application__c();
        application.First_Name__c            = 'test';
        application.Second_Name__c           = 'test';
        application.Status__c                = 'Form In Progress';
        application.Stripe_Transaction_Id__c = 'pi_3NPXIALWTMZA1UQ61yylq';
        application.Expiry_Date__c           = Date.today().addDays(5);
        application.Related_Contact_Phone__c = '+120412345';
        application.Email__c                 = 'test@gmail.nm';
        insert application;

    }

    @IsTest
    private static void afterInsertHasDocuSignTest() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Application_Document__c applicationDocument = new Application_Document__c();
        applicationDocument.Application__c = app.Id;
        applicationDocument.File_Name__c = 'First Form';
        applicationDocument.Status__c = 'New';
        insert applicationDocument;

        dfsle__EnvelopeStatus__c envelopeStatus = new dfsle__EnvelopeStatus__c();
        envelopeStatus.dfsle__SourceId__c = app.Id;
        envelopeStatus.Application__c = app.Id;
        envelopeStatus.dfsle__DocuSignId__c = 'docuSignId';
        insert envelopeStatus;

        dfsle__Envelope__c envelope = new dfsle__Envelope__c();
        envelope.dfsle__DocuSignId__c = 'docuSignId';
        insert envelope;

        dfsle__Document__c docuSignDoc = new dfsle__Document__c();
        docuSignDoc.dfsle__Envelope__c = envelope.Id;
        docuSignDoc.dfsle__Extension__c = 'pdf';
        docuSignDoc.dfsle__FullName__c = 'First Form';
        docuSignDoc.dfsle__Type__c = 'ContentVersion';
        insert docuSignDoc;

        ContentVersion contentVersion = new ContentVersion(
                Title = firstFileName,
                PathOnClient = firstFileName,
                VersionData = Blob.valueOf('Test Content'),
                IsMajorVersion = true
        );
        insert contentVersion;
        ContentVersion contentVersionInserted = [SELECT Id, Title, ContentDocumentId FROM ContentVersion WHERE Id = :contentVersion.Id LIMIT 1];
        Test.startTest();
        ContentDocumentLink contentlink = new ContentDocumentLink();
        contentlink.LinkedEntityId = app.Id;
        contentlink.ContentDocumentId = contentVersionInserted.ContentDocumentId;
        contentlink.ShareType = 'V';
        insert contentlink;
        Test.stopTest();
        List<ContentDocumentLink> appDocLinksResult = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId =: applicationDocument.Id];
        System.assertEquals(1, appDocLinksResult.size());
        Application_Document__c applicationDocumentResult = [SELECT Id, Status__c FROM Application_Document__c WHERE Application__c =: app.Id];
        System.assertEquals('Signed', applicationDocumentResult.Status__c);
    }

    @IsTest
    private static void afterInsertNoApplicationDocTest() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        dfsle__EnvelopeStatus__c envelopeStatus = new dfsle__EnvelopeStatus__c();
        envelopeStatus.dfsle__SourceId__c = app.Id;
        envelopeStatus.Application__c = app.Id;
        envelopeStatus.dfsle__DocuSignId__c = 'docuSignId';
        insert envelopeStatus;

        dfsle__Envelope__c envelope = new dfsle__Envelope__c();
        envelope.dfsle__DocuSignId__c = 'docuSignId';
        insert envelope;

        dfsle__Document__c docuSignDoc = new dfsle__Document__c();
        docuSignDoc.dfsle__Envelope__c = envelope.Id;
        docuSignDoc.dfsle__Extension__c = 'pdf';
        docuSignDoc.dfsle__FullName__c = 'First Form';
        docuSignDoc.dfsle__Type__c = 'ContentVersion';
        insert docuSignDoc;

        ContentVersion contentVersion = new ContentVersion(
                Title = firstFileName,
                PathOnClient = firstFileName,
                VersionData = Blob.valueOf('Test Content'),
                IsMajorVersion = true
        );
        insert contentVersion;
        ContentVersion contentVersionInserted = [SELECT Id, Title, ContentDocumentId FROM ContentVersion WHERE Id = :contentVersion.Id LIMIT 1];
        Test.startTest();
        ContentDocumentLink contentlink = new ContentDocumentLink();
        contentlink.LinkedEntityId = app.Id;
        contentlink.ContentDocumentId = contentVersionInserted.ContentDocumentId;
        contentlink.ShareType = 'V';
        insert contentlink;
        Test.stopTest();
        Application_Document__c applicationDocumentResult = [SELECT Id, Status__c FROM Application_Document__c WHERE Application__c =: app.Id];
        System.assertEquals('Signed', applicationDocumentResult.Status__c);
        List<ContentDocumentLink> appDocLinksResult = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId =: applicationDocumentResult.Id]; 
        System.assertEquals(1, appDocLinksResult.size());
    }

}