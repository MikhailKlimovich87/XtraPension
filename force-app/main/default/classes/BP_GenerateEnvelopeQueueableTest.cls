@IsTest
private class BP_GenerateEnvelopeQueueableTest {


    private class PdfMock implements HttpCalloutMock {

        public HTTPResponse respond(HTTPRequest req) {

            HttpResponse res = new HttpResponse();

            res.setStatusCode(200);
            res.setHeader(
                'Content-Type',
                'application/json'
            );

            res.setBody(
                JSON.serialize(
                    new Map<String, Object>{
                        'base64' => EncodingUtil.base64Encode(
                            Blob.valueOf('PDF DATA')
                        ),
                        'fileType' => 'pdf',
                        'fileName' => 'test'
                    }
                )
            );

            return res;
        }
    }


    @TestSetup
    static void setup() {

        Basic__c basic = new Basic__c(
            First_Name__c = 'John',
            Last_Name__c = 'Smith'
        );

        insert basic;


        XtraPension_Data__c data = new XtraPension_Data__c(
            BP_Pdf_File_Link__c = 'callout:test',
            BP_Pdf_File_IPC1394_Link__c = 'callout:test',
            BP_PDF_IPCBR1_Wet__c = 'callout:test',
            BP_PDF_IPC1394_Wet__c = 'callout:test'
        );

        insert data;
    }


    @IsTest
    static void testExecute() {

        Basic__c basic = [
            SELECT Id
            FROM Basic__c
            LIMIT 1
        ];


        Test.setMock(
            HttpCalloutMock.class,
            new PdfMock()
        );


        Test.startTest();

        Id jobId = System.enqueueJob(
            new BP_GenerateEnvelopeQueueable(
                basic.Id
            )
        );

        Test.stopTest();


        System.assertNotEquals(
            null,
            jobId
        );


        List<ContentDocumentLink> documents = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :basic.Id
        ];


        System.assert(
            documents.size() > 0
        );
    }


    @IsTest
    static void testConstructor() {

        Basic__c basic = [
            SELECT Id
            FROM Basic__c
            LIMIT 1
        ];


        BP_GenerateEnvelopeQueueable queueable =
            new BP_GenerateEnvelopeQueueable(
                basic.Id
            );


        System.assertNotEquals(
            null,
            queueable
        );
    }
}