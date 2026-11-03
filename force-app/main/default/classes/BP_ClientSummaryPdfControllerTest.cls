@IsTest
private class BP_ClientSummaryPdfControllerTest {

    @testSetup
    static void setup() {

        Basic__c app = new Basic__c(

            First_Name__c = 'John',
            Last_Name__c = 'Smith',

            Has_Nino__c = 'Yes',
            Claimant_nino__c = 'QQ123456A',

            Claimant_address1__c = 'Address line 1',
            Claimant_address2__c = 'Address line 2',
            Claimant_City__c = 'London',
            Current_Address_Abroad_State_Name__c = 'Greater London',
            Eircode__c = 'SW1A 1AA',
            Current_Address_Abroad_Country_Name__c = 'United Kingdom'
        );

        insert app;
    }

    @IsTest
    static void testConstructorWithoutId() {

        Test.setCurrentPage(new PageReference('/apex/TestPage'));

        Test.startTest();

        BP_ClientSummaryPdfController controller =
            new BP_ClientSummaryPdfController();

        Test.stopTest();

        System.assertEquals(null, controller.client);
    }

    @IsTest
    static void testConstructorWithId() {

        Basic__c app = [
            SELECT Id
            FROM Basic__c
            LIMIT 1
        ];

        PageReference page = new PageReference('/apex/TestPage');
        page.getParameters().put('id', app.Id);
        Test.setCurrentPage(page);

        Test.startTest();

        BP_ClientSummaryPdfController controller =
            new BP_ClientSummaryPdfController();

        Test.stopTest();

        System.assertNotEquals(null, controller.client);
        System.assertEquals(app.Id, controller.client.Id);

        System.assertEquals('QQ123456A', controller.ninoString);

        System.assert(controller.addressLines.size() > 0);
    }

    @IsTest
    static void testHasNoNino() {

        Basic__c app = new Basic__c(
            First_Name__c = 'Jane',
            Last_Name__c = 'Doe',

            Has_Nino__c = 'Never Had',
            Claimant_nino__c = 'AA111111A'
        );

        insert app;

        PageReference page = new PageReference('/apex/TestPage');
        page.getParameters().put('id', app.Id);
        Test.setCurrentPage(page);

        Test.startTest();

        BP_ClientSummaryPdfController controller =
            new BP_ClientSummaryPdfController();

        Test.stopTest();

        System.assertEquals('Never Had', controller.ninoString);
    }

    @IsTest
    static void testGetApplication() {

        Basic__c app = [
            SELECT Id
            FROM Basic__c
            LIMIT 1
        ];

        Test.startTest();

        List<Basic__c> result =
            BP_ClientSummaryPdfController.getApplication(app.Id);

        Test.stopTest();

        System.assertEquals(1, result.size());
        System.assertEquals(app.Id, result[0].Id);
    }

}