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
        		Id,
        		Name,
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
        		Include_UK_Address1__c,
        		Include_UK_Address2__c,
        		Include_UK_Address3__c,
        		Include_UK_Address4__c,
        		Include_UK_Address5__c,
        		Freeform_Text_Line1__c,
        		Freeform_Text_Line2__c,
        		Freeform_Text_Line3__c,
        		Freeform_Text_Line4__c,
        		Freeform_Text_Line5__c,
				Freeform_RichText_Line1__c,
				Freeform_RichText_Line2__c,
				Freeform_RichText_Line3__c,
				Freeform_RichText_Line4__c,
				Freeform_RichText_Line5__c,
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
                Abroad_Employer_Name1__c,
                Abroad_Employer_Start_Date1__c,
                Abroad_Employer_End_Date1__c,
                Abroad_Employer_Address1__City__s,
                Abroad_Employer_Address1__CountryCode__s,
                Abroad_Employer_Address1__StateCode__s,
                Abroad_Employer_Address1__Street__s,
                Abroad_Employer_Address1__PostalCode__s,
        		Abroad_Employer_Address1_Country__c,
        		Abroad_Employer_Address1_State__c,
                Career_Break_Employer_Name1__c,
                Career_Break_Employer_Start_Date1__c,
                Career_Break_Employer_End_Date1__c,
                Career_Break_Employer_Address1__City__s,
                Career_Break_Employer_Address1__CountryCode__s,
                Career_Break_Employer_Address1__StateCode__s,
                Career_Break_Employer_Address1__Street__s,
                Career_Break_Employer_Address1__PostalCode__s,
        		Career_Break_Employer_Address1_Country__c,
        		Career_Break_Employer_Address1_State__c,
                Include_Abroad_Employer1__c,
                Include_Abroad_Employer2__c,
                Include_Abroad_Employer3__c,
                Include_Abroad_Employer4__c,
                Include_Abroad_Employer5__c,
                Include_Career_Break_Employer1__c,
                Include_Career_Break_Employer2__c,
                Include_Career_Break_Employer3__c,
                Include_Career_Break_Employer4__c,
                Include_Career_Break_Employer5__c,
				DWP_Callback_Request__c,
       			Agent__r.Agent_ID__c,
        		Is_Know_National_Insurance_Number__c,
        		Custom_Letter_Date__c
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
      		ORDER BY Start_Date__c DESC
		];
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
        blob pdfBlob;
        if (!Test.isRunningTest()) {
            pdfBlob = savepage.getContent();
        } else {
            pdfBlob = Blob.valueOf('Test');
        }

    	String FinalTitle = appObj.First_Name__c + '_' + appObj.Second_Name__c + '_' + appObj.Name +'_CustomLetter_ForSignature';

    	ContentVersion conVer = new ContentVersion();
    	conVer.ContentLocation = 'S';
    	conVer.PathOnClient = FinalTitle+'.pdf';
    	conVer.Title = FinalTitle;
    	conVer.VersionData = pdfBlob;
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
	    return pageRef;
    }
}