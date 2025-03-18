public with sharing class ApplicationPdf {
    public String MstrId{get;set;}
    public Application__c appObj{get;set;}
    public Employer__c empUKObj{get;set;}
    public Employer__c selfEmpUKObj{get;set;}
    public Employer__c empAfterUKObj{get;set;}
    public String PDFNo{get;set;}
    public String EFNo{get;set;}
    public boolean show{get;set;}
    public boolean showpdf{get;set;}
    public ApexPages.PageReference page2{get;set;}
    public String baseURL{get;set;}

    public PageReference Cancel()
    {
        PageReference Pdf = new PageReference('/'+MstrID);
        pdf.setredirect(True);
        return Pdf;
    }

    public ApplicationPdf(ApexPages.StandardController Controller){
        baseURL = URL.getSalesforceBaseUrl().toExternalForm();
        MstrId = ApexPages.currentPage().getParameters().get('id');
        appObj = [Select Id, Name, Type_Of_Employment__c, Salutation__c, First_Name__c, Second_Name__c, Date_Of_Birth__c, Last_UK_Home_Address__c, Last_UK_Home_Address__Street__s, Last_UK_Home_Address__City__s, Last_UK_Home_Address__CountryCode__s, Last_UK_Home_Address__StateCode__s, Last_UK_Home_Address__PostalCode__s, Are_You_Single__c,  Date_Of_Marriage_Or_Civil_Partnership__c,  Date_Of_Leaving_Last_UK__c, Did_You_Change_Name__c, Full_Maiden_Previous_Name__c, Are_You_Divorced__c, Divorce_Date__c, National_Insurance_Number__c, Current_Address_Abroad__c, Current_Address_Abroad__Street__s, Current_Address_Abroad__City__s, Current_Address_Abroad__StateCode__s, Current_Address_Abroad__CountryCode__s, Current_Address_Abroad__PostalCode__s
                      From Application__c Where Id =: MstrId ];
		empUKObj = [SELECT Employers_Address__Street__s, Employers_Address__City__s, Employers_Address__CountryCode__s, Employers_Address__StateCode__s, Employers_Address__PostalCode__s FROM Employer__c WHERE Application__c =: MstrId AND Type__c = 'UK Work' ORDER BY Start_Date__c DESC][0];
		// selfEmpUKObj = [SELECT End_Date__c FROM Employer__c WHERE Application__c =: MstrId AND Type__c = 'UK Work' AND Self_employed__c = true ORDER BY Start_Date__c DESC][0];
		empAfterUKObj = [SELECT Employer_Name__c, Start_Date__c, Employers_Address__Street__s, Employers_Address__City__s, Employers_Address__CountryCode__s, Employers_Address__StateCode__s, Employers_Address__PostalCode__s FROM Employer__c WHERE Application__c =: MstrId AND Type__c = 'Work After UK' ORDER BY Start_Date__c DESC][0];
    }

    public PageReference pdfAction()
    {
        PageReference savepage ;
        savepage = Page.ApplyCF83;
        savepage.getParameters().put('id',MstrID);
        system.debug('id:- '+MstrID);
        blob pdfBlob;
        if (!Test.isRunningTest()) {
            pdfBlob = savepage.getContent();
        } else {
            pdfBlob = Blob.valueOf('Test');
        }
        List<ContentDocumentLink> notesattch = [select id, ContentDocument.Title,LinkedEntityId from ContentDocumentLink where LinkedEntityId =: MstrID order by ContentDocument.Title asc];
        system.debug('notesattch## ' + notesattch);
        if(notesattch.size() > 0)
        {
            string title =  notesattch[0].ContentDocument.Title;
            system.debug('title111 ' + title);
            List<String> titleSplit = title.split('R');
            String FinalTitle = 'ApplyCF'+notesattch.size()+'_ForSignature';
            system.debug('FinalTitle22 ' + FinalTitle);
            PDFNo=FinalTitle;

            ContentVersion conVer = new ContentVersion();
            conVer.ContentLocation = 'S';
            conVer.PathOnClient = FinalTitle+'.pdf';
            conVer.Title = FinalTitle;
            conVer.VersionData = pdfBlob;
            system.debug('conVer@@ ' + conVer);
            insert conVer;

            Id conDoc = [SELECT ContentDocumentId FROM ContentVersion WHERE Id =:conVer.Id].ContentDocumentId;

            ContentDocumentLink conDocLink = New ContentDocumentLink();
            conDocLink.LinkedEntityId = MstrID;
            conDocLink.ContentDocumentId = conDoc;
            conDocLink.shareType = 'V';
            insert conDocLink;
            update appObj;

             PageReference pageRef = new PageReference( baseURL+'/lightning/r/Application__c/' + System.currentPageReference().getParameters().get('id')+'/view');
            pageRef.setRedirect(true);
            return pageRef;

        }


         else{return null;}



    }

}