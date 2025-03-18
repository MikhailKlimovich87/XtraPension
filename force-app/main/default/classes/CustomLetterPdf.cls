public class CustomLetterPdf {
    public String MstrId{get;set;}
    public Application__c appObj{get;set;}
    public Employer__c empUKObj{get;set;}
    public List<Employer__c> empAfterUKObjList{get;set;}
    public String baseURL{get;set;}

    public CustomLetterPdf(ApexPages.StandardController Controller){
        baseURL = URL.getSalesforceBaseUrl().toExternalForm();
        MstrId = ApexPages.currentPage().getParameters().get('id');
        appObj = [
			SELECT
				Salutation__c,
				First_Name__c,
				Second_Name__c,
				Tel__c,
				Email__c
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
		// selfEmpUKObj = [SELECT End_Date__c FROM Employer__c WHERE Application__c =: MstrId AND Type__c = 'UK Work' AND Self_employed__c = true ORDER BY Start_Date__c DESC][0];
		List<Employer__c> afterUKEmployers = [
			SELECT
				Employer_Name__c,
				Start_Date__c,
				End_Date__c,
				Employers_Address__Street__s,
				Employers_Address__City__s,
				toLabel(Employers_Address__CountryCode__s),
				toLabel(Employers_Address__StateCode__s),
				Employers_Address__PostalCode__s,
				Add_to_custom_letter__c,
				Employers_Address_Country__c,
				Type_Of_After_UK_Employment__c,
				Current_Work__c
			FROM Employer__c
			WHERE Application__c =: MstrId
				AND Type__c = 'Work After UK'
				AND Add_to_custom_letter__c = true
			ORDER BY Start_Date__c ASC
		];
		empAfterUKObjList = afterUKEmployers.size() == 0 ? null : afterUKEmployers;
		if (appObj.Type_Of_Employment__c == 'Not employed') {
			empAfterUKObjList = null;
			empUKObj = null;
		}
    }

    public PageReference pdfAction() {
        PageReference savepage ;
        savepage = Page.CustomLetter;
        savepage.getParameters().put('id',MstrID);
        system.debug('id:- '+MstrID);
        blob pdfBlob;
        if (!Test.isRunningTest()) {
            pdfBlob = savepage.getContent();
        } else {
            pdfBlob = Blob.valueOf('Test');
        }

		String FinalTitle = appObj.First_Name__c + '_' + appObj.Second_Name__c + '_' + appObj.Name +'_CustomLetter_ForSignature';
		system.debug('FinalTitle22 ' + FinalTitle);

		ContentVersion conVer = new ContentVersion();
		conVer.ContentLocation = 'S';
		conVer.PathOnClient = FinalTitle+'.pdf';
		conVer.Title = FinalTitle;
		conVer.VersionData = pdfBlob;
		system.debug('conVer@@ ' + conVer);
		insert conVer;

		ContentVersion conDoc = [SELECT ContentDocumentId, ContentSize FROM ContentVersion WHERE Id =:conVer.Id][0];

		ContentDocumentLink conDocLink = New ContentDocumentLink();
		conDocLink.LinkedEntityId = MstrID;
		conDocLink.ContentDocumentId = conDoc.ContentDocumentId;
		conDocLink.shareType = 'V';
		conDocLink.Visibility = 'AllUsers';
		insert conDocLink;
		update appObj;

		Application_Document__c appDoc = new Application_Document__c(
			Type__c = 'Custom Letter',
			Application__c = MstrID,
			File_Name__c = FinalTitle,
			File_Size__c = conDoc.ContentSize,
			Status__c = 'New'
			);
		insert appDoc;
		insert new ContentDocumentLink(
            ContentDocumentId = conDoc.ContentDocumentId,
            LinkedEntityId    = appDoc.Id,
            ShareType         = 'V',
			Visibility        = 'AllUsers'
        );

		PageReference pageRef = new PageReference( baseURL+'/lightning/r/Application__c/' + System.currentPageReference().getParameters().get('id')+'/view');
		pageRef.setRedirect(true);
		System.debug('FINISHED');
		return pageRef;
    }
}