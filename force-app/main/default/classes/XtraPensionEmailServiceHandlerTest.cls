@isTest
public with sharing class XtraPensionEmailServiceHandlerTest {
    @TestSetup
    static void setup(){
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
    static void handleInboundEmailTest() {
        Application__c testApplicaition = [
            SELECT
                Name,
                First_Name__c,
                Second_Name__c,
                Email__c,
                Tracking_Number__c,
                Tracking_Number_Received_Date__c,
                Tracking_Number_Sent_Date__c
            FROM Application__c
            LIMIT 1
        ];
        Messaging.InboundEmail email = new Messaging.InboundEmail() ;
        String subject = testApplicaition.First_Name__c + ' ' +
                         testApplicaition.Second_Name__c + ' - ' +
                         testApplicaition.Name;
        email.subject = subject;
        email.fromAddress = 'test.xtrapension@email.com';
        String trackingNumber = '1234567421';
        email.plainTextBody = 'Name: ' + testApplicaition.First_Name__c + ' ' + testApplicaition.Second_Name__c + '\n' +
                              'AppID: ' + testApplicaition.Name + '\n\n' +
                              'Tracking No: ' + trackingNumber + '\n' +
                              'Tracking No Rx\'d by Printer: 24 Jul 2023 17:45 \n' +
                              'Service: Royal Mail Track24';
        email.toAddresses = new List<String> {
            testApplicaition.Email__c
        };
        Messaging.InboundEnvelope env = new Messaging.InboundEnvelope();
        System.assertEquals(null, testApplicaition.Tracking_Number__c, 'Tracking_Number__c must be null before update');
        System.assertEquals(null, testApplicaition.Tracking_Number_Received_Date__c, 'Tracking_Number_Received_Date__c must be null before update');
        System.assertEquals(null, testApplicaition.Tracking_Number_Sent_Date__c, 'Tracking_Number_Sent_Date__c must be null before update');
        Test.startTest();
        XtraPensionEmailServiceHandler testInbound = new XtraPensionEmailServiceHandler();
        testInbound.handleInboundEmail(email, env);
        Test.stopTest();

        Application__c testApplicaitionAfterUpdate = [
            SELECT
                Tracking_Number__c,
                Tracking_Number_Received_Date__c,
                Tracking_Number_Sent_Date__c
            FROM Application__c
            LIMIT 1
        ];
        System.assertEquals(trackingNumber, testApplicaitionAfterUpdate.Tracking_Number__c, 'Tracking_Number__c must be like in incomung email');
        System.assertNotEquals(null, testApplicaitionAfterUpdate.Tracking_Number__c, 'Tracking_Number__c must be not null after update');
        System.assertNotEquals(null, testApplicaitionAfterUpdate.Tracking_Number_Received_Date__c, 'Tracking_Number_Received_Date__c must be not null after update');
        //System.assertNotEquals(null, testApplicaitionAfterUpdate.Tracking_Number_Sent_Date__c, 'Tracking_Number_Sent_Date__c must be not null after update');

    }
}