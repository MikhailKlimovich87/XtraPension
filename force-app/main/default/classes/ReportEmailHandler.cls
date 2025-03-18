public class ReportEmailHandler {
    // public static final String REPORT_DEV_NAME = 'Applications_With_Posted_Status_7ea';
    // public static final String[] RECIPIENT_EMAILS = new String[] {
    //     'john@tinderpoint.com',
    //     'monica@tinderpoint.com'
    // };
    public static final String ORG_WIDE_EMAIL_ADDRESS = 'clients@xtrapension.com';

    @future(callout=true)
    public static void sendReport(String reportName, List<String> recipientsEmails, String subject) {
        try {
            List <Report> reportList = [
                SELECT
                    DeveloperName,
                    Name
                FROM Report
                WHERE DeveloperName =:reportName
            ];
            if (reportList.isEmpty()) {
                return;
            }
            Report postedApplicationReport = reportList[0];
            String instanceName = URL.getOrgDomainUrl().toExternalForm();
            String url = instanceName + '/servlet/PrintableViewDownloadServlet?isdtp=p1&reportId=' + postedApplicationReport.Id;

            ApexPages.PageReference objPage = new ApexPages.PageReference(url);

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();

            Messaging.EmailFileAttachment objMsgEmailAttach = new Messaging.EmailFileAttachment();
            objMsgEmailAttach.setFileName(postedApplicationReport.Name + '.xlsx');
            if (!Test.isRunningTest()) {
                objMsgEmailAttach.setBody(objPage.getContent());
            } else {
                objMsgEmailAttach.setBody(Blob.valueOf('Test'));
            }
            objMsgEmailAttach.setContentType('text/xlsx');
            email.setSubject(postedApplicationReport.Name);

            List<Messaging.EmailFileAttachment> attach = new List<Messaging.EmailFileAttachment>();
            attach.add(objMsgEmailAttach);
            email.setFileAttachments(attach);

            OrgWideEmailAddress[] owea = [
                SELECT Id
                FROM OrgWideEmailAddress
                WHERE Address = :ORG_WIDE_EMAIL_ADDRESS
            ];
            Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
            message.setUseSignature(false);
            message.setBccSender(false);
            message.setSaveAsActivity(false);
            message.setSubject(subject);
            message.setPlainTextBody('');
            message.setFileAttachments(attach);
            message.setToAddresses(recipientsEmails);
            if ( owea.size() > 0 ) {
                message.setOrgWideEmailAddressId(owea.get(0).Id);
            }
            Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
            Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
            System.debug('results === ' + results);
        } catch (Exception ex) {
            System.debug('Exception: ' + ex.getMessage());
        }
    }

}