public class EmailService {
    public string subject{get;set;}
    public String[] toAddresses{get;set;}
    public List<String> CCAddresses{get;set;}
    public String body{set;get;}
    public string displayName{set;get;}
    public boolean isAttachment{set;get;}
    public Map<String,String> attachFiles{set;get;}
    public boolean isHtml{set;get;}
    public List<Messaging.EmailFileAttachment> attachments;
    public Messaging.SingleEmailMessage email;

    public EmailService() {
        attachments = new List<Messaging.EmailFileAttachment>();
        email = new Messaging.SingleEmailMessage();
        this.isAttachment = false;
        this.isHtml = false;
    }

    public EmailService(Messaging.SingleEmailMessage mailMessage) {
        attachments = new List<Messaging.EmailFileAttachment>();
        email = mailMessage;
        this.isAttachment = false;
    }

    public Messaging.SendEmailResult [] sendMail() {
        if(isAttachment) {
            for (String name : attachFiles.keySet()) {
                Messaging.EmailFileAttachment csvAttc = new Messaging.EmailFileAttachment();
                blob csvBlob = Blob.valueOf(attachFiles.get(name));
                string csvname = name +'.pdf';
                // csvAttc.setContentType('text/csv');
                csvAttc.setFileName(csvname);
                csvAttc.setBody(csvBlob);
                attachments.add(csvAttc);
            }
        }
        email.setSubject(subject);
        email.setToAddresses(toAddresses);
        email.setSenderDisplayName(displayName);

        if(isHtml) email.setHtmlBody(body);
        else email.setPlainTextBody(body);

        if(isAttachment) email.setFileAttachments(attachments);

        Messaging.SendEmailResult [] result = Messaging.sendEmail(new Messaging.SingleEmailMessage[] {email});
        return result;
    }
}