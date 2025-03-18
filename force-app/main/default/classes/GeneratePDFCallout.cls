public class GeneratePDFCallout implements Queueable, Database.AllowsCallouts {
    public String applicationId;
    public Application__c app;
    public static final String FILL_FROM_URL = XtraPension_Data__c.getInstance().Fill_Pdf_File_Link__c;

    public GeneratePDFCallout (String recordId) {
        this.applicationId = recordId;
        this.app = [
            SELECT
                Id,
                Name,
                Salutation__c,
                First_Name__c,
                Second_Name__c,
                Date_Of_Birth__c,
                National_Insurance_Number__c,
                Work_Or_Pay_UK_National_Insurance__c,
                Private_UK_Pension__c,
                Approx_Value_Of_UK_Pension__c,
                Current_Occupation__c,
                Current_Address_Abroad__City__s,
                Current_Address_Abroad__Street__s,
                Current_Address_Abroad__StateCode__s,
                Current_Address_Abroad__CountryCode__s,
                Current_Address_Abroad__PostalCode__s,
                Last_UK_Home_Address__City__s,
                Last_UK_Home_Address__CountryCode__s,
                Last_UK_Home_Address__Street__s,
                Last_UK_Home_Address__StateCode__s,
                Last_UK_Home_Address__PostalCode__s,
                Previous_UK_Address_1__City__s,
                Pay_By__c,
                //Previous_UK_Address_1__CountryCode__s,
                Previous_UK_Address_1__PostalCode__s,
                Previous_UK_Address_1__StateCode__s,
                Previous_UK_Address_1__Street__s,
                Previous_UK_Address_2__City__s,
                Previous_UK_Address_2__CountryCode__s,
                Previous_UK_Address_2__PostalCode__s,
                Previous_UK_Address_2__StateCode__s,
                Previous_UK_Address_2__Street__s,
                Previous_UK_Address_3__City__s,
                Previous_UK_Address_3__CountryCode__s,
                Previous_UK_Address_3__PostalCode__s,
                Previous_UK_Address_3__StateCode__s,
                Previous_UK_Address_3__Street__s,
                Previous_UK_Address_4__City__s,
                Previous_UK_Address_4__CountryCode__s,
                Previous_UK_Address_4__PostalCode__s,
                Previous_UK_Address_4__StateCode__s,
                Previous_UK_Address_4__Street__s,
                Previous_UK_Address_5__City__s,
                Previous_UK_Address_5__CountryCode__s,
                Previous_UK_Address_5__PostalCode__s,
                Previous_UK_Address_5__StateCode__s,
                Previous_UK_Address_5__Street__s,
                Did_You_Change_Name__c,
                Date_Of_Marriage_Or_Civil_Partnership__c,
                Are_You_Divorced__c,
                Full_Maiden_Previous_Name__c,
                Are_You_Single__c,
                Type_Of_Employment__c,
                Date_Of_Leaving_Last_UK__c,
                Divorce_Date__c,
                Years_Of_Work_In_The_UK__c,
                Status__c,
                Tel__c,
                Agent__c,
                Abroad_Employer_Name1__c,
                Abroad_Employer_Start_Date1__c,
                Abroad_Employer_End_Date1__c,
                Abroad_Employer_Address1__City__s,
                Abroad_Employer_Address1__CountryCode__s,
                Abroad_Employer_Address1__StateCode__s,
                Abroad_Employer_Address1__Street__s,
                Abroad_Employer_Address1__PostalCode__s,
                Career_Break_Employer_Name1__c,
                Career_Break_Employer_Start_Date1__c,
                Career_Break_Employer_End_Date1__c,
                Career_Break_Employer_Address1__City__s,
                Career_Break_Employer_Address1__CountryCode__s,
                Career_Break_Employer_Address1__StateCode__s,
                Career_Break_Employer_Address1__Street__s,
                Career_Break_Employer_Address1__PostalCode__s,
                Self_Employed_Start_Date1__c,
                Self_Employed_End_Date1__c,
                Last_UK_Employer_Name__c,
                Last_UK_Employer_Start_Date__c,
                Last_UK_Employer_End_Date__c,
                Last_UK_Employer_Address__City__s,
                Last_UK_Employer_Address__CountryCode__s,
                Last_UK_Employer_Address__StateCode__s,
                Last_UK_Employer_Address__Street__s,
                Last_UK_Employer_Address__PostalCode__s,
                Employed_Direcly__c,
                Right_of_dismissal__c,
                Abroad_Employer_Address1_State__c,
                Career_Break_Employer_Address1_State__c,
                Last_UK_Employer_Address_State__c,
                Previous_UK_Address1_State__c,
                Current_Address_Abroad_State__c,
                Last_UK_Home_Address_State__c,
                Abroad_Employer_Address1_Country__c,
                Career_Break_Employer_Address1_Country__c,
                Current_Address_Abroad_Country__c,
                Last_UK_Employer_Address_Country__c,
                Last_UK_Home_Address_Country__c,
                Previous_UK_Address_1_Country__c,
                Related_Contact_Phone__c,
                Pay_Voluntary_Contribution_At__c,
                Govt_Org_Who_has_Right_of_Dismissal__c,
                Is_Self_Assessment__c,
                Is_Individual_Pay_Section__c,
                Date_of_Last_Pay_Contributions__c,
                    (SELECT
                        Employer_Name__c,
                        Start_Date__c,
                        End_Date__c,
                        Employers_Address__City__s,
                        Employers_Address__CountryCode__s,
                        Employers_Address__StateCode__s,
                        Employers_Address__Street__s,
                        Employers_Address__PostalCode__s,
                        Type__c,
                        Career_Break__c,
                        Self_employed__c,
                        Employed__c,
                        Employers_Address_Country__c
                    FROM Employers__r),
                Step__c
            FROM Application__c
            WHERE Id =: applicationId
                AND Expiry_Date__c >: Datetime.now()
            LIMIT 1];
    }

    public void execute(QueueableContext context) {
        /*if (app != null && app.Are_You_Single__c == true) {
            app.Did_You_Change_Name__c = null;
        }*/
        RequestWrapper requestData = new RequestWrapper();
        requestData.application = app;
        app.Last_UK_Employer_Address__CountryCode__s = null;
        System.debug('app.Agent__c === ' + app.Agent__c);
        List<Agent__c> agents = [
            SELECT
                Name,
                First_Name__c,
                Last_Name__c,
                Name_of_Company__c,
                Agent_s_Business_Name__c,
                Company_Address__City__s,
                Company_Address__CountryCode__s,
                Company_Address__PostalCode__s,
                Company_Address__StateCode__s,
                Company_Address__Street__s,
                Company_Phone_Number__c,
                Agent_Address__City__s,
                Agent_Address__CountryCode__s,
                Agent_Address__PostalCode__s,
                Agent_Address__StateCode__s,
                Agent_Address__Street__s,
                Agent_Phone_Number__c,
                Agent_code_SA__c,
                Agent_code_CT__c,
                Client_reference__c,
                Self_Assessment__c,
                Partnership__c,
                National_Insurance_number__c,
                Unique_Tax_reference__c,
                UTR_Has_Not_Been_Issued__c,
                Trust__c,
                Individual_Pay_As_You_Earn_PAYE__c,
                Corporation_Tax__c,
                Company_Registration_Number__c,
                Company_Unique_Tax_Reference__c,
                Tax_Credits__c,
                Joint_Claimant_Name__c,
                Joint_Claimant_National_Insurance_Number__c,
                VAT__c,
                VAT_Registration_Number__c,
                Not_Registered_Yet_VAT__c,
                Construction_Industry_Scheme__c,
                CIS_Reference_Number__c,
                PAYE_Reference_Number__c,
                Agent_Government_Gateway_identifier__c,
                PAYE_Agent_ID_code__c,
                Contractor_CIS_Use_Online_Services__c,
                Contractor_CIS_Receive_Info__c,
                Employers_PAYE__c,
                Authorise_Agent_Use_PAYE_Online_Service__c,
                Authorise_Agent_Receive_Info__c,
                Agent_Office_Name__c
            FROM Agent__c
            WHERE Id = : app.Agent__c
            LIMIT 1
        ];
        System.debug('agents === ' + agents);
        System.debug('agents.isEmpty() === ' + agents.isEmpty());
        if(agents.isEmpty()) {
            requestData.agent = null;
        } else {
            requestData.agent = agents[0];
        }
        System.debug('requestData.agent === ' + requestData.agent);
        Http http = new Http();
	    HttpRequest request = new HttpRequest();
	    request.setEndpoint(FILL_FROM_URL);
	    request.setMethod('POST');
	    request.setHeader('Content-Type', 'application/json;charset=UTF-8');
	    // Set the body as a JSON object
	    request.setBody(JSON.serialize(requestData));
        HttpResponse response = http.send(request);
	    // Parse the JSON response
        try {
            if (response.getStatusCode() != 201) {
                update app;
                System.debug('The status code returned was not expected: ' +
                response.getStatusCode() + ' ' + response.getStatus());
                System.debug('response.getBody() ==== ' + response.getBody());
                ResponseWrapper wrapper = (ResponseWrapper) System.JSON.deserialize(response.getBody(), ResponseWrapper.class);
                List<ContentDocumentLink> oldDocuments = [
                    SELECT
                        ContentDocument.Title,
                        LinkedEntityId
                    FROM ContentDocumentLink
                    WHERE (ContentDocument.Title LIKE '%CF083%' OR
                           ContentDocument.Title LIKE '%64-8%') AND
                           LinkedEntityId = :app.Id
                ];
    
                if (!oldDocuments.isEmpty()) {
                    List<ContentDocumentLink> cf083Docs         = new List<ContentDocumentLink>();
                    List<ContentDocumentLink> agentDocs         = new List<ContentDocumentLink>();
                    ContentDocument forSignatureCF083Doc        = new ContentDocument();
                    ContentDocument forSignatureAgentDoc        = new ContentDocument();
                    List<SObject> updateDocs = new List<SObject>();
                    for (ContentDocumentLink doc : oldDocuments) {
                        if (doc.ContentDocument.Title.contains('CF083')) {
                            cf083Docs.add(doc);
                        } else if (doc.ContentDocument.Title.contains('64-8')) {
                            agentDocs.add(doc);
                        }
                    }
                    if (!cf083Docs.isEmpty()) {
                        for (ContentDocumentLink link : cf083Docs) {
                            if (link.ContentDocument.Title.contains('ForSignature') && !link.ContentDocument.Title.contains('completed')) {
                                forSignatureCF083Doc.Id    = link.ContentDocument.Id;
                                forSignatureCF083Doc.Title = link.ContentDocument.Title.replace('ForSignature', 'v' + cf083Docs.size() + '.0');
                                updateDocs.add(forSignatureCF083Doc);
                            }
                        }
                    }
                    if (!agentDocs.isEmpty()) {
                        for (ContentDocumentLink link : agentDocs) {
                            if (link.ContentDocument.Title.contains('ForSignature') && !link.ContentDocument.Title.contains('completed')) {
                                forSignatureAgentDoc.Id    = link.ContentDocument.Id;
                                forSignatureAgentDoc.Title = link.ContentDocument.Title.replace('ForSignature', 'v' + agentDocs.size() + '.0');
                                updateDocs.add(forSignatureAgentDoc);
                            }
                        }
                    }
                    if (!updateDocs.isEmpty()) {
                        update updateDocs;
                    }
                }
                List<ContentVersion> newContentVersions = new List<ContentVersion>();
                ContentVersion conVerCF83 = new ContentVersion();
                conVerCF83.ContentLocation = 'S';
                conVerCF83.PathOnClient = app.First_Name__c + '_' + app.Second_Name__c + '_' + app.Name + '_CF083_ForSignature.pdf';
                conVerCF83.Title = app.First_Name__c + '_' + app.Second_Name__c + '_' + app.Name + '_CF083_ForSignature';
                conVerCF83.VersionData = EncodingUtil.base64Decode(wrapper?.result?.application);
                newContentVersions.add(conVerCF83);
                ContentVersion conVer64_8 = new ContentVersion();
                conVer64_8.ContentLocation = 'S';
                conVer64_8.PathOnClient = app.First_Name__c + '_' + app.Second_Name__c + '_' + app.Name + '_64-8_ForSignature.pdf'; 
                conVer64_8.Title = app.First_Name__c + '_' + app.Second_Name__c + '_' + app.Name + '_64-8_ForSignature'; 
                conVer64_8.VersionData = EncodingUtil.base64Decode(wrapper?.result?.agent);
                newContentVersions.add(conVer64_8);
                insert newContentVersions;
    
                List<Id> conVersIds = new List<Id>();
                conVersIds.add(conVerCF83.Id);
                conVersIds.add(conVer64_8.Id);
    
                Map<Id, ContentVersion> conDocs = new Map<Id, ContentVersion>([
                    SELECT
                        ContentDocumentId,
                        ContentSize
                    FROM ContentVersion
                    WHERE Id IN :conVersIds
                ]);
    
                List<ContentDocumentLink> conDocLinks = new List<ContentDocumentLink>();
                ContentDocumentLink conDocLinkCF83 = new ContentDocumentLink();
                conDocLinkCF83.LinkedEntityId = app.Id;
                conDocLinkCF83.ContentDocumentId = conDocs.get(conVerCF83.Id).ContentDocumentId;
                conDocLinkCF83.shareType = 'V';
                conDocLinkCF83.Visibility = 'AllUsers';
                conDocLinks.add(conDocLinkCF83);
                ContentDocumentLink conDocLink64_8 = new ContentDocumentLink();
                conDocLink64_8.LinkedEntityId = app.Id;
                conDocLink64_8.ContentDocumentId = conDocs.get(conVer64_8.Id).ContentDocumentId;
                conDocLink64_8.shareType = 'V';
                conDocLinkCF83.Visibility = 'AllUsers';
                conDocLinks.add(conDocLink64_8);
                insert conDocLinks;
    
                List<Application_Document__c> relatedApplicationDocuments = [
                    SELECT 
                        File_Name__c
                    FROM Application_Document__c
                    WHERE Application__c = :app.Id AND
                          (File_Name__c LIKE '%CF083%' OR 
                           File_Name__c LIKE '%64-8%')
                ];
                if (!relatedApplicationDocuments.isEmpty()) {
                    List<ContentDocumentLink> conDocLinksAppDocs = new List<ContentDocumentLink>();
                    Application_Document__c cf083AppDocum;
                    Application_Document__c agentAppDocum;
                    for (Application_Document__c addDoc : relatedApplicationDocuments) {
                        if (addDoc.File_Name__c.contains('CF083')) {
                            cf083AppDocum = addDoc;
                        } else if (addDoc.File_Name__c.contains('64-8')) {
                            agentAppDocum = addDoc;
                        }
                    }
                    if (cf083AppDocum != null) {
                        ContentDocumentLink conDocLinkCF83AppDoc = new ContentDocumentLink();
                        conDocLinkCF83AppDoc.LinkedEntityId = cf083AppDocum.Id;
                        conDocLinkCF83AppDoc.ContentDocumentId =  conDocs.get(conVerCF83.Id).ContentDocumentId;  
                        conDocLinkCF83AppDoc.shareType = 'V';
                        conDocLinkCF83AppDoc.Visibility = 'AllUsers';
                        conDocLinksAppDocs.add(conDocLinkCF83AppDoc);
                    }
                    if (agentAppDocum != null) {
                        ContentDocumentLink conDocLinkAgentAppDoc = new ContentDocumentLink();
                        conDocLinkAgentAppDoc.LinkedEntityId = agentAppDocum.Id;
                        conDocLinkAgentAppDoc.ContentDocumentId =  conDocs.get(conVer64_8.Id).ContentDocumentId; 
                        conDocLinkAgentAppDoc.shareType = 'V';
                        conDocLinkAgentAppDoc.Visibility = 'AllUsers';
                        conDocLinksAppDocs.add(conDocLinkAgentAppDoc);
                    }
                    if (!conDocLinksAppDocs.isEmpty()) {
                        Database.insert(conDocLinksAppDocs, false);
                    }
                } else {
                    List<Application_Document__c> newAppDocs = new List<Application_Document__c>();
                    Application_Document__c agentAppDoc = new Application_Document__c(
                        Type__c = 'Statement of Social Insurance',
                        Application__c = applicationId,
                        File_Name__c = app.First_Name__c + '_' + app.Second_Name__c + '_' + app.Name + '_64-8_ForSignature',
                        File_Size__c = conDocs.get(conVer64_8.Id).ContentSize,
                        Status__c = 'New'
                    );
                    newAppDocs.add(agentAppDoc);
                    Application_Document__c cf083AppDoc = new Application_Document__c(
                        Type__c = 'Statement of Social Insurance',
                        Application__c = applicationId,
                        File_Name__c = app.First_Name__c + '_' + app.Second_Name__c + '_' + app.Name + '_CF083_ForSignature',
                        File_Size__c = conDocs.get(conVerCF83.Id).ContentSize,
                        Status__c = 'New'
                    );
                    newAppDocs.add(cf083AppDoc);
                    insert newAppDocs;
                    List<ContentDocumentLink> newContDocs = new List<ContentDocumentLink>();
                    newContDocs.add(new ContentDocumentLink(
                        ContentDocumentId = conDocs.get(conVer64_8.Id).ContentDocumentId,
                        LinkedEntityId    = agentAppDoc.Id,
                        ShareType = 'V',
                        Visibility = 'AllUsers'
                    ));
                    newContDocs.add(new ContentDocumentLink(
                        ContentDocumentId = conDocs.get(conVerCF83.Id).ContentDocumentId,
                        LinkedEntityId    = cf083AppDoc.Id,
                        ShareType = 'V',
                        Visibility = 'AllUsers'
                    ));
                    insert newContDocs;
                }
            } else {
                System.debug('In else');
                System.debug(response.getBody());
            }
            pdfAction();
        } catch (Exception ex) {
            System.debug(ex.getLineNumber() + ' - ' + ex.getMessage());
            update new Application__c(Id = app.Id, Heroku_Request__c = JSON.serialize(requestData));
        }
	    
    }

    public void pdfAction() {
        PageReference savepage ;
        savepage = Page.CustomLetter;
        savepage.getParameters().put('id', applicationId);
        blob pdfBlob;
        if (!Test.isRunningTest()) {
            pdfBlob = savepage.getContent();
        } else {
            pdfBlob = Blob.valueOf('Test');
        }
        List<ContentDocumentLink> oldDocuments = [
            SELECT
                ContentDocument.Title,
                LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocument.Title LIKE '%CustomLetter%' AND 
                  LinkedEntityId = :app.Id
        ];
        String forSignatureContDocument;
        for (ContentDocumentLink link : oldDocuments) {
            if (link.ContentDocument.Title.contains('ForSignature')) {
                forSignatureContDocument = link.ContentDocumentId;
                break;
            }
        }
        if (forSignatureContDocument != null) {
            List<ContentDocument> contentDocument = [
                SELECT Title
                FROM ContentDocument
                WHERE Id = :forSignatureContDocument
            ];
            if (!contentDocument.isEmpty()) {
                contentDocument[0].Title = contentDocument[0].Title.replace('ForSignature', 'v' + oldDocuments.size() + '.0');
                update contentDocument;
            }
        }

        String FinalTitle = app.First_Name__c + '_' + app.Second_Name__c + '_' + app.Name +'_CustomLetter_ForSignature';

		ContentVersion conVer = new ContentVersion();
		conVer.ContentLocation = 'S';
		conVer.PathOnClient = FinalTitle+'.pdf';
		conVer.Title = FinalTitle;
		conVer.VersionData = pdfBlob;
		system.debug('conVer@@ ' + conVer);
		insert conVer;

		ContentVersion conDoc = [SELECT ContentDocumentId, ContentSize FROM ContentVersion WHERE Id =:conVer.Id][0];

		ContentDocumentLink conDocLink = New ContentDocumentLink();
		conDocLink.LinkedEntityId = applicationId;
		conDocLink.ContentDocumentId = conDoc.ContentDocumentId;
		conDocLink.shareType = 'V';
        conDocLink.Visibility = 'AllUsers';
		insert conDocLink;

        List<Application_Document__c> relatedApplicationDocuments = [
            SELECT
                File_Name__c
            FROM Application_Document__c
            WHERE Application__c = :app.Id AND
                  File_Name__c LIKE '%CustomLetter%'
        ];
        if (relatedApplicationDocuments.isEmpty()) {
            Application_Document__c appDoc = new Application_Document__c(
                Type__c = 'Custom Letter',
                Application__c = applicationId,
                File_Name__c = FinalTitle,
                File_Size__c = conDoc.ContentSize,
                Status__c = 'New'
                );
            insert appDoc;
            insert new ContentDocumentLink(
                ContentDocumentId = conDoc.ContentDocumentId,
                LinkedEntityId    = appDoc.Id,
                ShareType = 'V',
                Visibility = 'AllUsers'
            );
        } else {
            Application_Document__c relatedDocument = relatedApplicationDocuments[0];
            Database.insert (new ContentDocumentLink(
                ContentDocumentId = conDoc.ContentDocumentId,
                LinkedEntityId    = relatedDocument.Id,
                ShareType = 'V',
                Visibility = 'AllUsers'
            ),false);
        }

    }

    public class ResponseWrapper {
        public String status;
        public ResponseResultWrapper result;
    }

    public class ResponseResultWrapper {
        public String application;
        public String agent;
    }

    public class RequestWrapper {
        public Application__c application;
        public Agent__c agent;
    }
}