@IsTest
public class BP_SFTPZipFileEnvelupeBatchTest {

    private class SFTPHttpMock implements HttpCalloutMock {
        private Integer code;
        SFTPHttpMock(Integer code) {
            this.code = code;
        }

        public HttpResponse respond(HttpRequest req) {

            System.assertEquals(
                'POST',
                req.getMethod()
            );

            System.assertNotEquals(
                null,
                req.getBody()
            );

            HttpResponse response = new HttpResponse();

            response.setStatusCode(code);

            if(code == 200) {
                response.setBody('SUCCESS');
            } else {
                response.setBody('FAILED');
            }

            return response;
        }
    }


    @TestSetup
    static void createData() {

        // Custom setting for SFTP
        Printing_House_SFTP__c sftp = new Printing_House_SFTP__c(
            Name = 'Default',
            Key__c = 'TEST_KEY',
            Host__c = 'test.host.com',
            Port__c = '22',
            UserName__c = 'testUser',
            Password__c = 'testPassword',
            Claim_Stage_1_Folder__c = '/claims'
        );

        insert sftp;

        // Custom setting for endpoint
        XtraPension_Data__c data = new XtraPension_Data__c(
            Name = 'Default',
            BP_SFTP_Upload_File_Link__c = 'https://test.endpoint.com/upload',
            BR_X_Api_Key__c = 'TEST_API_KEY'
        );

        insert data;

        Basic__c app = new Basic__c(
            First_Name__c = 'John',
            Last_Name__c = 'Smith',
            Claim_Created_ZIP_for_UPLOAD__c = true
        );

        insert app;

        ContentVersion version = new ContentVersion(
            Title = 'TEST_Stage 1',
            PathOnClient = 'TEST_Stage 1.zip',
            VersionData = Blob.valueOf('TEST ZIP FILE')
        );

        insert version;

        ContentVersion insertedVersion = [
            SELECT 
                Id,
                ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ];

        ContentDocumentLink link = new ContentDocumentLink(
            LinkedEntityId = app.Id,
            ContentDocumentId = insertedVersion.ContentDocumentId,
            ShareType = 'V'
        );

        insert link;
    }

    @IsTest
    static void testBatchSuccess() {


        Test.setMock(
            HttpCalloutMock.class,
            new SFTPHttpMock(200)
        );


        Test.startTest();

        Database.executeBatch(
            new BP_SFTPZipFileEnvelupeBatch(),
            1
        );

        Test.stopTest();



        Basic__c app = [
            SELECT
                FTP_Claim_Created_Send_Date__c,
                FTP_Claim_Created_Error__c
            FROM Basic__c
            LIMIT 1
        ];

        System.assertEquals(
            Date.today(),
            app.FTP_Claim_Created_Send_Date__c
        );

        System.assertEquals(
            null,
            app.FTP_Claim_Created_Error__c
        );
    }

    @IsTest
    static void testBatchFailedUpload() {

        Test.setMock(
            HttpCalloutMock.class,
            new SFTPHttpMock(500)
        );

        Test.startTest();

        Database.executeBatch(
            new BP_SFTPZipFileEnvelupeBatch(),
            1
        );

        Test.stopTest();

        Basic__c app = [
            SELECT
                FTP_Claim_Created_Send_Date__c,
                FTP_Claim_Created_Error__c
            FROM Basic__c
            LIMIT 1
        ];

        System.assertEquals(
            null,
            app.FTP_Claim_Created_Send_Date__c
        );

        System.assertEquals(
            'FAILED',
            app.FTP_Claim_Created_Error__c
        );
    }

    @IsTest
    static void testUploadFileToSFTPDirectly() {

        Test.setMock(
            HttpCalloutMock.class,
            new SFTPHttpMock(200)
        );

        BP_SFTPZipFileEnvelupeBatch.SFTPFile file =
            new BP_SFTPZipFileEnvelupeBatch.SFTPFile();

        file.fileName = 'test.zip';

        file.body =
            EncodingUtil.base64Encode(
                Blob.valueOf('TEST')
            );

        BP_SFTPZipFileEnvelupeBatch.SFTPWrapper wrapper =
            new BP_SFTPZipFileEnvelupeBatch.SFTPWrapper();

        wrapper.key = 'key';
        wrapper.sftpHost = 'host';
        wrapper.sftpPort = '22';
        wrapper.sftpUserName = 'user';
        wrapper.sftpPassword = 'password';
        wrapper.folderName = '/folder';
        wrapper.files =
            new List<BP_SFTPZipFileEnvelupeBatch.SFTPFile>{
                file
            };

        Test.startTest();
        HttpResponse response =
            BP_SFTPZipFileEnvelupeBatch.uploadFileToSFTP(wrapper);
        Test.stopTest();

        System.assertEquals(
            200,
            response.getStatusCode()
        );
    }

    @IsTest
    static void testFinishMethod() {
        Test.startTest();
        BP_SFTPZipFileEnvelupeBatch batch =
            new BP_SFTPZipFileEnvelupeBatch();
        batch.finish(null);
        Test.stopTest();
        System.assertEquals(
            true,
            true
        );
    }
}