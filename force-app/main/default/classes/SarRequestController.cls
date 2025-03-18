public class SarRequestController {
    private static final EmailTemplate SAR_REQUEST_TEMPLATE {
        get {
            if (SAR_REQUEST_TEMPLATE == null) {
                List<EmailTemplate> emailTemplates = [
                    SELECT Id, HtmlValue
                    FROM EmailTemplate
                    WHERE Name = 'SAR Request'
                    WITH USER_MODE
                    LIMIT 1
                ];
                if (!emailTemplates.isEmpty()) {
                    SAR_REQUEST_TEMPLATE = emailTemplates[0];
                }
            }
        return SAR_REQUEST_TEMPLATE;
    }
        private set;
    }

    private static final OrgWideEmailAddress OWD {
        get {
            if (OWD == null) {
                List<OrgWideEmailAddress> orgWideEmailAddresses = [
                    SELECT Id
                    FROM OrgWideEmailAddress
                    WHERE Address = 'clients@xtrapension.com'
                    WITH USER_MODE
                    LIMIT 1
                ];
                if (!orgWideEmailAddresses.isEmpty()) {
                    OWD = orgWideEmailAddresses[0];
                }
            }
            return OWD;
        }
        private set;
    }

	@AuraEnabled
    public static String sendSAREmail(String appId) {
        if (appId == null) throw new SarRequestException('Application Id is null');
		List<Application__c> apps = [
			SELECT
				First_Name__c,
				Second_Name__c,
				Contact__c,
				Email__c,
				Name
			FROM Application__c
			WHERE Id = :appId
		];
		if(apps.isEmpty()) throw new SarRequestException('Couldn\'t find app with this record Id');
		Application__c currentApplication = apps[0];
		PageReference savepage;
        savepage = Page.SarRequest;
        savepage.getParameters().put('id', appId);
        blob pdfBlob;
        if (!Test.isRunningTest()) {
           	pdfBlob = savepage.getContent();
        } else {
           	pdfBlob = Blob.valueOf('Test');
        }
        String finalTitle = currentApplication.First_Name__c + '_' + currentApplication.Second_Name__c + '_' +
                            currentApplication.Name + '_SarRequest';

        ContentVersion conVer = new ContentVersion();
		conVer.ContentLocation = 'S';
		conVer.PathOnClient = finalTitle+'.pdf';
		conVer.Title = finalTitle;
		conVer.VersionData = pdfBlob;
		insert conVer;

		ContentVersion conDoc = [SELECT ContentDocumentId, ContentSize FROM ContentVersion WHERE Id =:conVer.Id][0];

		ContentDocumentLink conDocLink = new ContentDocumentLink();
		conDocLink.LinkedEntityId = currentApplication.Id;
		conDocLink.ContentDocumentId = conDoc.ContentDocumentId;
		conDocLink.shareType = 'V';
		conDocLink.Visibility = 'AllUsers';
		insert conDocLink;


		Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setTargetObjectId(currentApplication.Contact__c);
        message.setUseSignature(false);
        message.setBccSender(false);
        message.setSaveAsActivity(true);
		if (SAR_REQUEST_TEMPLATE != null) {
            message.setTemplateID(SAR_REQUEST_TEMPLATE.Id);
        }
        if (OWD != null) {
            message.setOrgWideEmailAddressId(OWD.Id);
        }
        message.setWhatId(currentApplication.Id);
        message.toAddresses = new String[] {currentApplication.Email__c};
		message.setTreatTargetObjectAsRecipient(false);

        Id[] contDocIds = new List<Id> {conVer.Id};
        message.setEntityAttachments(contDocIds);
        Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
        Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
		Boolean isSuccess = true;
		for (Messaging.SendEmailResult result : results) {
			if (result.isSuccess() == false) {
				isSuccess = false;
				break;
			}
		}
        return String.valueOf(isSuccess);
    }

    public class SarRequestException extends Exception {}
}