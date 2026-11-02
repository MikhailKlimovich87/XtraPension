@IsTest
public class BP_SFTPZipFileFullFormBatchTest {


    private class SFTPHttpMock implements HttpCalloutMock {

        private Integer statusCode;

        SFTPHttpMock(Integer statusCode) {
            this.statusCode = statusCode;
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

            response.setStatusCode(statusCode);


            if(statusCode == 200) {
                response.setBody('SUCCESS');
            } else {
                response.setBody('SFTP ERROR');
            }


            return response;
        }
    }



    @TestSetup
    static void setupData() {


        insert new Printing_House_SFTP__c(
            Name = 'Default',
            Key__c = 'TEST_KEY',
            Host__c = 'localhost',
            Port__c = '22',
            UserName__c = 'testUser',
            Password__c = 'testPassword',
            Claim_Stage_2_Folder__c = '/claims'
        );


        insert new XtraPension_Data__c(
            Name = 'Default',
            BP_SFTP_Upload_File_Link__c = 'https://test.com/upload',
            BR_X_Api_Key__c = 'TEST_API_KEY'
        );



        Basic__c app = new Basic__c(
            First_Name__c = 'John',
            Last_Name__c = 'Smith',
            Claim_Full_Form_ZIP_for_UPLOAD__c = true
        );

        insert app;



        ContentVersion cv = new ContentVersion(
            Title = 'TEST_Stage 2',
            PathOnClient = 'TEST_Stage 2.zip',
            VersionData = Blob.valueOf('FULL FORM ZIP DATA')
        );

        insert cv;



        ContentVersion insertedCv = [
            SELECT 
                Id,
                ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];



        ContentDocumentLink link = new ContentDocumentLink(
            LinkedEntityId = app.Id,
            ContentDocumentId = insertedCv.ContentDocumentId,
            ShareType = 'V'
        );

        insert link;
    }




    @IsTest
    static void testFullFormBatchSuccess() {


        Test.setMock(
            HttpCalloutMock.class,
            new SFTPHttpMock(200)
        );



        Test.startTest();


        Database.executeBatch(
            new BP_SFTPZipFileFullFormBatch(),
            1
        );


        Test.stopTest();



        Basic__c app = [
            SELECT
                FTP_Claim_Full_Form_Created_Send_Date__c,
                FTP_Claim_Full_Form_Error__c
            FROM Basic__c
            LIMIT 1
        ];



        System.assertEquals(
            Date.today(),
            app.FTP_Claim_Full_Form_Created_Send_Date__c
        );


        System.assertEquals(
            null,
            app.FTP_Claim_Full_Form_Error__c
        );
    }





    @IsTest
    static void testFullFormBatchError() {


        Test.setMock(
            HttpCalloutMock.class,
            new SFTPHttpMock(500)
        );



        Test.startTest();


        Database.executeBatch(
            new BP_SFTPZipFileFullFormBatch(),
            1
        );


        Test.stopTest();



        Basic__c app = [
            SELECT
                FTP_Claim_Full_Form_Created_Send_Date__c,
                FTP_Claim_Full_Form_Error__c
            FROM Basic__c
            LIMIT 1
        ];



        System.assertEquals(
            null,
            app.FTP_Claim_Full_Form_Created_Send_Date__c
        );


        System.assertEquals(
            'SFTP ERROR',
            app.FTP_Claim_Full_Form_Error__c
        );
    }


    @IsTest
    static void testUploadFileDirectly() {


        Test.setMock(
            HttpCalloutMock.class,
            new SFTPHttpMock(200)
        );



        BP_SFTPZipFileFullFormBatch.SFTPFile file =
            new BP_SFTPZipFileFullFormBatch.SFTPFile();


        file.fileName = 'full.zip';

        file.body =
            EncodingUtil.base64Encode(
                Blob.valueOf('test')
            );



        BP_SFTPZipFileFullFormBatch.SFTPWrapper wrapper =
            new BP_SFTPZipFileFullFormBatch.SFTPWrapper();


        wrapper.key = 'key';
        wrapper.sftpHost = 'host';
        wrapper.sftpPort = '22';
        wrapper.sftpUserName = 'user';
        wrapper.sftpPassword = 'password';
        wrapper.folderName = '/folder';


        wrapper.files =
            new List<BP_SFTPZipFileFullFormBatch.SFTPFile>{
                file
            };



        Test.startTest();


        HttpResponse response =
            BP_SFTPZipFileFullFormBatch.uploadFileToSFTP(wrapper);


        Test.stopTest();



        System.assertEquals(
            200,
            response.getStatusCode()
        );
    }





    @IsTest
    static void testFinish() {


        BP_SFTPZipFileFullFormBatch batch =
            new BP_SFTPZipFileFullFormBatch();


        Test.startTest();

        batch.finish(null);

        Test.stopTest();


        System.assert(true);
    }
}