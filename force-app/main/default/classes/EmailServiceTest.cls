@isTest
public class EmailServiceTest {

    @IsTest
    static void sendReportTestCase1() {
        EmailService service = new EmailService();
        service.body = '';
        service.isHtml = false;
        service.toAddresses = new List<String>{'john.snow@gmail.com'};
        service.displayName = 'Test';
        service.subject = 'Test subject';
        Test.startTest();
        Messaging.SendEmailResult [] result = service.sendMail();
        Test.stopTest();
        System.assertEquals(1, result.size());
        System.assertEquals(true, result.get(0).isSuccess());
    }

    @IsTest
    static void sendReportTestCase2() {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();

        Messaging.EmailFileAttachment objMsgEmailAttach = new Messaging.EmailFileAttachment();
        objMsgEmailAttach.setFileName('Test.xlsx');
        objMsgEmailAttach.setBody(Blob.valueOf('Test'));
        objMsgEmailAttach.setContentType('text/xlsx');
        email.setSubject('Test');
        List<Messaging.EmailFileAttachment> attach = new List<Messaging.EmailFileAttachment>();
        attach.add(objMsgEmailAttach);
        email.setFileAttachments(attach);

        EmailService service = new EmailService(email);
        service.body = '';
        service.isHtml = false;
        service.toAddresses = new List<String>{'john.snow@gmail.com'};
        service.displayName = 'Test';
        service.subject = 'Test subject';
        service.isAttachment = true;
        Map<String,String> attachFilesData = new Map<String,String>{'Test' => 'Test Data'};
        service.attachFiles = attachFilesData;
        Test.startTest();
        Messaging.SendEmailResult [] result = service.sendMail();
        Test.stopTest();
        System.assertEquals(1, result.size());
        System.assertEquals(true, result.get(0).isSuccess());
    }
}