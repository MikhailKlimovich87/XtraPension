public class HMRCRepliesDocsGenerator implements Queueable, Database.AllowsCallouts {
    public String applicationId;
    public String typeOfTemplate;
    public final Map<String, String> FIELD_BODY_TO_FILE_NAME = new Map<String, String> {
        'NINO_Template__c'                           => 'NINO reply',
        'Custom_Reply_Template__c'                   => 'CUSTOM reply',
        'Appeal_Template__c'                         => 'APPEAL reply',
        'Current_Job_Reply_Template__c'              => 'CURRENT JOB reply',
        'DWP_Status_Check_Template__c'               => 'DWPStatusCheck',
        'Certified_Doc_Template__c'                  => 'CerifiedDoc',
        'EU_Residency_Appeal_Template__c'            => 'EU Residency Appeal',
        'Maiden_Name_Template__c'                    => 'Maiden Name',
        'DWP_C2_Request_Template__c'                 => 'DWP_C2_Request',
        'Bounce_Letter_Template__c'                  => 'Bounce Letter',
        'Update_Letter_Template__c'                  => '64-8 Update Letter',
        'EU_Residency_Letter_Template__c'            => 'EU_Residency_Letter',
        'Class_3_Appeal_Despite_3_Years_Template__c' => 'Class_3_Appeal_Despite_3_Years',
        'Bad_Error_In_C2_Decision_Template__c'       => 'Bad_Error_In_C2_Decision',
        'No_Shortfall_Table_Provided_Template__c'    => 'No_Shortfall_Table_Provided',
        'Custom_Carnage_Template__c'                 => 'Custom_Carnage',
        'Missing_Correspondence_Template__c'         => 'Missing_Correspondence',
        'CF83_NOT_Received_letter_again_Template__c' => 'CF83_NOT_Received_letter_again',
        'Late_Payment_Appeal_Template__c'            => 'Late_Payment_Appeal',
        'Reply_to_EU_C2_C3_Rejection_Template__c'    => 'Reply_to_EU_C2_C3_Rejection',
        'Higher_Level_Appeal_Template__c'            => 'Higher_Level_Stage2_Appeal_Statutory_Review'
    };

    private final static String ORG_WIDE = 'clients@xtrapension.com';
    private final static String CERTIFIED_TEMPLATE_NAME = 'Certified Proof';

    public HMRCRepliesDocsGenerator(String recordId, String templateName) {
        applicationId  = recordId;
        typeOfTemplate = templateName;
    }

    public void execute(QueueableContext context) {
        List<Application__c> apps = [
		    SELECT
                Id,
                First_Name__c,
                Second_Name__c,
                Name
		    FROM Application__c
		    WHERE Id = :applicationId
		];
		if(apps.isEmpty()) return;
		Application__c currentApplication = apps[0];
        if (typeOfTemplate == 'Certified_Doc_Template__c') {
            PageReference savepage = Page.CertifiedProof;
            savepage.getParameters().put('id', applicationId);
            blob pdfBlob;
            if (!Test.isRunningTest()) {
           	    pdfBlob = savepage.getContent();
            } else {
           	    pdfBlob = Blob.valueOf('Test');
            }
            String finalTitle = currentApplication.First_Name__c + '_' + currentApplication.Second_Name__c + '_' +
                                currentApplication.Name + '_' + FIELD_BODY_TO_FILE_NAME.get(typeOfTemplate) + '_REPLY';

            saveFile(pdfBlob, finalTitle);
        } else if (typeOfTemplate == 'DWP_Status_Check_Template__c') {
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
                                currentApplication.Name + '_' + FIELD_BODY_TO_FILE_NAME.get(typeOfTemplate) + '_REPLY';
            saveFile(pdfBlob, finalTitle);
        }  else if (typeOfTemplate == 'DWP_C2_Request_Template__c' || typeOfTemplate == 'Higher_Level_Appeal_Template__c') {
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
            String finalTitle = currentApplication.First_Name__c + '_' + currentApplication.Second_Name__c + '_' +
                                currentApplication.Name + '_' +  + FIELD_BODY_TO_FILE_NAME.get(typeOfTemplate) + '_REPLY';
            saveFile(pdfBlob, finalTitle);
        } else if (typeOfTemplate == 'Bounce_Letter_Template__c') {
            PageReference savepage ;
            savepage = Page.BounceLetter;
            savepage.getParameters().put('id', currentApplication.Id);
            blob pdfBlob;
            if (!Test.isRunningTest()) {
                pdfBlob = savepage.getContent();
            } else {
                pdfBlob = Blob.valueOf('Test');
            }
            String finalTitle = currentApplication.First_Name__c + '_' + currentApplication.Second_Name__c + '_' +
                                currentApplication.Name + '_' +  + FIELD_BODY_TO_FILE_NAME.get(typeOfTemplate) + '_REPLY';
            saveFile(pdfBlob, finalTitle);
        } else if (typeOfTemplate == 'Update_Letter_Template__c') {
            PageReference savepage ;
            savepage = Page.UpdateLetter;
            savepage.getParameters().put('id', currentApplication.Id);
            blob pdfBlob;
            if (!Test.isRunningTest()) {
                pdfBlob = savepage.getContent();
            } else {
                pdfBlob = Blob.valueOf('Test');
            }
            String finalTitle = currentApplication.First_Name__c + '_' + currentApplication.Second_Name__c + '_' +
                                currentApplication.Name + '_' +  + FIELD_BODY_TO_FILE_NAME.get(typeOfTemplate) + '_REPLY';
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
            String finalTitle = currentApplication.First_Name__c + '_' + currentApplication.Second_Name__c + '_' +
                                currentApplication.Name + '_' +  + FIELD_BODY_TO_FILE_NAME.get(typeOfTemplate) + '_REPLY';
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