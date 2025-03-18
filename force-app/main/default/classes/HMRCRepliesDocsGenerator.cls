public class HMRCRepliesDocsGenerator implements Queueable, Database.AllowsCallouts {
    public String applicationId;
    public String typeOfTemplate;
    public final Map<String, String> FIELD_BODY_TO_FILE_NAME = new Map<String, String> {
        'NINO_Template__c'                => 'NINO reply',
        'Custom_Reply_Template__c'        => 'CUSTOM reply',
        'Appeal_Template__c'              => 'APPEAL reply',
        'Current_Job_Reply_Template__c'   => 'CURRENT JOB reply',
        'DWP_Status_Check_Template__c'    => 'DWPStatusCheck',
        'Certified_Doc_Template__c'       => 'CerifiedDoc',
        'EU_Residency_Appeal_Template__c' => 'EU Residency Appeal',
        'Maiden_Name_Template__c'         => 'Maiden Name',
        'DWP_C2_Request_Template__c'      => 'DWP C2 Request'
    };

    private final static String ORG_WIDE = 'clients@xtrapension.com';
    private final static String CERTIFIED_TEMPLATE_NAME = 'Certified Proof';

    public HMRCRepliesDocsGenerator(String recordId, String templateName) {
        applicationId  = recordId;
        typeOfTemplate = templateName;
    }

    public void execute(QueueableContext context) {
        if (typeOfTemplate == 'Certified_Doc_Template__c') {
            List<Application__c> apps = [
			    SELECT
				    First_Name__c,
				    Second_Name__c,
				    Name
			    FROM Application__c
			    WHERE Id = :applicationId
		    ];
		    if(apps.isEmpty()) return;
		    Application__c currentApplication = apps[0];
            PageReference savepage = Page.CertifiedProof;
            savepage.getParameters().put('id', applicationId);
            blob pdfBlob;
            if (!Test.isRunningTest()) {
           	    pdfBlob = savepage.getContent();
            } else {
           	    pdfBlob = Blob.valueOf('Test');
            }
            String finalTitle = currentApplication.First_Name__c + '_' + currentApplication.Second_Name__c + '_' +
                                currentApplication.Name + '_' + FIELD_BODY_TO_FILE_NAME.get(typeOfTemplate);

            saveFile(pdfBlob, finalTitle);            
        } else if (typeOfTemplate == 'DWP_Status_Check_Template__c') {
            List<Application__c> apps = [
			    SELECT
				    First_Name__c,
				    Second_Name__c,
				    Name
			    FROM Application__c
			    WHERE Id = :applicationId
		    ];
		    if(apps.isEmpty()) return;
		    Application__c currentApplication = apps[0];
            PageReference savepage;
            savepage = Page.statusCheck;
            savepage.getParameters().put('id', applicationId);
            blob pdfBlob;
            if (!Test.isRunningTest()) {
           	    pdfBlob = savepage.getContent();
            } else {
           	    pdfBlob = Blob.valueOf('Test');
            }
            String finalTitle = currentApplication.First_Name__c + '_' + currentApplication.Second_Name__c + '_' +
                                currentApplication.Name + '_' + FIELD_BODY_TO_FILE_NAME.get(typeOfTemplate);
            saveFile(pdfBlob, finalTitle);
        }  else if (typeOfTemplate == 'DWP_C2_Request_Template__c') {
            PageReference savepage ;
            savepage = Page.DWP_C2Request;
            savepage.getParameters().put('id', applicationId);
            savepage.getParameters().put('template', typeOfTemplate);
            blob pdfBlob;
            if (!Test.isRunningTest()) {
                pdfBlob = savepage.getContent();
            } else {
                pdfBlob = Blob.valueOf('Test');
            }
            String finalTitle = FIELD_BODY_TO_FILE_NAME.get(typeOfTemplate);
            saveFile(pdfBlob, finalTitle);
        } else {
            PageReference savepage ;
            savepage = Page.HRMCReply;
            savepage.getParameters().put('id', applicationId);
            savepage.getParameters().put('template', typeOfTemplate);
            blob pdfBlob;
            if (!Test.isRunningTest()) {
                pdfBlob = savepage.getContent();
            } else {
                pdfBlob = Blob.valueOf('Test');
            }
            String finalTitle = FIELD_BODY_TO_FILE_NAME.get(typeOfTemplate);
            saveFile(pdfBlob, finalTitle);
        }
    }

    private static void sendCertifiedProofMessage(Id appId, Id currDocId) {
        OrgWideEmailAddress[] owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :ORG_WIDE
        ];
        List<EmailTemplate> certifiedEmailTemplate = [
            SELECT
                Id
            FROM EmailTemplate
            WHERE Name = :CERTIFIED_TEMPLATE_NAME
        ];
        List<Application__c> apps = [
            SELECT
                Contact__c,
                Email__c
            FROM Application__c
            WHERE Id = :appId
        ];
        if (apps.isEmpty()) {
            return;
        }
        Application__c app = apps[0];
        if (app.Contact__c == null) {
            return;
        }
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setTargetObjectId(app.Contact__c);
        message.setUseSignature(false);
        message.setSaveAsActivity(true);
        message.setTreatTargetObjectAsRecipient(false);
        message.setWhatId(app.Id);
        if (certifiedEmailTemplate.isEmpty()) {
            return;
        }
        message.setTemplateID(certifiedEmailTemplate[0].Id);
        if ( owea.size() > 0 ) {
            message.setOrgWideEmailAddressId(owea.get(0).Id);
        }
        Id[] contDocIds = new List<Id> {currDocId};
        message.setEntityAttachments(contDocIds);
        message.toAddresses = new String[] { app.Email__c };
        Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
        Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
    }

    private void saveFile(Blob pdfBlob, String title) {
        List<ContentDocumentLink> currentDoc = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE ContentDocument.Title = :title AND
                  LinkedEntityId = :applicationId
        ];

        if (!currentDoc.isEmpty()) {
            ContentVersion conVer = new ContentVersion();
            conVer.ContentDocumentId = currentDoc[0].ContentDocumentId;
            conVer.VersionData = pdfBlob;
            conVer.ContentLocation = 'S';
            conVer.PathOnClient = title +'.pdf';
            conVer.Title = title;
            conVer.VersionData = pdfBlob;
            insert conVer;
            return;
        }

        ContentVersion conVer = new ContentVersion();
        conVer.ContentLocation = 'S';
        conVer.PathOnClient = title+'.pdf';
        conVer.Title = title;
        conVer.VersionData = pdfBlob;
        insert conVer;

        ContentVersion conDoc = [SELECT ContentDocumentId, ContentSize FROM ContentVersion WHERE Id =:conVer.Id][0];

        ContentDocumentLink conDocLink = new ContentDocumentLink();
        conDocLink.LinkedEntityId = applicationId;
        conDocLink.ContentDocumentId = conDoc.ContentDocumentId;
        conDocLink.shareType = 'V';
        conDocLink.Visibility = 'AllUsers';
        insert conDocLink;
        if (typeOfTemplate == 'Certified_Doc_Template__c') {
            sendCertifiedProofMessage(applicationId, conDoc.Id);
        }
    }
}