public without sharing class GeneratePdfFileController {
    public static final String FILL_FROM_URL = XtraPension_Data__c.getInstance().Fill_Pdf_File_Link__c;
    public static final String PUBLIC_GROUP_NAME = 'XtraPension';

    @AuraEnabled(cacheable=false)
    public static ApplicationDocsWrapper getApplication(String recordId) {
        List<Application__c> apps = [
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
                Pay_By__c,
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
                Previous_UK_Address_1__CountryCode__s,
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
                        Employed__c
                    FROM Employers__r),
                Step__c
            FROM Application__c
            WHERE Id =: recordId
                AND Expiry_Date__c >: Datetime.now()
            LIMIT 1];
        RequestWrapper requestData = new RequestWrapper();
        Application__c app;
        if (!apps.isEmpty()) {
            app = apps[0];
            if (app.National_Insurance_Number__c != null && app.Type_Of_Employment__c == 'Self-Employed')  {
                app.Is_Self_Assessment__c = true;
                app.Is_Individual_Pay_Section__c = true;
            } else {
                app.Is_Self_Assessment__c = false;
                app.Is_Individual_Pay_Section__c = true;
            }
            requestData.application = app;
            app.Last_UK_Employer_Address__CountryCode__s = null;
            app.Current_Address_Abroad_State__c = CountryCodeHelper.getCountryStateNameByIsoCode(
                app.Current_Address_Abroad__CountryCode__s,
                app.Current_Address_Abroad__StateCode__s);
            List<Employer__c> afterUKEmployers = [
                SELECT
                    Employer_Name__c,
                    Employers_Address__City__s,
                    Employers_Address__CountryCode__s,
                    Employers_Address__PostalCode__s,
                    Employers_Address__StateCode__s,
                    Employers_Address__Street__s,
                    Employers_Address_Country__c,
                    Employers_Address_State__c,
                    Start_Date__c,
                    End_Date__c,
                    Type_Of_After_UK_Employment__c,
                    Application__c,
                    Is_First_Employer__c
                FROM Employer__c
                WHERE Type__c = 'Work After UK' AND
                      Application__c = :app.Id
                ORDER BY Start_Date__c
            ];
            for (Employer__c employer : afterUKEmployers) {
                if (employer.Type_Of_After_UK_Employment__c == 'Self-Employed') {
                    app.Self_Employed_Start_Date1__c             = employer.Start_Date__c;
                    app.Self_Employed_End_Date1__c               = employer.End_Date__c;
                    app.SelfEmployment_Employment_Abroad__c      = 'Self-employed';
                    app.Abroad_Start_Date__c                     = null;
                    app.Abroad_Employer_Name1__c                 = null;
                    app.Abroad_Employer_Start_Date1__c           = null;
                    app.Abroad_Employer_End_Date1__c             = null;
                    app.Abroad_Employer_Address1__City__s        = null;
                    app.Abroad_Employer_Address1__CountryCode__s = null;
                    app.Abroad_Employer_Address1__StateCode__s   = null;
                    app.Abroad_Employer_Address1__Street__s      = null;
                    app.Abroad_Employer_Address1__PostalCode__s  = null;
                    app.Abroad_Employer_Address1_Country__c      = null;
                    app.Abroad_Employer_Address1_State__c        = null;
                    break;
                }
                if (employer.Type_Of_After_UK_Employment__c == 'Employed') {
                    app.Abroad_Start_Date__c                     = employer.Start_Date__c;
                    app.Abroad_Employer_Name1__c                 = employer.Employer_Name__c;
                    app.Abroad_Employer_Start_Date1__c           = employer.Start_Date__c;
                    app.Abroad_Employer_End_Date1__c             = employer.End_Date__c;
                    app.Abroad_Employer_Address1__City__s        = employer.Employers_Address__City__s;
                    app.Abroad_Employer_Address1__CountryCode__s = employer.Employers_Address__CountryCode__s;
                    app.Abroad_Employer_Address1__StateCode__s   = employer.Employers_Address__StateCode__s;
                    app.Abroad_Employer_Address1__Street__s      = employer.Employers_Address__Street__s;
                    app.Abroad_Employer_Address1__PostalCode__s  = employer.Employers_Address__PostalCode__s;
                    app.Abroad_Employer_Address1_Country__c      = employer.Employers_Address_Country__c;
                    app.Abroad_Employer_Address1_State__c        = employer.Employers_Address_State__c;
                    app.Self_Employed_Start_Date1__c             = null;
                    app.Self_Employed_End_Date1__c               = null;
                    app.SelfEmployment_Employment_Abroad__c      = 'Employed';
                    break;
                }
            }
        }
        // if (app.Are_You_Single__c == true) {
        //     app.Did_You_Change_Name__c = null;
        // }
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
        if(agents.isEmpty()) {
            requestData.agent = null;
        } else {
            requestData.agent = agents[0];
        }
        Http http = new Http();
	    HttpRequest request = new HttpRequest();
	    request.setEndpoint(FILL_FROM_URL);
	    request.setMethod('POST');
	    request.setHeader('Content-Type', 'application/json;charset=UTF-8');
	    // Set the body as a JSON object
	    request.setBody(JSON.serialize(requestData));
	    HttpResponse response = http.send(request);
        ApplicationDocsWrapper docsWrapper = new ApplicationDocsWrapper();
        update new Application__c(Id = recordId, Request_Data__c = JSON.serialize(requestData));
	    // Parse the JSON response
	    if (response.getStatusCode() != 201) {
    	    System.debug('The status code returned was not expected: ' +
    	    response.getStatusCode() + ' ' + response.getStatus());
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
                List<ContentDocumentLink> cf083Docs = new List<ContentDocumentLink>();
                List<ContentDocumentLink> agentDocs = new List<ContentDocumentLink>();
                ContentDocument forSignatureCF083Doc = new ContentDocument();
                ContentDocument forSignatureAgentDoc = new ContentDocument();
                Set<SObject> updateDocs = new Set<SObject>();
                for (ContentDocumentLink doc : oldDocuments) {
                    if (doc.ContentDocument.Title.contains('CF083')) {
                        cf083Docs.add(doc);
                        if (doc.ContentDocument.Title.contains('ForSignature') && !doc.ContentDocument.Title.contains('completed') && forSignatureCF083Doc.Title == null) {
                            forSignatureCF083Doc.Id    = doc.ContentDocument.Id;
                            forSignatureCF083Doc.Title = doc.ContentDocument.Title.replace('ForSignature', 'v' + oldDocuments.size() / 2 + '.0');
                            updateDocs.add(forSignatureCF083Doc);
                        }
                    } else if (doc.ContentDocument.Title.contains('64-8')) {
                        agentDocs.add(doc);
                        if (doc.ContentDocument.Title.contains('ForSignature') && !doc.ContentDocument.Title.contains('completed') && forSignatureAgentDoc.Title == null) {
                            forSignatureAgentDoc.Id    = doc.ContentDocument.Id;
                            forSignatureAgentDoc.Title = doc.ContentDocument.Title.replace('ForSignature', 'v' + oldDocuments.size() / 2 + '.0');
                            updateDocs.add(forSignatureAgentDoc);
                        }
                    }
                }
                if (!updateDocs.isEmpty()) {
                    update new List<SObject>(updateDocs);
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
            conDocLink64_8.Visibility = 'AllUsers';
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
            }
            docsWrapper.cf83DocLink  = URL.getOrgDomainUrl().toExternalForm() + '/sfc/servlet.shepherd/document/download/' + conDocs.get(conVerCF83.Id).ContentDocumentId;
            docsWrapper.agentDocLink = URL.getOrgDomainUrl().toExternalForm() + '/sfc/servlet.shepherd/document/download/' + conDocs.get(conVer64_8.Id).ContentDocumentId;
            docsWrapper.status = 'Success';
	    } else {
            docsWrapper.status = 'Error: ' + response.getBody();
	    }
        return docsWrapper;
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

    public class ApplicationDocsWrapper{
        @AuraEnabled
        public String cf83DocLink{get;set;}
        @AuraEnabled
        public String agentDocLink{get;set;}
        @AuraEnabled
        public String status{get;set;}
    }
}