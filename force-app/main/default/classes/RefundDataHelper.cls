public class RefundDataHelper {
    public static final String EMAIL_TEMPALTE_NAME = 'Refund Credit Note';

    public static String setBodyValues(string body,Map<String,String> params){
        if(params!=null && params.size()>0){
            for(String key :params.keySet()){
                string val=params.get(key);
                body=body.replace(key,val);
                system.debug('body:'+body);
            }
        }
        return body;
    }

    public static void generateCreditNotePdf() {
        // Messaging.EmailFileAttachment attach = new Messaging.EmailFileAttachment();
        // attach.setContentType('application/pdf');
        // attach.setFileName(fileName);
        // attach.setInline(true);
        EmailTemplate creditNoteTemplate = getEmailTemplate(EMAIL_TEMPALTE_NAME);
       	String bodyValue = creditNoteTemplate.HtmlValue;
        System.debug('body === ' + creditNoteTemplate.Body);
        //System.debug('blob === ' + Blob.valueOf(creditNoteTemplate.Body));
        // ContentVersion contVerFile = new ContentVersion();
        // contVerFile.VersionData = Blob.toPDF(body);
        // contVerFile.Title = 'TestNote';
        // contVerFile.ContentLocation = 's';
        // contVerFile.PathOnClient = 'TestNote.pdf';
        // insert contVerFile;

        //body = setBodyValues(body,emailContent);
        // attach.Body = Blob.toPDF(body);
        // return attach;
    }

    public static EmailTemplate getEmailTemplate(String name) {
        return [
            SELECT
                Id,
                Name,
                Subject,
                HtmlValue,
                Body
            FROM EmailTemplate
            WHERE Name=:name
            LIMIT 1
        ];
    }

}