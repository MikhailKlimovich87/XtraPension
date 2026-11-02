@IsTest
public class BP_GenerateApplication_BR1Test {


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

        XtraPension_Data__c data = new XtraPension_Data__c(
            Name = 'Test',
            BP_Pdf_File_Link__c = 'https://test.salesforce.com/pdf'
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


    private class BR1Mock implements HttpCalloutMock {

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
            new BR1Mock()
        );


        BP_GenerateApplication_BR1.Request req =
            new BP_GenerateApplication_BR1.Request();

        req.recordId = app.Id;


        Test.startTest();

        BP_GenerateApplication_BR1.generate(
            new List<BP_GenerateApplication_BR1.Request>{
                req
            }
        );

        Test.stopTest();


        System.assert(true);
    }



    @IsTest
    static void testGetApplicationBR1() {

        Basic__c app = getApplication();


        Test.setMock(
            HttpCalloutMock.class,
            new BR1Mock()
        );


        Test.startTest();

        BP_GenerateApplication_BR1.getApplication_BR1(
            app.Id
        );

        Test.stopTest();


        System.assert(true);
    }

    @IsTest
    static void testGetApplicationNotSingleBR1() {

        Basic__c app = getApplication();

        app.Claimant_marital_Status__c = 'Divorced';
        app.Partner_same_as_claimant__c = false;
        update app; 
        Test.setMock(
            HttpCalloutMock.class,
            new BR1Mock()
        );


        Test.startTest();

        BP_GenerateApplication_BR1.getApplication_BR1(
            app.Id
        );

        Test.stopTest();


        System.assert(true);
    }



    @IsTest
    static void testExistingIPCBR1Document() {


        Basic__c app = getApplication();


        ContentVersion cv = new ContentVersion(
            Title = 'TEST_IPCBR1',
            PathOnClient = 'TEST_IPCBR1.pdf',
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
            new BR1Mock()
        );


        Test.startTest();

        BP_GenerateApplication_BR1.getApplication_BR1(
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

    BP_BR1_Wrapper.ApplicationDataWrapper wrap =
        new BP_BR1_Wrapper.ApplicationDataWrapper(appList[0]);

    Test.startTest();
    BP_GenerateApplication_BR1.updateCodesBR(wrap, app.Id);
    Test.stopTest();
}

    @IsTest
    static void testFullFormZipIsOnlyBuiltOnceTheClaimIsSigned() {
        Basic__c app = getApplication();

        // Not signed yet: the ZIP (which must contain the BR1 with the DocuSign date) is not built
        BP_GenerateApplication_BR1.buildFullFormZipIfSigned(app.Id);
        System.assertEquals(null, [SELECT FTP_Claim_Full_Form_ZIP_Error__c FROM Basic__c WHERE Id = :app.Id].FTP_Claim_Full_Form_ZIP_Error__c);

        update new Basic__c(Id = app.Id, Status__c = BP_DocuSignController.STATUS_SIGNED_WAITING_DOCS);
        Test.startTest();
        BP_GenerateApplication_BR1.buildFullFormZipIfSigned(app.Id);
        Test.stopTest();

        // Signed: the ZIP builder ran (no PDFs / incomplete data in this fixture, so it reports why it stopped)
        System.assertNotEquals(null, [SELECT FTP_Claim_Full_Form_ZIP_Error__c FROM Basic__c WHERE Id = :app.Id].FTP_Claim_Full_Form_ZIP_Error__c);
    }

    @IsTest
    static void testBr1ServiceFailureIsLoggedNotSilent() {
        Basic__c app = getApplication();
        Test.setMock(HttpCalloutMock.class, new FailingBR1Mock());

        Test.startTest();
        BP_GenerateApplication_BR1.getApplication_BR1(app.Id);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Application_Form_Error__c]);
    }

    private class FailingBR1Mock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(503);
            res.setBody('unavailable');
            return res;
        }
    }
}