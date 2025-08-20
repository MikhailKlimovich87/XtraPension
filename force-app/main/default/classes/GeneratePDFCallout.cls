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
        RequestWrapper requestData = new RequestWrapper();
        requestData.application = app;
        app.Last_UK_Employer_Address__CountryCode__s = null;
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
	    // Parse the JSON response
        try {
            if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
                update app;
                ResponseWrapper wrapper = (ResponseWrapper) System.JSON.deserialize(response.getBody(), ResponseWrapper.class);
                PageReference savepage ;
                savepage = Page.CustomLetter;
                savepage.getParameters().put('id', applicationId);
                blob pdfBlob;
                if (!Test.isRunningTest()) {
                    pdfBlob = savepage.getContent();
                } else {
                    pdfBlob = Blob.valueOf('Test');
                }
                List<ContentVersion> newContVersions = new List<ContentVersion>();
                List<ContentVersion> updatedContVers = new List<ContentVersion>();
                Map<String, ContentDocumentLink> fileLabelByLink = new Map<String, ContentDocumentLink>();
                for (ContentDocumentLink link : [
                    SELECT
                        ContentDocument.Title,
                        ContentDocumentId,
                        LinkedEntityId
                    FROM ContentDocumentLink
                    WHERE (ContentDocument.Title LIKE '%CF083_ForSignature%' OR
                           ContentDocument.Title LIKE '%64-8_ForSignature%' OR
                           ContentDocument.Title LIKE '%CustomLetter_ForSignature%') AND
                           LinkedEntityId = :app.Id
                ]) {
                    ContentVersion conVer = new ContentVersion();
                    if (link.ContentDocument.Title.contains('CF083_ForSignature')) {
                        conVer = createContentVerison(
                            EncodingUtil.base64Decode(wrapper?.result?.application),
                            app.First_Name__c + '_' + app.Second_Name__c + '_' + app.Name + '_CF083_ForSignature'
                       );
                        fileLabelByLink.put('CF083_ForSignature', link);
                    }
                    if (link.ContentDocument.Title.contains('64-8_ForSignature')) {
                        conVer = createContentVerison(
                            EncodingUtil.base64Decode(wrapper?.result?.agent),
                            app.First_Name__c + '_' + app.Second_Name__c + '_' + app.Name + '_64-8_ForSignature'
                        );
                        fileLabelByLink.put('64-8_ForSignature', link);
                    }
                    if (link.ContentDocument.Title.contains('CustomLetter_ForSignature')) {
                        conVer = createContentVerison(
                            pdfBlob,
                            app.First_Name__c + '_' + app.Second_Name__c + '_' + app.Name + '_CustomLetter_ForSignature'
                        );
                        fileLabelByLink.put('CustomLetter_ForSignature', link);
                    }
                    conVer.ContentDocumentId = link.ContentDocumentId;
                    updatedContVers.add(conVer);
                }
                if (updatedContVers.size() != 0) {
                    Database.SaveResult[] results = Database.insert(updatedContVers, false);
                }
                if(fileLabelByLink.get('CF083_ForSignature') == null) {
                    newContVersions.add(
                        createContentVerison(
                            EncodingUtil.base64Decode(wrapper?.result?.application),
                            app.First_Name__c + '_' + app.Second_Name__c + '_' + app.Name + '_CF083_ForSignature'
                        )
                    );
                }
                if(fileLabelByLink.get('64-8_ForSignature') == null) {
                    newContVersions.add(
                        createContentVerison(
                            EncodingUtil.base64Decode(wrapper?.result?.agent),
                            app.First_Name__c + '_' + app.Second_Name__c + '_' + app.Name + '_64-8_ForSignature'
                        )
                    );
                }
                if(fileLabelByLink.get('CustomLetter_ForSignature') == null) {
                    newContVersions.add(
                        createContentVerison(
                            pdfBlob,
                            app.First_Name__c + '_' + app.Second_Name__c + '_' + app.Name + '_CustomLetter_ForSignature'
                        )
                    );
                }
                if (newContVersions.size() != 0) {
                    Database.insert(newContVersions, false);
                    createContentLinks(newContVersions);
                }
            } else {
                update new Application__c(Id = app.Id, Heroku_Request__c = response.getBody());
            }
        } catch (Exception ex) {
            update new Application__c(Id = app.Id, Heroku_Request__c = JSON.serialize(requestData));
        }
    }

    private ContentVersion createContentVerison(Blob pdfBlob, String title) {
        return new ContentVersion(
            VersionData = pdfBlob,
            ContentLocation = 'S',
            PathOnClient = title +'.pdf',
            Title = title
        );
    }

    private void createContentLinks(List<ContentVersion> newDocuments) {
        Map<Id, ContentVersion> newContVersMap = new Map<Id, ContentVersion>(newDocuments);
        List<ContentVersion> conDocs = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id IN :newContVersMap.keySet()
        ];
        if (conDocs.size() != 0) {
            List<ContentDocumentLink> contentDocLinks = new List<ContentDocumentLink>();
            for (ContentVersion version : conDocs) {
                contentDocLinks.add(
                    new ContentDocumentLink(
                        LinkedEntityId = app.Id,
                        ContentDocumentId = version.ContentDocumentId,
                        shareType = 'V',
                        Visibility = 'AllUsers'
                    )
                );
            }
            insert contentDocLinks;
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