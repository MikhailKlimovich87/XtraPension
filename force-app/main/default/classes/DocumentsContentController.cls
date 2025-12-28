public without sharing class DocumentsContentController {
    private static final StaticResource TRANSFER_UK_PENSION_ATTACH_FILE {
        get {
            if (TRANSFER_UK_PENSION_ATTACH_FILE == null) {
                List<StaticResource> resources = [
                    SELECT
                        Name,
                        Body,
                        Description
                    FROM StaticResource
                    WHERE Name = 'Transfer_Private_UK_Pension_to_Ireland'
                ];
                if (!resources.isEmpty()) {
                    TRANSFER_UK_PENSION_ATTACH_FILE = resources[0];
                }
            }
            return TRANSFER_UK_PENSION_ATTACH_FILE;
        }
        private set;
    }
    private static final String HMRC_RESULT_STATUS = 'Agent Call';
    private static final String MISSING_APPLICATION_PAYMENT_RECIPIENT_ADDRESS = 'fernando@xtrapension.com';
    private static final OrgWideEmailAddress DEFAULT_ORG_WIDE_EMAIL_ADDRESS {
        get {
            if (DEFAULT_ORG_WIDE_EMAIL_ADDRESS == null) {
                List<OrgWideEmailAddress> orgWideEmailAddresses = [
                    SELECT Id
                    FROM OrgWideEmailAddress
                    WHERE Address = 'clients@xtrapension.com'
                    WITH USER_MODE
                    LIMIT 1
                ];
                if (!orgWideEmailAddresses.isEmpty()) {
                    DEFAULT_ORG_WIDE_EMAIL_ADDRESS = orgWideEmailAddresses[0];
                }
            }
            return DEFAULT_ORG_WIDE_EMAIL_ADDRESS;
        }
        private set;
    }

    @AuraEnabled(cacheable='false')
    public static DocumentsData getContentDocuments(String recordId){
        List<ContentDocumentLink> forSignatureContentDocs = [
            SELECT
                ContentDocumentId,
                ContentDocument.Title,
                LinkedEntityId,
                ContentDocument.LatestPublishedVersion.CreatedDate
            FROM ContentDocumentLink
            WHERE
                LinkedEntityId = :recordId AND
                ContentDocument.FileType != 'SNOTE' AND
                (ContentDocument.Title LIKE '%ForSignature%' OR
                ContentDocument.Title LIKE '%ClientSummary%' OR
                ContentDocument.Title LIKE 'DWPStatusCheck' OR
                ContentDocument.Title LIKE 'CUSTOM reply' OR
                ContentDocument.Title LIKE 'APPEAL reply' OR
                ContentDocument.Title LIKE '%C2%' OR
                ContentDocument.Title LIKE '%C3%' OR
                ContentDocument.Title LIKE '%C2 AGT%' OR
                ContentDocument.Title LIKE '%CUSTOM%' OR
                ContentDocument.Title LIKE '%NINO%' OR
                ContentDocument.Title LIKE '%DWP%' OR
                ContentDocument.Title LIKE '%APPEAL%'OR
                ContentDocument.Title LIKE '%Next Step 2%'OR
                ContentDocument.Title LIKE '%Next Step 1%' OR
                ContentDocument.Title LIKE '%Annual Service%' OR
                ContentDocument.Title LIKE '%Private Pensions%' OR
                ContentDocument.Title LIKE 'CURRENT JOB reply' OR
                ContentDocument.Title LIKE 'NINO reply' OR
                ContentDocument.Title LIKE 'EU Residency Appeal' OR
                ContentDocument.Title LIKE '%PENALTY%' OR
                ContentDocument.Title LIKE '%2024ANNUAL' OR
                ContentDocument.Title LIKE '%64-8 Update Letter' OR
                ContentDocument.Title LIKE '%Bounce Letter'
                )
            ORDER BY ContentDocument.LatestPublishedVersion.CreatedDate DESC
        ];

        List<ContentDocumentLink> hmrcAssessmentContentDocs = [
            SELECT
                ContentDocumentId,
                ContentDocument.Title,
                LinkedEntityId,
                ContentDocument.LatestPublishedVersion.CreatedDate
            FROM ContentDocumentLink
            WHERE
                LinkedEntityId = :recordId AND
                ContentDocument.Title LIKE '%HMRC Assessment%'
            ORDER BY ContentDocument.LatestPublishedVersion.CreatedDate DESC
            LIMIT 1
        ];
        List<Application__c> currentApplication = [
            SELECT
                Name,
                Type_Of_Employment__c,
                Freeform_RichText_Line1__c,
				Freeform_RichText_Line2__c,
				Freeform_RichText_Line3__c,
				Freeform_RichText_Line4__c,
				Freeform_RichText_Line5__c,
                DWP_Callback_Request__c,
                Current_Address_Abroad__Street__s,
                Current_Address_Abroad__City__s,
                Current_Address_Abroad__CountryCode__s,
                Current_Address_Abroad__StateCode__s,
                Current_Address_Abroad__PostalCode__s,
                Docusigned_Date__c,
                National_Insurance_Number__c,
                Salutation__c,
                First_Name__c,
                Second_Name__c,
                Agent__r.First_Name__c,
                Agent__r.Last_Name__c,
                Last_UK_Home_Address__Street__s,
                Last_UK_Home_Address__City__s,
                Last_UK_Home_Address__CountryCode__s,
                Last_UK_Home_Address__PostalCode__s,
                Previous_UK_Address_1__Street__s,
                Previous_UK_Address_1__City__s,
                Previous_UK_Address_1__CountryCode__s,
                Previous_UK_Address_1__PostalCode__s,
                Include_UK_Address1__c,
                Previous_UK_Address_2__Street__s,
                Previous_UK_Address_2__City__s,
                Previous_UK_Address_2__CountryCode__s,
                Previous_UK_Address_2__PostalCode__s,
                Include_UK_Address2__c,
                Previous_UK_Address_3__Street__s,
                Previous_UK_Address_3__City__s,
                Previous_UK_Address_3__CountryCode__s,
                Previous_UK_Address_3__PostalCode__s,
                Include_UK_Address3__c,
                Previous_UK_Address_4__Street__s,
                Previous_UK_Address_4__City__s,
                Previous_UK_Address_4__CountryCode__s,
                Previous_UK_Address_4__PostalCode__s,
                Include_UK_Address4__c,
                Previous_UK_Address_5__Street__s,
                Previous_UK_Address_5__City__s,
                Previous_UK_Address_5__CountryCode__s,
                Previous_UK_Address_5__PostalCode__s,
                Include_UK_Address5__c,
                Last_UK_Employer_Name__c,
                Last_UK_Employer_Start_Date__c,
                Last_UK_Employer_End_Date__c,
                Last_UK_Employer_Address__City__s,
                Last_UK_Employer_Address__CountryCode__s,
                Last_UK_Employer_Address__StateCode__s,
                Last_UK_Employer_Address__Street__s,
                Last_UK_Employer_Address__PostalCode__s,
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
                Current_Address_Abroad_State__c,
                Current_Address_Abroad_Country__c,
                Last_UK_Home_Address_Country__c,
                Previous_UK_Address_1_Country__c,
                Previous_UK_Address_2_Country__c,
                Previous_UK_Address_3_Country__c,
                Previous_UK_Address_4_Country__c,
                Previous_UK_Address_5_Country__c,
                Abroad_Employer_Address1_Country__c,
                Career_Break_Employer_Address1_Country__c,
                Last_UK_Employer_Address_Country__c,
                HMRC_Reply_Status__c,
                Is_Know_National_Insurance_Number__c,
                Previous_UK_Address_End_Date_1__c,
                Previous_UK_Address_End_Date_2__c,
                Previous_UK_Address_End_Date_3__c,
                Previous_UK_Address_Start_Date_1__c,
                Previous_UK_Address_Start_Date_2__c,
                Previous_UK_Address_Start_Date_3__c,
                Custom_Letter_Date__c,
                Status__c,
                Appeal_Application__c,
                    (SELECT
                        Employer_Name__c,
                        Start_Date__c,
                        End_Date__c,
                        Employers_Address__Street__s,
                        Employers_Address__City__s,
                        toLabel(Employers_Address__CountryCode__s),
                        toLabel(Employers_Address__StateCode__s),
                        Employers_Address__PostalCode__s,
                        Employers_Address_Country__c,
                        Type_Of_UK_Employment__c
                    FROM Employers__r
                    WHERE Type__c = 'UK Work'),
                    (SELECT
                        Status__c
                    FROM Payments__r
                    WHERE (Product_Name__c = 'Application' OR Product_Name__c = 'Appeal') AND Status__c = 'Paid')
            FROM Application__c
            WHERE Id = :recordId
        ];
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
			WHERE Application__c =: recordId
				AND Type__c = 'Work After UK'
			ORDER BY Start_Date__c ASC
		];
        if (forSignatureContentDocs.isEmpty() || currentApplication.isEmpty()) {
            return null;
        }
        List<dfsle__EnvelopeStatus__c> envelopStatus = [
            SELECT
                dfsle__Status__c,
                    (SELECT
                        Name
                    FROM DocuSign_Envelope_Documents__r)
            FROM dfsle__EnvelopeStatus__c
            WHERE Application__c = :recordId
            ORDER BY CreatedDate DESC
        ];
        DocusingEnvelopeStatus statusWrapper = new DocusingEnvelopeStatus();
        if (!envelopStatus.isEmpty()) {
            for (dfsle__EnvelopeStatus__c status : envelopStatus) {
                for (dfsle__Document__c link : status.DocuSign_Envelope_Documents__r) {
                    if (link.Name.contains('CF083')) {
                        statusWrapper.cf083DocStatus = status.dfsle__Status__c;
                    }
                    if (link.Name.contains('64-8')) {
                        statusWrapper.agentDocStatus = status.dfsle__Status__c;
                    }
                }
                if (statusWrapper.agentDocStatus == 'Completed' && statusWrapper.cf083DocStatus == 'Completed') {
                    break;
                } else if (statusWrapper.agentDocStatus != null && statusWrapper.agentDocStatus != null) {
                    continue;
                }
            }
        }
        DocumentsData data     = new DocumentsData();
        data.latestDocs        = new List<DocumentInfo>();
        data.replyDocs        = new List<DocumentInfo>();
        data.previousAddresses = new List<PreviousUKAddressData>();
        data.abroadEmployers   = new List<EmployerData>();
        Map<String, DocumentInfo> titleByDocumentInfo = new Map<String, DocumentInfo>();
        Application__c app = currentApplication[0];
        ResultEmailTemplate resultBody = new ResultEmailTemplate();
        resultBody.successTemplate = app.Current_Address_Abroad__CountryCode__s == 'IE' ?
                                         XtraPensionConstants.SUCCESS_HMRC_RESULT_IRELAND_CUSTOMER_TEMPLATE.replace('{!Application__c.First_Name__c}', app.First_Name__c) :
                                         XtraPensionConstants.SUCCESS_HMRC_RESULT_TEMPLATE.replace('{!Application__c.First_Name__c}', app.First_Name__c);
        resultBody.rejectTempalte = XtraPensionConstants.REJECT_HMRC_RESULT_TEMPLATE.replace('{!Application__c.First_Name__c}', app.First_Name__c);
        resultBody.emailSubject = app.Name + ' - ' + app.First_Name__c + ' ' + app.Second_Name__c + ' - UK State Pension / Your HMRC Assessment';
        data.templateData = resultBody;
        List<String> notCompletedFiles = new List<String>();
        if(app.Status__c == 'Send to Client') data.isSendToClientAppStatus = true;
        else data.isSendToClientAppStatus = false;

        if(app.Payments__r.size() != 0 ) data.isPaidApplicationPayment = true;
        else data.isPaidApplicationPayment = false;

        for (ContentDocumentLink link : forSignatureContentDocs) {
            String title = link.ContentDocument.Title;
            String docTitle = title.contains('64-8_') ? 'Agent Authorisation':
                                title.contains('CF083') ? 'Application Form' :
                                    title.contains('CustomLetter') ? 'Custom Letter' :
                                        title.contains('UPLOAD') ? 'Client Uploaded Doc' :
                                            title.contains('ClientSummary') ? 'Client Summary' :
                                            title.contains('DWPStatusCheck') ? 'DWP Status Check' :
                                                title.contains('C2 AGT') ? 'C2 AGT' :
                                                    title.contains('C2') ? 'C2' :
                                                        title.contains('C3') ? 'C3' :
                                                        title.contains('CUSTOM') ? 'CUSTOM' :
                                                            title.contains('NINO') ? 'NINO' :
                                                                title.contains('DWP') ? 'DWP' :
                                                                    title.contains('APPEAL') ? 'Appeal' :
                                                                        title.contains('Next Step 1') ? 'Next Step 1' :
                                                                            title.contains('Next Step 2') ? 'Next Step 2' :
                                                                                title.contains('Annual Service') ? 'Annual Service' :
                                                                                    title.contains('APPEAL reply') ? 'APPEAL' :
                                                                                        title.contains('CUSTOM reply') ? 'CUSTOM reply' :
                                                                                            title.contains('NINO reply') ? 'NINO reply' :
                                                                                                title.contains('Private Pensions') ? 'Private Pensions' :
                                                                                                    title.contains('CURRENT JOB reply') ? 'CURRENT JOB' :
                                                                                                        title.contains('EU Residency Appeal') ? 'EU Residency Appeal' :
                                                                                                            title.contains('PENALTY') ? 'PENALTY' :
                                                                                                                title.contains('2024ANNUAL') ? '2024ANNUAL' :
                                                                                                                    title.contains('64-8 Update Letter') ? '64-8 Update Letter' :
                                                                                                                        title.contains('Bounce Letter') ? 'Bounce Letter' : null;
            if (titleByDocumentInfo.get(docTitle) != null) {
                continue;
            }
            DocumentInfo latestInfo = new DocumentInfo();
            latestInfo.title = docTitle;
            latestInfo.documentId  = link.ContentDocumentId;
            Datetime docCreatedDate = link.ContentDocument.LatestPublishedVersion.CreatedDate;
            latestInfo.createdDate = docCreatedDate != null ? docCreatedDate.format('EEE dd MMM yyyy') : '';
            if (latestInfo.title == 'Custom Letter') {
                latestInfo.isCustomLetter = true;
            } else latestInfo.isCustomLetter = false;
            if (latestInfo.title == 'Application Form' && statusWrapper.cf083DocStatus != null) {
                latestInfo.isCompleteDocusignStatus = statusWrapper.cf083DocStatus == 'Completed' ? true : false;
                latestInfo.isApplicationForm        = true;
            }
            if (latestInfo.title == 'Agent Authorisation' && statusWrapper.agentDocStatus != null) {
                latestInfo.isCompleteDocusignStatus = statusWrapper.agentDocStatus == 'Completed' ? true : false;
                latestInfo.isAgentAuthorisation     = true;
            }
            titleByDocumentInfo.put(latestInfo.title, latestInfo);
        }
        if (!hmrcAssessmentContentDocs.isEmpty()) {
            DocumentInfo latestInfo = new DocumentInfo();
            latestInfo.title = 'HMRC Assessment';
            latestInfo.isHMRCReply = true;
            latestInfo.hmrcReplyStatus = app.HMRC_Reply_Status__c;
            latestInfo.documentId  = hmrcAssessmentContentDocs[0].ContentDocumentId;
            Datetime docCreatedDate = hmrcAssessmentContentDocs[0].ContentDocument.LatestPublishedVersion.CreatedDate;
            latestInfo.createdDate = docCreatedDate != null ? docCreatedDate.format('EEE dd MMM yyyy') : '';
            titleByDocumentInfo.put(latestInfo.title, latestInfo);
        }

        if(titleByDocumentInfo.get('Custom Letter') != null) data.latestDocs.add(titleByDocumentInfo.get('Custom Letter'));
        if(titleByDocumentInfo.get('Application Form') != null) data.latestDocs.add(titleByDocumentInfo.get('Application Form'));
        if(titleByDocumentInfo.get('Agent Authorisation') != null) data.latestDocs.add(titleByDocumentInfo.get('Agent Authorisation'));
        if(titleByDocumentInfo.get('Client Uploaded Doc') != null) data.latestDocs.add(titleByDocumentInfo.get('Client Uploaded Doc'));
        if(titleByDocumentInfo.get('HMRC Assessment') != null) data.latestDocs.add(titleByDocumentInfo.get('HMRC Assessment'));
        if(titleByDocumentInfo.get('Client Summary') != null) data.latestDocs.add(titleByDocumentInfo.get('Client Summary'));
        if(titleByDocumentInfo.get('DWP Status Check') != null) data.replyDocs.add(titleByDocumentInfo.get('DWP Status Check'));
        if(titleByDocumentInfo.get('C2') != null) data.replyDocs.add(titleByDocumentInfo.get('C2'));
        if(titleByDocumentInfo.get('C3') != null) data.replyDocs.add(titleByDocumentInfo.get('C3'));
        if(titleByDocumentInfo.get('C2 AGT') != null) data.replyDocs.add(titleByDocumentInfo.get('C2 AGT'));
        if(titleByDocumentInfo.get('DWP') != null) data.replyDocs.add(titleByDocumentInfo.get('DWP'));
        if(titleByDocumentInfo.get('NINO') != null) data.replyDocs.add(titleByDocumentInfo.get('NINO'));
        if(titleByDocumentInfo.get('CUSTOM') != null) data.replyDocs.add(titleByDocumentInfo.get('CUSTOM'));
        if(titleByDocumentInfo.get('Appeal') != null) data.replyDocs.add(titleByDocumentInfo.get('Appeal'));
        if(titleByDocumentInfo.get('Next Step 1') != null) data.replyDocs.add(titleByDocumentInfo.get('Next Step 1'));
        if(titleByDocumentInfo.get('Next Step 2') != null) data.replyDocs.add(titleByDocumentInfo.get('Next Step 2'));
        if(titleByDocumentInfo.get('Annual Service') != null) data.replyDocs.add(titleByDocumentInfo.get('Annual Service'));
        //if(titleByDocumentInfo.get('Bank Transfer') != null) data.replyDocs.add(titleByDocumentInfo.get('Bank Transfer'));
        if(titleByDocumentInfo.get('Private Pensions') != null) data.replyDocs.add(titleByDocumentInfo.get('Private Pensions'));
        if(titleByDocumentInfo.get('APPEAL') != null) data.replyDocs.add(titleByDocumentInfo.get('APPEAL'));
        if(titleByDocumentInfo.get('CUSTOM reply') != null) data.replyDocs.add(titleByDocumentInfo.get('CUSTOM reply'));
        if(titleByDocumentInfo.get('NINO reply') != null) data.replyDocs.add(titleByDocumentInfo.get('NINO reply'));
        if(titleByDocumentInfo.get('CURRENT JOB') != null) data.replyDocs.add(titleByDocumentInfo.get('CURRENT JOB'));
        if(titleByDocumentInfo.get('EU Residency Appeal') != null) data.replyDocs.add(titleByDocumentInfo.get('EU Residency Appeal'));
        if(titleByDocumentInfo.get('PENALTY') != null) data.replyDocs.add(titleByDocumentInfo.get('PENALTY'));
        if(titleByDocumentInfo.get('2024ANNUAL') != null) data.replyDocs.add(titleByDocumentInfo.get('2024ANNUAL'));
        if(titleByDocumentInfo.get('64-8 Update Letter') != null) data.replyDocs.add(titleByDocumentInfo.get('64-8 Update Letter'));
        if(titleByDocumentInfo.get('Bounce Letter') != null) data.replyDocs.add(titleByDocumentInfo.get('Bounce Letter'));

        data.application = app;
        PreviousUKAddressData latestAddress = new PreviousUKAddressData();
        latestAddress.addressData = app.Last_UK_Home_Address__Street__s + ', ' + app.Last_UK_Home_Address__City__s + ', ' +
                                    app.Last_UK_Home_Address__PostalCode__s + ', ' + app.Last_UK_Home_Address_Country__c;
        latestAddress.numberOfAddress =  1;
        data.latestUKAddress = latestAddress;
        for (Integer i = 1; i <= 5; i++) {
            if (app.get('Previous_UK_Address_' + i + '__Street__s') != null) {
                PreviousUKAddressData prevAddress = new PreviousUKAddressData();
                prevAddress.addressData =
                    app.get('Previous_UK_Address_' + i + '__Street__s') + ', ' +
                    app.get('Previous_UK_Address_' + i + '__City__s') + ', ' +
                    app.get('Previous_UK_Address_' + i + '__PostalCode__s') +  ', ' +
                    app.get('Previous_UK_Address_' + i + '_Country__c');
                prevAddress.checkboxFieldName = 'Include_UK_Address' + i +'__c';
                prevAddress.addToCustomLetter = (Boolean)app.get(prevAddress.checkboxFieldName);
                prevAddress.numberOfAddress = i + 1;
                data.previousAddresses.add(prevAddress);
            }
        }
        if (app.Type_Of_Employment__c == 'Not employed') {
            data.abroadEmployers = null;
        } else if (app.Type_Of_Employment__c != 'Not employed' && !afterUKEmployers.isEmpty()) {
            for (Integer i = 0; i < afterUKEmployers.size(); i++) {
                EmployerData abroadEmplolyer = new EmployerData();
                abroadEmplolyer.employerName = afterUKEmployers[i].Employer_Name__c;
                abroadEmplolyer.startDate = afterUKEmployers[i]?.Start_Date__c != null ? ((Datetime)afterUKEmployers[i]?.Start_Date__c).format('EEE dd MMM yyyy') : '';
                abroadEmplolyer.endDate =  afterUKEmployers[i]?.End_Date__c == null ? '' : ((Datetime)afterUKEmployers[i]?.End_Date__c).format('EEE dd MMM yyyy');
                if (afterUKEmployers[i].Type_Of_After_UK_Employment__c == 'Employed') {
                    abroadEmplolyer.isEmployedType = true;
                    abroadEmplolyer.employerType = 'Employed';
                    abroadEmplolyer.addressData = (String) afterUKEmployers[i].Employers_Address__Street__s  + ', ' +
                                                  ((String) afterUKEmployers[i].Employers_Address__City__s == null ? '' : (String) afterUKEmployers[i].Employers_Address__City__s + ', ' ) +
                                                  ((String) afterUKEmployers[i].Employers_Address__PostalCode__s == null ? '' : (String) afterUKEmployers[i].Employers_Address__PostalCode__s + ', ' ) +
                                                  (String) afterUKEmployers[i].Employers_Address__CountryCode__s;
                    abroadEmplolyer.currentWork = afterUKEmployers[i].Current_Work__c == 'Yes' ? true : false;
                } else if (afterUKEmployers[i].Type_Of_After_UK_Employment__c == 'Career Break') {
                    abroadEmplolyer.isEmployedType = false;
                    abroadEmplolyer.employerType = 'Career Break';
                } else if (afterUKEmployers[i].Type_Of_After_UK_Employment__c == 'Self-Employed') {
                    abroadEmplolyer.isEmployedType = false;
                    abroadEmplolyer.employerType = 'Self-Employed';
                } else if (afterUKEmployers[i].Type_Of_After_UK_Employment__c == 'Unemployed') {
                    abroadEmplolyer.isEmployedType = false;
                    abroadEmplolyer.employerType = 'Unemployed';
                } else if (afterUKEmployers[i].Type_Of_After_UK_Employment__c == 'Family Carer') {
                    abroadEmplolyer.isEmployedType = false;
                    abroadEmplolyer.employerType = 'Family Carer';
                } else if (afterUKEmployers[i].Type_Of_After_UK_Employment__c == 'Homemaker') {
                    abroadEmplolyer.isEmployedType = false;
                    abroadEmplolyer.employerType = 'Homemaker';
                } else if (afterUKEmployers[i].Type_Of_After_UK_Employment__c == 'Disabled') {
                    abroadEmplolyer.isEmployedType = false;
                    abroadEmplolyer.employerType = 'Disabled';
                } else if (afterUKEmployers[i].Type_Of_After_UK_Employment__c == 'Retired') {
                    abroadEmplolyer.isEmployedType = false;
                    abroadEmplolyer.employerType = 'Retired';
                } else if (afterUKEmployers[i].Type_Of_After_UK_Employment__c == 'Education') {
                    abroadEmplolyer.isEmployedType = false;
                    abroadEmplolyer.employerType = 'Education';
                } else if (afterUKEmployers[i].Type_Of_After_UK_Employment__c == 'Illness') {
                    abroadEmplolyer.isEmployedType = false;
                    abroadEmplolyer.employerType = 'Illness';
                }

                abroadEmplolyer.numberOfEmployer = i;
                abroadEmplolyer.employerId = afterUKEmployers[i].Id;
                String checkboxName = 'Include_Abroad_Employer' + i + '__c';
                abroadEmplolyer.checkboxFieldName = checkboxName;
                abroadEmplolyer.includeEmployer = afterUKEmployers[i].Add_to_custom_letter__c;
                data.abroadEmployers.add(abroadEmplolyer);
            }
        }

        EmployerData lastUKEmployer = new EmployerData();
        if (app.Type_Of_Employment__c == 'Not employed') {
            lastUKEmployer = null;
        } else if(!app.Employers__r.isEmpty() && app.Type_Of_Employment__c != 'Not employed'){
            lastUKEmployer.employerName = app.Employers__r[0].Type_Of_UK_Employment__c == 'Employed' ?
            app.Employers__r[0].Employer_Name__c :
            app.Employers__r[0].Type_Of_UK_Employment__c;
            lastUKEmployer.startDate = app.Employers__r[0].Start_Date__c != null ?
                ((Datetime)app.Employers__r[0].Start_Date__c).format('EEE dd MMM yyyy') :
                null;
            lastUKEmployer.endDate   = app.Employers__r[0].End_Date__c != null ?
                ((Datetime)app.Employers__r[0].End_Date__c).format('EEE dd MMM yyyy') :
                null;
            lastUKEmployer.addressData = app.Employers__r[0].Type_Of_UK_Employment__c == 'Employed' ?
                app.Last_UK_Employer_Address__Street__s + ', ' +
                app.Last_UK_Employer_Address__City__s + ', ' +
                app.Last_UK_Employer_Address__PostalCode__s + ', ' +
                app.Last_UK_Employer_Address_Country__c :
                '';
            data.lastUKEmployer = lastUKEmployer;
        }
        return data;
    }

    @AuraEnabled
    public static String changeCustomLetter(CustomLetterData letterData) {
        try {
            Application__c updateApplication = new Application__c(
                Id = letterData?.applicationId,
                Freeform_RichText_Line1__c = letterData?.freeformTextLine1,
                Freeform_RichText_Line2__c = letterData?.freeformTextLine2,
                Freeform_RichText_Line3__c = letterData?.freeformTextLine3,
                Freeform_RichText_Line4__c = letterData?.freeformTextLine4,
                Freeform_RichText_Line5__c = letterData?.freeformTextLine5,
                Custom_Letter_Date__c  = letterData?.customLetterDate
            );
            if (!letterData.newEmployerData.isEmpty()) {
                List<Id> changedEmployersIds = new List<Id>();
                for (ChangedDataWrapper wrapper : letterData?.newEmployerData) {
                    changedEmployersIds.add(wrapper?.employerId);
                }
                if (!changedEmployersIds.isEmpty()) {
                    Map<Id, Employer__c> changedEmployers = new Map<Id, Employer__c>([
                        SELECT Add_to_custom_letter__c
                        FROM Employer__c
                        WHERE Id IN :changedEmployersIds
                    ]);
                    for (ChangedDataWrapper wrapper : letterData?.newEmployerData) {
                        Employer__c currentEmployer = changedEmployers.get(wrapper?.employerId);
                        if (currentEmployer != null) {
                            currentEmployer.Add_to_custom_letter__c = Boolean.valueOf(wrapper?.value);
                        } else continue;
                    }
                    update changedEmployers.values();
                }
            }
            if (!letterData.newPreviousAddressData.isEmpty()) {
                for (ChangedDataWrapper wrapper : letterData?.newPreviousAddressData) {
                    updateApplication.put(wrapper?.fieldName, Boolean.valueOf(wrapper?.value));
                }

            }
            update updateApplication;
            return 'true';
        } catch (Exception ex) {
            return ex.getMessage();
        }
    }

    @AuraEnabled
    public static String pdfAction(String applicationId) {
        List<Application__c> currentApplication = [
            SELECT
                First_Name__c,
                Second_Name__c,
                Name,
                    (SELECT
                        ContentDocumentId,
                        ContentDocument.Title,
                        ContentDocument.CreatedDate,
                        LinkedEntityId
                    FROM ContentDocumentLinks
                    WHERE ContentDocument.Title LIKE '%CustomLetter_ForSignature%'
                    LIMIT 1)
            FROM Application__c
            WHERE Id = :applicationId
        ];
        if (currentApplication.size() == 0) {
            return 'Didn\'t find any apps';
        }
        Application__c app = currentApplication[0];
        PageReference savepage ;
        savepage = Page.CustomLetter;
        savepage.getParameters().put('id', applicationId);
        blob pdfBlob;
        if (!Test.isRunningTest()) {
            pdfBlob = savepage.getContent();
        } else {
            pdfBlob = Blob.valueOf('Test');
        }
        ContentVersion conVer = createContentVerison(
            pdfBlob,
            app.First_Name__c + '_' + app.Second_Name__c + '_' + app.Name + '_CustomLetter_ForSignature'
        );
        if(app.ContentDocumentLinks.size() != 0) {
            conVer.ContentDocumentId = app.ContentDocumentLinks[0].ContentDocumentId;
        }
        insert conVer;
        if(app.ContentDocumentLinks.size() == 0) {
            List<ContentVersion> conDocs = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id = :conVer.Id
            ];
            if (conDocs.size() > 0) {
                insert new ContentDocumentLink(
                        LinkedEntityId = app.Id,
                        ContentDocumentId = conDocs[0].ContentDocumentId,
                        shareType = 'V',
                        Visibility = 'AllUsers'
                );
            }
        }
        return 'Success';
    }

    private static ContentVersion createContentVerison(Blob pdfBlob, String title) {
        return new ContentVersion(
            VersionData = pdfBlob,
            ContentLocation = 'S',
            PathOnClient = title +'.pdf',
            Title = title
        );
    }

    @AuraEnabled
    public static SendEmailResultWrapper sendHMRCResult(ResultEmailDataWrapper emailData) {
        SendEmailResultWrapper result = new SendEmailResultWrapper();
        if (emailData == null) {
            result.isSuccess = false;
            result.errorMessage = 'Input data is empty';
        }
        String appId = emailData.applicationId;
        if (appId == null) {
            result.isSuccess = false;
            result.errorMessage = 'Application Id is null';
        }
        List<Application__c> apps = [
            SELECT
                Contact__c,
                Email__c,
                Status__c, 
                Current_Address_Abroad__CountryCode__s
            FROM Application__c
            WHERE Id = :appId
        ];
        if (apps.isEmpty()) {
            result.isSuccess = false;
            result.errorMessage = 'Didn\'t find application with this Id';
        }
        Application__c app = apps[0];
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setTargetObjectId(app.Contact__c);
        message.setUseSignature(false);
        message.setBccSender(false);
        message.setSaveAsActivity(true);
        message.setTreatTargetObjectAsRecipient(false);
        message.setHtmlBody(
            '<html style="overflow-y: hidden;">' +
                '<head>' +
                    '<title>HRMC RESULT</title>' +
                    '<style type="text/css">' +
                        '* {' +
                            'margin: 0px;' +
                            'padding: 0px;' +
                            'box-sizing: border-box;' +
                            'text-decoration: none;' +
                        '}' +
                        '.main-container p{' +
                            'font-family: "Roboto", sans-serif;' +
                            'color: #000000;' +
                            'font-size: 1.0rem;' +
                            'line-height: 1.4;' +
                            'font-variant: normal;' +
                            'font-style: normal;' +
                            'max-width: 1000px;' +
                            'overflow: hidden;' +
                            'scroll-behavior: smooth;' +
                            'height: auto;' +
                            'width: 100%;' +
                            'background-color: #fff;' +
                            'display: grid;' +
                            'padding-left: 1rem;' +
                            'padding-right: 1rem;' +
                        '}' +
                        'ul, li {' +
                            'font-family: "Roboto", sans-serif;' +
                            'font-size: 1.0rem;' +
                            'margin-left: 0.8rem;' +
                            'list-style-type: disc;' +
                            'padding-left: 1rem;' +
                            'padding-right: 1rem;' +
                        '}' +
                        'a {' +
                            'font-family: "Roboto", sans-serif;' +
                            'font-size: 1.0rem;' +
                            'color: #1aa2b0;' +
                        '}' +
                        'p, ul {' +
                            'margin-bottom: 0px;' +
					        'margin-top: 0px;' +
                        '}'+
                    '</style>' +
                '</head>' +
                '<body>' +
                    '<div class="main-container">' +
                        emailData?.htmlBody +
                    '</div>' +
                '</body>' +
            '</html>'
        );
        message.setSubject(emailData?.subject);
        message.setWhatId(app.Id);
        if ( DEFAULT_ORG_WIDE_EMAIL_ADDRESS != null) {
            message.setOrgWideEmailAddressId(DEFAULT_ORG_WIDE_EMAIL_ADDRESS.Id);
        }

        List<String> conDocIds = emailData?.documentsIds;
        List<ContentDocument> docs = [
            SELECT
                LatestPublishedVersion.VersionData,
                LatestPublishedVersion.Title
            FROM ContentDocument
            WHERE Id IN :conDocIds
        ];

        String[] attachDocIds = new List<String>();
        for (ContentDocument doc : docs) {
            if (app.Current_Address_Abroad__CountryCode__s == 'IE' && doc.LatestPublishedVersion.Title.contains('Private Pensions')) continue;
            attachDocIds.add(doc.LatestPublishedVersionId);
        }
        if (TRANSFER_UK_PENSION_ATTACH_FILE != null && app.Current_Address_Abroad__CountryCode__s == 'IE') {
            ContentVersion contVersAttacment = new ContentVersion (
                VersionData = TRANSFER_UK_PENSION_ATTACH_FILE.Body,
                PathOnClient = TRANSFER_UK_PENSION_ATTACH_FILE.Description + '.pdf'
            );
            insert contVersAttacment;
            ContentVersion conDoc = [
                SELECT
                    ContentDocumentId,
                    ContentSize
                FROM ContentVersion
                WHERE Id =:contVersAttacment.Id][0];
            ContentDocumentLink conDocStep2Link = new ContentDocumentLink();
            conDocStep2Link.LinkedEntityId = app.Id;
            conDocStep2Link.ContentDocumentId = conDoc.ContentDocumentId;
            conDocStep2Link.shareType = 'V';
            conDocStep2Link.Visibility = 'AllUsers';
            insert conDocStep2Link;
            attachDocIds.add(contVersAttacment.Id);
        }
        if (!attachDocIds.isEmpty()) {
            message.setEntityAttachments(attachDocIds);
        }
        message.toAddresses = new String[] { app.Email__c };
        Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
        Messaging.SendEmailResult[] sendingResults = Messaging.sendEmail(messages);
        Boolean isSuccess = true;
        for (Messaging.SendEmailResult sendingResult : sendingResults) {
            if (sendingResult.isSuccess() == false) {
                isSuccess = false;
            }
        }
        if (isSuccess == true) {
            app.Status__c = HMRC_RESULT_STATUS;
            update app;
        }
        result.isSuccess = true;
        return result;
    }

    @AuraEnabled(cacheable=false)
    public static void sendMissingApplicationPaymentEmail(Id appId) {
        if (appId == null) return;
        List<Application__c> apps = [
            SELECT
                Contact__c,
                Name,
                First_Name__c,
                Second_Name__c,
                Missing_App_Payment_Email_Send_Date__c
            FROM Application__c
            WHERE Id = :appId
            LIMIT 1
        ];
        if (apps.size() == 0) return;
        Application__c app = apps[0];
        if (app.Missing_App_Payment_Email_Send_Date__c != null) return;
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setTargetObjectId(app.Contact__c);
        message.setUseSignature(false);
        message.setBccSender(false);
        message.setSaveAsActivity(true);
        message.setTreatTargetObjectAsRecipient(false);
        message.setHtmlBody('<div></div>');
        message.setSubject(app.Name + ' - ' + app.First_Name__c + ' ' + app.Second_Name__c + ' - Application Fee NOT PAID.');
        message.setWhatId(app.Id);
        if (DEFAULT_ORG_WIDE_EMAIL_ADDRESS != null) {
            message.setOrgWideEmailAddressId(DEFAULT_ORG_WIDE_EMAIL_ADDRESS.Id);
        }
        message.toAddresses = new String[] { MISSING_APPLICATION_PAYMENT_RECIPIENT_ADDRESS };
        Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
        Messaging.SendEmailResult[] sendingResults = Messaging.sendEmail(messages);
        Boolean isSuccess = true;
        for (Messaging.SendEmailResult sendingResult : sendingResults) {
            if (sendingResult.isSuccess() == false) {
                isSuccess = false;
            }
        }
        if (isSuccess == true) {
            app.Missing_App_Payment_Email_Send_Date__c = Date.today();
            update app;
        }
    }

    public class DocumentsData {
        @AuraEnabled
        public List<DocumentInfo> latestDocs{get; set;}
        @AuraEnabled
        public List<DocumentInfo> replyDocs{get; set;}
        @AuraEnabled
        public Application__c application{get; set;}
        @AuraEnabled
        public PreviousUKAddressData latestUKAddress{get; set;}
        @AuraEnabled
        public List<PreviousUKAddressData> previousAddresses{get; set;}
        @AuraEnabled
        public EmployerData lastUKEmployer{get; set;}
        @AuraEnabled
        public List<EmployerData> abroadEmployers{get; set;}
        @AuraEnabled
        public Boolean isSendToClientAppStatus{get; set;}
        @AuraEnabled
        public Boolean isPaidApplicationPayment{get; set;}
        @AuraEnabled
        public ResultEmailTemplate templateData{get; set;}
    }

    public class EmployerData {
        @AuraEnabled
        public String startDate{get; set;}
        @AuraEnabled
        public String endDate{get; set;}
        @AuraEnabled
        public String employerName{get; set;}
        @AuraEnabled
        public String addressData {get; set;}
        @AuraEnabled
        public Integer numberOfEmployer {get; set;}
        @AuraEnabled
        public Boolean includeEmployer {get; set;}
        @AuraEnabled
        public String checkboxFieldName{get; set;}
        @AuraEnabled
        public String employerId{get; set;}
        @AuraEnabled
        public Boolean isEmployedType{get; set;}
        @AuraEnabled
        public Boolean currentWork {get; set;}
        @AuraEnabled
        public String employerType{get; set;}
    }

    public class PreviousUKAddressData {
        @AuraEnabled
        public String addressData{get; set;}
        @AuraEnabled
        public Boolean addToCustomLetter{get; set;}
        @AuraEnabled
        public Integer numberOfAddress{get; set;}
        @AuraEnabled
        public String checkboxFieldName{get; set;}
    }

    public class AllDocumentsData {
        @AuraEnabled
        public List<DocumentInfo> allDocs{get; set;}
    }

    public class DocumentInfo {
        @AuraEnabled
        public String title;
        @AuraEnabled
        public String documentId;
        @AuraEnabled
        public String createdDate;
        @AuraEnabled
        public Boolean isCustomLetter;
        @AuraEnabled
        public Boolean isHMRCReply;
        @AuraEnabled
        public Boolean isApplicationForm = false;
        @AuraEnabled
        public Boolean isAgentAuthorisation = false;
        @AuraEnabled
        public String hmrcReplyStatus;
        @AuraEnabled
        public Boolean isCompleteDocusignStatus = false;
    }

    public class CustomLetterData {
        @AuraEnabled
        public String applicationId{get; set;}
        @AuraEnabled
        public String freeformTextLine1{get; set;}
        @AuraEnabled
        public String freeformTextLine2{get; set;}
        @AuraEnabled
        public String freeformTextLine3{get; set;}
        @AuraEnabled
        public String freeformTextLine4{get; set;}
        @AuraEnabled
        public String freeformTextLine5{get; set;}
        @AuraEnabled
        public Date customLetterDate{get; set;}
        @AuraEnabled
        public List<ChangedDataWrapper> newPreviousAddressData{get; set;}
        @AuraEnabled
        public List<ChangedDataWrapper> newEmployerData{get; set;}
    }

    public class ChangedDataWrapper {
        @AuraEnabled
        public String fieldName{get; set;}
        @AuraEnabled
        public String value{get; set;}
        @AuraEnabled
        public String employerId{get; set;}
    }

    public class DocusingEnvelopeStatus {
        public String cf083DocStatus;
        public String agentDocStatus;
    }

    public class ResultEmailTemplate {
        @AuraEnabled
        public String successTemplate{get; set;}
        @AuraEnabled
        public String emailSubject{get; set;}
        @AuraEnabled
        public String rejectTempalte{get; set;}
    }

    public class ResultEmailDataWrapper {
        @AuraEnabled
        public String applicationId{get; set;}
        @AuraEnabled
        public String htmlBody{get; set;}
        @AuraEnabled
        public String subject{get; set;}
        @AuraEnabled
        public List<String> documentsIds{get; set;}
    }

    public class SendEmailResultWrapper {
        @AuraEnabled
        public Boolean isSuccess{get; set;}
        @AuraEnabled
        public String errorMessage{get; set;}
        @AuraEnabled
        public String successMessage{get; set;}
    }
}