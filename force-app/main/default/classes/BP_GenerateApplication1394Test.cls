@IsTest
public class BP_GenerateApplication1394Test {


    @TestSetup
    static void setup() {

        TestDataFactory.createTestCountry(true);

        Account acc = TestDataFactory.createAccount(true);

        Contact con = [
            SELECT Id
            FROM Contact
            WHERE AccountId = :acc.Id
            LIMIT 1
        ];

        Basic__c app = BP_TestDataFactory.createBasic(con.Id, true);

        app.First_Name__c = 'John';
        app.Last_Name__c = 'Smith';
        app.Email__c = 'john@test.com';
        update app;

        Claimant_Child__c child = BP_TestDataFactory.createChild(app.Id, true);
        Claimant_Child__c child2 = BP_TestDataFactory.createChild(app.Id, true);
        Claimant_Child__c child3 = BP_TestDataFactory.createChild(app.Id, true);
        Claimant_Company__c company = BP_TestDataFactory.createCompany(app.Id, true);
        Claimant_Company__c company2 = BP_TestDataFactory.createCompany(app.Id, true);
        Claimant_Company__c company3 = BP_TestDataFactory.createCompany(app.Id, true);
        Claimant_Company__c company4 = BP_TestDataFactory.createCompanyPartner(app.Id, true);
        Claimant_Company__c company5 = BP_TestDataFactory.createCompanyPartner(app.Id, true);
        Claimant_Company__c company6 = BP_TestDataFactory.createCompanyPartner(app.Id, true);
        Claimant_Company__c company7 = BP_TestDataFactory.createCompanyUkAddress(app.Id, true);
        Claimant_Company__c company8 = BP_TestDataFactory.createCompanyUkAddress(app.Id, true);
        Claimant_Company__c company9 = BP_TestDataFactory.createCompanyUkAddress(app.Id, true);
        Claimant_Country_lived__c country = BP_TestDataFactory.createCountryLived(app.Id, true);
        Claimant_Country_lived__c country2 = BP_TestDataFactory.createCountryLived(app.Id, true);
        Claimant_Country_lived__c country3 = BP_TestDataFactory.createCountryLived(app.Id, true);

        app.First_Name__c = 'John';
        app.Last_Name__c = 'Smith';
        app.Email__c = 'john@test.com';
        update app;

        XtraPension_Data__c data = new XtraPension_Data__c(
            Name = 'Test',
            BP_Pdf_File_IPC1394_Link__c = 'https://test.salesforce.com/pdf'
        );
        insert data;
    }


    private static Basic__c getApplication() {
        return [
            SELECT Id
            FROM Basic__c
            LIMIT 1
        ];
    }


    private class X1394Mock implements HttpCalloutMock {

        public HTTPResponse respond(HTTPRequest req) {

            System.assertEquals(
                'POST',
                req.getMethod()
            );

            System.assert(
                req.getBody().contains('application')
            );

            HttpResponse res = new HttpResponse();

            res.setStatusCode(200);

            res.setBody(
                EncodingUtil.base64Encode(
                    Blob.valueOf('TEST PDF')
                )
            );

            return res;
        }
    }


    @IsTest
    static void testGenerate() {

        Basic__c app = getApplication();


        Test.setMock(
            HttpCalloutMock.class,
            new X1394Mock()
        );


        BP_GenerateApplication1394.Request req =
            new BP_GenerateApplication1394.Request();

        req.recordId = app.Id;


        Test.startTest();

        BP_GenerateApplication1394.generate(
            new List<BP_GenerateApplication1394.Request>{
                req
            }
        );

        Test.stopTest();


        System.assert(true);
    }



    @IsTest
    static void testGetApplication1394() {

        Basic__c app = getApplication();


        Test.setMock(
            HttpCalloutMock.class,
            new X1394Mock()
        );


        Test.startTest();

        BP_GenerateApplication1394.getApplication_1394(
            app.Id
        );

        Test.stopTest();


        System.assert(true);
    }



    @IsTest
    static void testExistingIPC1394Document() {


        Basic__c app = getApplication();


        ContentVersion cv = new ContentVersion(
            Title = 'TEST_IPC1394',
            PathOnClient = 'TEST_IPC1394.pdf',
            VersionData = Blob.valueOf('test'),
            IsMajorVersion = true
        );

        insert cv;


        cv = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];


        insert new ContentDocumentLink(
            LinkedEntityId = app.Id,
            ContentDocumentId = cv.ContentDocumentId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );


        Test.setMock(
            HttpCalloutMock.class,
            new X1394Mock()
        );


        Test.startTest();

        BP_GenerateApplication1394.getApplication_1394(
            app.Id
        );

        Test.stopTest();


        System.assert(true);
    }

    @IsTest
static void testUpdateCodes() {

    TestDataFactory.createTestCountry(true);

    Account acc = TestDataFactory.createAccount(true);

    Contact con = [
        SELECT Id
        FROM Contact
        WHERE AccountId = :acc.Id
        LIMIT 1
    ];

    Basic__c app = BP_TestDataFactory.createBasic(con.Id, true);

    app.Current_Address_Abroad_State_Name__c = 'Leinster';
    app.Current_Address_Abroad_Country_Name__c = 'Ireland';
    app.Partner_Country__c = 'United Kingdom';

    update app;

    List<Basic__c> appList = BP_PortalUtils.getApplication(app.Id);

    BP_ResponseWrappers.ApplicationDataWrapper wrap =
        new BP_ResponseWrappers.ApplicationDataWrapper(appList);

    Test.startTest();
    BP_GenerateApplication1394.updateCodes(wrap);
    Test.stopTest();
}

}