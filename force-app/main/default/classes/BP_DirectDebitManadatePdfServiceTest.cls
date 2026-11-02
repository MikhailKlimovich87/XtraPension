@IsTest
public class BP_DirectDebitManadatePdfServiceTest {
    private class EndpointMock implements HttpCalloutMock {
        private String expectedEndpoint;
        private Integer callCount = 0;

        EndpointMock(String expectedEndpoint) {
            this.expectedEndpoint = expectedEndpoint;
        }

        public HttpResponse respond(HttpRequest request) {
            callCount++;
            System.assertEquals(expectedEndpoint, request.getEndpoint());
            System.assertEquals('POST', request.getMethod());
            System.assert(((Map<String, Object>) JSON.deserializeUntyped(request.getBody())).containsKey('claim'));

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');
            response.setBody('{"base64":"' + EncodingUtil.base64Encode(Blob.valueOf('PDF-DATA')) + '"}');
            return response;
        }
    }

    @TestSetup
    static void setup() {
        XtraPension_Data__c settings = TestDataFactory.createXtraPensionDataCustomSetting(false);
        settings.BP_DD_Mandate_Pdf_File_Link__c = 'https://example.test/mandate-eur';
        settings.BP_DD_Mandate_Australia_Pdf_File_Link__c = 'https://example.test/mandate-aud';
        insert settings;

        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Contact contact = [
            SELECT Id
            FROM Contact
            WHERE AccountId = :account.Id
            LIMIT 1
        ];
        BP_TestDataFactory.createBasic(contact.Id, true);

        Basic__c gbpApplication = BP_TestDataFactory.createBasic(contact.Id, false);
        gbpApplication.CurrencyIsoCode = 'GBP';
        insert gbpApplication;

        Basic__c audApplication = BP_TestDataFactory.createBasic(contact.Id, false);
        audApplication.CurrencyIsoCode = 'AUD';
        insert audApplication;
    }

    @IsTest
    static void generatePdfRoutesByCurrency() {
        Basic__c application = [
            SELECT Id, CurrencyIsoCode
            FROM Basic__c
            LIMIT 1
        ];

        EndpointMock eurMock = new EndpointMock('https://example.test/mandate-eur');
        Test.setMock(HttpCalloutMock.class, eurMock);
        Test.startTest();
        BP_DirectDebitManadatePdfService.generatePdf(null);
        BP_DirectDebitManadatePdfService.generatePdf(application.Id);
        Test.stopTest();
        System.assertEquals(0, eurMock.callCount);

    }

    @IsTest
    static void generatePdfUsesAustraliaEndpoint() {
        Basic__c application = [
            SELECT Id
            FROM Basic__c
            WHERE CurrencyIsoCode = 'AUD'
            LIMIT 1
        ];
        EndpointMock audMock = new EndpointMock('https://example.test/mandate-aud');
        Test.setMock(HttpCalloutMock.class, audMock);
        Test.startTest();
        BP_DirectDebitManadatePdfService.generatePdf(application.Id);
        Test.stopTest();
        System.assertEquals(0, audMock.callCount);
    }

    @IsTest
    static void generatePdfReturnsForUnsupportedCurrency() {
        Basic__c application = [
            SELECT Id
            FROM Basic__c
            WHERE CurrencyIsoCode = 'GBP'
            LIMIT 1
        ];
        EndpointMock unsupportedCurrencyMock = new EndpointMock('https://example.test/mandate-eur');
        Test.setMock(HttpCalloutMock.class, unsupportedCurrencyMock);
        BP_DirectDebitManadatePdfService.generatePdf(application.Id);
        System.assertEquals(0, unsupportedCurrencyMock.callCount);
    }

    @IsTest
    static void createsAndUpdatesMandateDocument() {
        Basic__c application = [
            SELECT Id
            FROM Basic__c
            LIMIT 1
        ];
        String initialBody = '{"base64":"' + EncodingUtil.base64Encode(Blob.valueOf('INITIAL-PDF')) + '"}';

        Test.startTest();
        BP_DirectDebitManadatePdfService.generateDocument(
            initialBody,
            application.Id,
            'Mandate_Test'
        );
        Test.stopTest();

        ContentDocumentLink documentLink = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :application.Id
            LIMIT 1
        ];
        List<ContentVersion> versions = [
            SELECT Id, Title, VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :documentLink.ContentDocumentId
        ];
        System.assertEquals(1, versions.size());
        System.assertEquals('Mandate_Test', versions[0].Title);

        String updatedBody = '{"base64":"' + EncodingUtil.base64Encode(Blob.valueOf('UPDATED-PDF')) + '"}';
        BP_DirectDebitManadatePdfService.updateDocumentVersion(
            updatedBody,
            'Mandate_Test',
            'pdf',
            new List<ContentDocumentLink>{ documentLink }
        );

        System.assertEquals(
            2,
            [
                SELECT COUNT()
                FROM ContentVersion
                WHERE ContentDocumentId = :documentLink.ContentDocumentId
            ]
        );
    }

    @IsTest
    static void returnsNullForInvalidContentLinkArguments() {
        System.assertEquals(
            null,
            BP_DirectDebitManadatePdfService.createContentLink(null, null)
        );
        BP_DirectDebitManadatePdfService.updateDocumentVersion(
            '',
            'Mandate_Test',
            'pdf',
            new List<ContentDocumentLink>()
        );
        BP_DirectDebitManadatePdfService.generateDocument('', null, 'Mandate_Test');
    }
}