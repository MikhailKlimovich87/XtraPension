public class ResendEstimateController {
    public static String EMAIL_TEMPLATE_NAME = 'Resend Lead Estimate';
    public static final String ORG_WIDE_EMAIL_ADDRESS = 'clients@xtrapension.com';

    @AuraEnabled(cacheable='true')
    public static String resendEstimateEmail(String recordId) {
        List<Lead> leads = [
            SELECT
                FirstName,
                Email,
                Estimate__c
            FROM Lead
            WHERE Id = :recordId
            LIMIT 1
        ];
        if (leads.isEmpty()) {
            return 'Didn\'t find lead';
        }
        OrgWideEmailAddress[] owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :ORG_WIDE_EMAIL_ADDRESS
        ];

        List<EmailTemplate> resendEmailTemplate = [
            SELECT
                Id,
                Subject,
                Description,
                HtmlValue,
                DeveloperName,
                Body
            FROM EmailTemplate
            WHERE Name = :EMAIL_TEMPLATE_NAME
        ];
        Lead currentLead = leads[0];
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setTargetObjectId(currentLead.Id);
        message.setUseSignature(false);
        message.setBccSender(false);
        message.setSaveAsActivity(false);
        message.setHtmlBody(resendEmailTemplate[0].HtmlValue.replace('{!Lead.FirstName}', currentLead.FirstName));
        message.setSubject(currentLead.FirstName + ' - Your UK State Pension Estimate');
        message.setWhatId(currentLead.Id);
        message.toAddresses = new String[] {currentLead.Email};
        message.setTreatTargetObjectAsRecipient(false);
        if ( owea.size() > 0 ) {
            message.setOrgWideEmailAddressId(owea.get(0).Id);
        }
        HttpRequest requestObj = new HttpRequest();
        requestObj.setMethod('GET');
        requestObj.setEndpoint(currentLead.Estimate__c);
        Http httpObj = new Http();
        HttpResponse responseObj = httpObj.send(requestObj);
        Blob blobContent = responseObj.getbodyasblob();
        Messaging.EmailFileAttachment fileAttach = new Messaging.EmailFileAttachment();
        fileAttach.setInline(true);
        fileAttach.setBody(blobContent);
        fileAttach.setFileName('Estimate.pdf');
        message.setFileAttachments(new List<Messaging.EmailFileAttachment>{fileAttach});
        Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
        Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
        return 'Estimate resend successfully';
    }
}