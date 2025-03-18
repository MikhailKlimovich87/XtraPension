public with sharing class ApplicationAgentPdf {
    public String MstrId{get;set;}
    public Application__c appObj{get;set;}
    
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
    
    public ApplicationAgentPdf(ApexPages.StandardController Controller){
        baseURL = URL.getSalesforceBaseUrl().toExternalForm();
        MstrId = ApexPages.currentPage().getParameters().get('id');
        appObj = [Select Id, Name, First_Name__c, Second_Name__c From Application__c Where Id =: MstrId ];
        
    }   
    
    public PageReference pdfAction()
    {
        PageReference savepage ;
        savepage = Page.Agent64_8;
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
            String FinalTitle = 'PO'+notesattch.size();
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