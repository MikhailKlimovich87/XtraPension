public class CustomSummerPdf {
	ApexPages.StandardController stdController = null;
    public String baseURL{get;set;}
    public String MstrId{get;set;}
    public Application__c appObj{get;set;}
    public Employer__c empUKObj{get;set;}
    public List<Employer__c> empAfterUKObjList{get;set;}
	public List<AfterUkEmployerWrapper> empAfterUKWrapperList {get;set;}
	public List<UKAddress> previousUKAdresses {get;set;}
	public static final String SEND_CLIENT_SUMMER_EMAIL_ADDRESS = 'xtrapension@gmail.com';
	public static final String CLIENT_SUMMARY_LIBRARY_NAME = 'Client Summary';


	public PageReference save() {       
        System.debug('==== TestExtension: save() ====');
		generateClientSummary(MstrId);
        // do some stuff
        Pagereference ref = stdController.save();
        // some more stuff
        // give control back to standard controller
        return ref;
    }
    public CustomSummerPdf(ApexPages.StandardController Controller) {
        baseURL = URL.getSalesforceBaseUrl().toExternalForm();
        MstrId = ApexPages.currentPage().getParameters().get('id');
        appObj = [
			SELECT
				Id,
				Name,
				Age__c,
				Type_Of_Employment__c,
				Salutation__c,
				First_Name__c,
				Second_Name__c,
				Date_Of_Birth__c,
				Last_UK_Home_Address__c,
				Last_UK_Home_Address__Street__s,
				Last_UK_Home_Address__City__s,
				Last_UK_Home_Address__CountryCode__s,
				Last_UK_Home_Address__StateCode__s,
				Last_UK_Home_Address__PostalCode__s,
				Last_UK_Home_Address_Country__c,
				Last_UK_Home_Address_State__c,
				Are_You_Single__c,
				Date_Of_Marriage_Or_Civil_Partnership__c,
				Date_Of_Leaving_Last_UK__c,
				Did_You_Change_Name__c,
				Full_Maiden_Previous_Name__c,
				Are_You_Divorced__c,
				Divorce_Date__c,
				National_Insurance_Number__c,
				Current_Address_Abroad__c,
				Current_Address_Abroad__Street__s,
				Current_Address_Abroad__City__s,
				Current_Address_Abroad__StateCode__s,
				Current_Address_Abroad__CountryCode__s,
				Current_Address_Abroad__PostalCode__s,
				Current_Address_Abroad_Country__c,
				Current_Address_Abroad_State__c,
				Previous_UK_Address_1__Street__s,
				Previous_UK_Address_2__Street__s,
				Previous_UK_Address_3__Street__s,
				Previous_UK_Address_4__Street__s,
				Previous_UK_Address_5__Street__s,
				Previous_UK_Address_1__City__s,
				Previous_UK_Address_2__City__s,
				Previous_UK_Address_3__City__s,
				Previous_UK_Address_4__City__s,
				Previous_UK_Address_5__City__s,
				Previous_UK_Address_1__StateCode__s,
				Previous_UK_Address_2__StateCode__s,
				Previous_UK_Address_3__StateCode__s,
				Previous_UK_Address_4__StateCode__s,
				Previous_UK_Address_5__StateCode__s,
				Previous_UK_Address_1__CountryCode__s,
				Previous_UK_Address_2__CountryCode__s,
				Previous_UK_Address_3__CountryCode__s,
				Previous_UK_Address_4__CountryCode__s,
				Previous_UK_Address_5__CountryCode__s,
				Previous_UK_Address_1__PostalCode__s,
				Previous_UK_Address_2__PostalCode__s,
				Previous_UK_Address_3__PostalCode__s,
				Previous_UK_Address_4__PostalCode__s,
				Previous_UK_Address_5__PostalCode__s,
				Previous_UK_Address_1_Country__c,
				Previous_UK_Address_2_Country__c,
				Previous_UK_Address_3_Country__c,
				Previous_UK_Address_4_Country__c,
				Previous_UK_Address_5_Country__c,
				Previous_UK_Address1_State__c,
				Previous_UK_Address2_State__c,
				Previous_UK_Address3_State__c,
				Previous_UK_Address4_State__c,
				Previous_UK_Address5_State__c,
				Previous_UK_Address_End_Date_1__c,
				Previous_UK_Address_End_Date_2__c,
				Previous_UK_Address_End_Date_3__c,
				Previous_UK_Address_Start_Date_1__c,
				Previous_UK_Address_Start_Date_2__c,
				Previous_UK_Address_Start_Date_3__c,
				Docusigned_Date__c,
				Agent_ID__c,
				Last_UK_Employer_Name__c,
                Last_UK_Employer_Start_Date__c,
                Last_UK_Employer_End_Date__c,
                Last_UK_Employer_Address__City__s,
                Last_UK_Employer_Address__CountryCode__s,
                Last_UK_Employer_Address__StateCode__s,
                Last_UK_Employer_Address__Street__s,
                Last_UK_Employer_Address__PostalCode__s,
				Last_UK_Employer_Address_Country__c,
				Last_UK_Employer_Address_State__c,
                Form_Complete_Date__c,
                CreatedDate,
                Current_Occupation__c,
                Related_Contact_Phone__c,
                Email__c,
				Years_Of_Work_In_The_UK__c,
				Package_Name__c
            FROM Application__c
			WHERE Id =: MstrId
		];
		List<Employer__c> lastUkEmployer= [
			SELECT
				Employers_Address__Street__s,
				Employers_Address__City__s,
				Employers_Address__CountryCode__s,
				Employers_Address__StateCode__s,
				Employers_Address__PostalCode__s,
				Start_Date__c,
				End_Date__c,
				Employer_Name__c,
				Employers_Address_Country__c,
				Type_Of_UK_Employment__c
			FROM Employer__c
			WHERE Application__c =: MstrId
				AND Type__c = 'UK Work'
			ORDER BY Start_Date__c DESC];
		empUKObj = lastUkEmployer.size() != 0 ? lastUkEmployer[0] : null;
		List<Employer__c> afterUKEmployers = [
			SELECT
				Employer_Name__c,
				Start_Date__c,
				End_Date__c,
				Employers_Address__Street__s,
				Employers_Address__City__s,
				Employers_Address__CountryCode__s,
				Employers_Address__StateCode__s,
				Employers_Address__PostalCode__s,
				Add_to_custom_letter__c,
				Employers_Address_Country__c,
				Type_Of_After_UK_Employment__c
			FROM Employer__c
			WHERE Application__c =: MstrId
				AND Type__c = 'Work After UK'
			ORDER BY Start_Date__c ASC
		];
		empAfterUKObjList = afterUKEmployers.size() == 0 ? null : afterUKEmployers;
		if (afterUKEmployers.size() != 0) {
			empAfterUKWrapperList = new List<AfterUkEmployerWrapper>();
			for (Integer i = 0; i < afterUKEmployers.size(); i++) {
				if (Math.mod(i, 2) == 0 || i == 0) {
					AfterUkEmployerWrapper employerWrapper = new AfterUkEmployerWrapper();
					employerWrapper.firstEmployerInLine = afterUKEmployers[i];
					if (i+1 < afterUKEmployers.size()) {
						employerWrapper.secondEmployerInLine = afterUKEmployers[i + 1];
					}
					empAfterUKWrapperList.add(employerWrapper);
				}
			}
		}
		previousUKAdresses = new List<UKAddress>();
		for (Integer i = 1; i <= 3; i++) {
			if ((String)appObj.get('Previous_UK_Address_' + i + '__Street__s') != null) {
				String addressInfo = (String)appObj.get('Previous_UK_Address_' + i + '__Street__s');
				addressInfo += (String)appObj.get('Previous_UK_Address_' + i + '__City__s') != null ?
							   		(' ' + (String)appObj.get('Previous_UK_Address_' + i + '__City__s')) :
									'';
				UKAddress addressItem = new UKAddress();
				addressItem.addressData = addressInfo;
				addressItem.startDate   = (Date)appObj.get('Previous_UK_Address_Start_Date_' + i + '__c');
				addressItem.endDate     = (Date)appObj.get('Previous_UK_Address_End_Date_' + i + '__c');
				addressItem.postcode    = (String)appObj.get('Previous_UK_Address_' + i + '__PostalCode__s');
				previousUKAdresses.add(addressItem);
			}
		}
    }
	public class AfterUkEmployerWrapper {
		public Employer__c firstEmployerInLine {get;set;}
		public Employer__c secondEmployerInLine {get;set;}
	}
	public class UKAddress {
		public Date startDate {get;set;}
		public Date endDate {get;set;}
		public String postcode {get;set;}
		public String addressData {get;set;}
	}

	@future(callout = true)
	public static void generateClientSummary(Id applicationId) {
		List<Application__c> applications =	[
			SELECT
				Id,
				Name,
				Contact__c,
				First_Name__c,
				Second_Name__c,
				Age__c,
				Current_Address_Abroad_Country__c,
				Years_Of_Work_In_The_UK__c,
				Package_Name__c,
				Is_Generate_Client_Summary_PDF__c
         	FROM Application__c
			WHERE Id =: applicationId
		];
		if (applications.isEmpty()) {
			return;
		}
		Application__c currentApplication = applications[0];
		Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setTargetObjectId(currentApplication.Contact__c);
        message.setSenderDisplayName('XtraPension');
        message.setUseSignature(false);
        message.setBccSender(false);
        message.setSaveAsActivity(true);
		message.setHtmlBody('<div></div>');
        message.setWhatId(currentApplication.Id);
        message.setSubject(currentApplication.First_Name__c + ' ' + currentApplication.Second_Name__c +
                           ', ' + currentApplication.Age__c + ', ' + currentApplication.Current_Address_Abroad_Country__c +
                           ', ' + currentApplication.Years_Of_Work_In_The_UK__c + ' years - ' + currentApplication.Package_Name__c);
        message.toAddresses = new String[] {SEND_CLIENT_SUMMER_EMAIL_ADDRESS};
		message.setTreatTargetObjectAsRecipient(false);
        PageReference savepage ;
        savepage = Page.ClientSummary;
        savepage.getParameters().put('id', currentApplication.Id);
        blob pdfBlob;
        if (!Test.isRunningTest()) {
            pdfBlob = savepage.getContent();
        } else {
            pdfBlob = Blob.valueOf('Test');
        }
        String finalTitle = currentApplication.First_Name__c + '_' + currentApplication.Second_Name__c + '_' +
                            currentApplication.Name + '_ClientSummary';

        ContentVersion conVer = new ContentVersion();
		conVer.ContentLocation = 'S';
		conVer.PathOnClient = finalTitle+'.pdf';
		conVer.Title = finalTitle;
		conVer.VersionData = pdfBlob;
		insert conVer;

		ContentVersion conDoc = [SELECT ContentDocumentId, ContentSize FROM ContentVersion WHERE Id =:conVer.Id][0];

		List<ContentDocumentLink> newLinks = new List<ContentDocumentLink>();
		ContentDocumentLink conDocLink = new ContentDocumentLink();
		conDocLink.LinkedEntityId = currentApplication.Id;
		conDocLink.ContentDocumentId = conDoc.ContentDocumentId;
		conDocLink.shareType = 'V';
		conDocLink.Visibility = 'AllUsers';
		newLinks.add(conDocLink);

		ContentWorkspace ws = [
			SELECT
				Id
			FROM ContentWorkspace
			WHERE Name = :CLIENT_SUMMARY_LIBRARY_NAME
			LIMIT 1
		];
		if (ws != null) {
			ContentDocumentLink libraryLink = new ContentDocumentLink();
			libraryLink.LinkedEntityId = ws.Id;
			libraryLink.ContentDocumentId = conDoc.ContentDocumentId;
			libraryLink.shareType = 'I';
			libraryLink.Visibility = 'AllUsers';
			newLinks.add(libraryLink);
		}
		insert newLinks;
		currentApplication.Is_Generate_Client_Summary_PDF__c = true;
		update currentApplication;
        Id[] contDocIds = new List<Id> {conDoc.Id};
        message.setEntityAttachments(contDocIds);
        Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
        Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
	}
}