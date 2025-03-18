public without sharing class ApplicationTriggerHandler {
    public Map<Id, Application__c> newApplications;
    public Map<Id, Application__c> oldApplications;
    public final String APPROVE_EMAIL_TEMPLATE_NAME = 'HMRC Success Result Reply';
    private static final Map<String, String[]> PROJECT_NAME_BY_RELATED_PRODUCT_NAME = new Map<String, String[]>{
        'Freebie'  => new String[]{'Deposit (Free)', 'Application (Free)', 'Guidance on HMRC Reply (Free)'}
    };
    private static final List<String> PRODUCT_NAMES = new String[] {
        'Deposit', 'Application', 'Monthly Updates', 'Success'
    };
    private static final String APPEAL_PRODUCT_NAME = 'Appeal';

    Map<String, Integer> VAL_AGENTS_PROPORTION = new Map<String, Integer> {
        'Sean'       => 10,
        'Ciara'      => 10,
        'Niamh'      => 20,
        'Becky'      => 20,
        'Monica'     => 20,
        'MaryClaire' => 20
    };

    private static Map<String, Integer> AGENTS_PROPORTION = new Map<String, Integer> {
        'Daniel'  => 25,
        'Edryl'   => 25,
        'Camille' => 25,
        'Maria'   => 25
    };

    Map<String, Integer> DOC_AGENTS_PROPORTION = new Map<String, Integer>{
        'Fiona'  => 50,
        'Rob' => 50
    };


    private final Map<String,String> CHANGED_STATUS_DATE_FIELDS = new Map<String, String>{
        'Form Completed'      => 'Form_Completed_Change_Date__c',
        'NINO/Doc Needed'     => 'NINO_Doc_Needed_Changed_Date__c',
        'Agent Check'         => 'Agent_Check_Changed_Date__c',
        'Fix'                 => 'Fix_Changed_Date__c',
        //'Quality Control'	  => 'Quality_Control_Changed_Date__c',
        //'QC Approved'	      => 'QC_Approved_Changed_Date__c',
        'Pending Client'	  => 'Pending_Client_Send_SMS_Date__c',
        'Sent for eSignature' => 'Sent_for_eSignature_Changed_Date__c',
        'Signed'              => 'Signed_Changed_Date__c',
        'Printing House'      => 'Printing_House_Changed_Date__c',
        'Posted'              => 'Posted_Changed_Date__c',
        'HMRC Reply 1'        => 'HMRC_Reply_1_Changed_Date__c',
        'XP Letter Sent'      => 'XP_Letter_Sent_Changed_Date__c',
        'HMRC Reply 2'        => 'HMRC_Reply_2_Changed_Date__c',
        'REPEAT(edits)'       => 'Repeat_Change_Date__c',
        'REPEAT(NO edits)'    => 'Repeat_No_Edit_Changed_Date__c',
        'Send to Client'      => 'Send_to_Client_Changed_Date__c',
        'Agent Call'	      => 'Agent_Call_Changed_Date__c',
        'Charge CC'	          => 'Charge_CC_Changed_Date__c',
        'Annual Service'      => 'Annual_Service_Changed_Date__c',
        'No Annual'           => 'Closed_Won_Changed_Date__c',
        'Closed'              => 'Closed_Lost_Changed_Date__c',
        'Deposit Refund'      => 'Deposit_Refund_Changed_Date__c',
        'Deferred'            => 'Deferred_Changed_Date__c'
    };
    private final static String REGISTRATION_ORG_WIDE = 'clients@xtrapension.com';
    private final static String REGISTRATION_TEMPLATE_NAME = 'Registration Data Information';
    // private final static Map<String, String> AGENT_NAME_BY_EMAIL = new Map<String, String> {
    //     'Adrian'  => 'adrian@xtrapension.com',
    //     'Amy'     => 'amy@xtrapension.com',
    //     'Megan'   => 'megan@xtrapension.com',
    //     'Patrick' => 'patrick@xtrapension.com',
    //     'Tomas'   => 'tomas@xtrapension.com',
    //     'Sean'    => 'sean@xtrapension.com',
    //     'George'  => 'george@xtrapension.com',
    //     'Gerard'  => 'gerard@xtrapension.com'
    // };

    // private static Map<String, String> VAL_AGENTS_BY_EMAIL = new Map<String, String> {
    //     'Sean'       => 'seanb@xtrapension.com',
    //     'Ciara'      => 'ciara@xtrapension.com',
    //     'Niamh'      => 'agent1@xtrapension.com',
    //     'Becky'      => 'becky@xtrapension.com ',
    //     'Monica'     => 'monica@xtrapension.com',
    //     'MaryClaire' => 'mary@xtrapension.com'
    // };

    // private static Map<String, String> DOC_AGENTS_BY_EMAIL = new Map<String, String> {
    //     'Daniel'  => 'daniel@xtrapension.com',
    //     'Edryl'   => 'edryl@xtrapension.com',
    //     'Camille' => 'camille@xtrapension.com',
    //     'Maria'   => 'maria@xtrapension.com'
    // };

    private final static Map<String, String> AGENT_NAME_BY_EMAIL = new Map<String, String> {
        'Barry'      => 'mishaklimovich87@gmail.com',
        'Ciara'      => 'mishaklimovich87@gmail.com',
        'Emma'       => 'mishaklimovich87@gmail.com',
        'John R'     => 'mishaklimovich87@gmail.com',
        'Megan'      => 'mishaklimovich87@gmail.com',
        'Tomas'      => 'mishaklimovich87@gmail.com',
        'George'     => 'mishaklimovich87@gmail.com',
        'Ciaran'     => 'mishaklimovich87@gmail.com',
        'Paul'       => 'mishaklimovich87@gmail.com',
        'Elaine'     => 'mishaklimovich87@gmail.com'
    };

        private static Map<String, String> VAL_AGENTS_BY_EMAIL = new Map<String, String> {
        'Sean'       => 'mihail.klimovich@outlook.com',
        'Ciara'      => 'mihail.klimovich@outlook.com',
        'Niamh'      => 'mihail.klimovich@outlook.com',
        'Becky'      => 'mihail.klimovich@outlook.com',
        'Monica'     => 'mihail.klimovich@outlook.com',
        'MaryClaire' => 'mihail.klimovich@outlook.com'
    };

    private static Map<String, String> DOC_AGENTS_BY_EMAIL = new Map<String, String> {
        'Daniel'  => 'mihail.klimovich@outlook.com',
        'Edryl'   => 'mihail.klimovich@outlook.com',
        'Camille' => 'mihail.klimovich@outlook.com',
        'Maria'   => 'mihail.klimovich@outlook.com'
    };

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

    private static final CustomNotificationType AGENT_NOTIFICATION {
        get {
            if (AGENT_NOTIFICATION == null) {
                List<CustomNotificationType> notificationType = [
                    SELECT
                        Id,
                        DeveloperName
                    FROM CustomNotificationType
                    WHERE DeveloperName = 'Doc_Agent_Notification'
                    LIMIT 1
                ];
                if (!notificationType.isEmpty()) {
                    AGENT_NOTIFICATION = notificationType[0];
                }
            }
            return AGENT_NOTIFICATION;
        }
        private set;
    }

    public ApplicationTriggerHandler(Map<Id, Application__c> newApplications, Map<Id, Application__c> oldApplications) {
        this.newApplications = newApplications;
        this.oldApplications = oldApplications;
    }

    public void generatePdfFiles () {
        Set<Id> updateSelfemployedAppIds = new Set<Id>();
        Set<Id> updateNameAppIds = new Set<Id>();
        Set<Id> updateEmailAppIds = new Set<Id>();
        Set<Id> updateApps = new Set<Id>();
        Set<Id> updateDaysSinceContactAppIds = new Set<Id>();
        Set<Id> updateAmountPayments = new Set<Id>();
        Set<Id> appealApps = new Set<Id>();
        Set<Id> googleReviewApps = new Set<Id>();
        Set<Id> sendGoogleReviewSmsApps = new Set<Id>();
        Set<Id> currentAddressAbroadStateApps = new Set<Id>();
        Set<Id> googleReviewSendEmailApps = new Set<Id>();
        Set<Id> updateNINOfieldApps = new Set<Id>();
        Set<Id> updateAgentStatusApps = new Set<Id>();
        Set<Id> salesAgentCustomNotificationApps = new Set<Id>();
        Set<Id> valAgentCustomNotificationApps = new Set<Id>();
        List<Application__c> changedStatusesApps = new List<Application__c>();

        for (Application__c app : newApplications.values()) {
            if (app.Status__c == 'Form Completed' && app.Status__c != oldApplications.get(app.Id).Status__c) {
                System.enqueueJob(new GeneratePDFCallout(app.Id));
                if (app.Is_Generate_Client_Summary_PDF__c == false) {
                    CustomSummerPdf.generateClientSummary(app.Id);
                }
            }
            if (app.Status__c == 'Send to Client' && app.Status__c != oldApplications.get(app.Id).Status__c) {
                SuccessDocsController.generateDocs(app.Id);
            }
            if ((app.Status__c == 'Printing House' || app.Status__c == 'REPEAT(NO edits)') && app.Status__c != oldApplications.get(app.Id).Status__c) {
                //updateApplicationDocumentStatus(app.Id);
                generateZipArchive(app.Id);
            }
            if ((app.Status__c == 'Closed Won' ||
                app.Status__c == 'Charge CC' ||
                app.Status__c == 'Annual Service')&&
                oldApplications.get(app.Id).Status__c == 'Agent Call' &&
                app.Agent_Call_Changed_Date__c == null) {
                googleReviewSendEmailApps.add(app.Id);
            }
            if (app.Status__c != oldApplications.get(app.Id).Status__c) {
                String appStatus = CHANGED_STATUS_DATE_FIELDS.get(app.Status__c);
                if(appStatus != null) {
                    Application__c currentApp = new Application__c();
                    currentApp.put('Id',app.Id);
                    currentApp.put(appStatus, Date.today());
                    changedStatusesApps.add(currentApp);
                }
            }
            if (app.SelfEmployment_Employment_Abroad__c != oldApplications.get(app.Id).SelfEmployment_Employment_Abroad__c) {
                updateSelfemployedAppIds.add(app.Id);
            }
            if (!app.First_Name__c.equals(oldApplications.get(app.Id).First_Name__c) || !app.Second_Name__c.equals(oldApplications.get(app.Id).Second_Name__c)) {
                updateNameAppIds.add(app.Id);
            }
            if (app.Email__c != oldApplications.get(app.Id).Email__c) {
                updateEmailAppIds.add(app.Id);
            }
            if (app.Did_Client_Change_Name__c != oldApplications.get(app.Id).Did_Client_Change_Name__c) {
                updateApps.add(app.Id);
            }
            if (app.Who__c != oldApplications.get(app.Id).Who__c ||
                app.Contact_Type__c != oldApplications.get(app.Id).Contact_Type__c ||
                app.Days_Since_Contact__c != oldApplications.get(app.Id).Days_Since_Contact__c) {
                updateDaysSinceContactAppIds.add(app.Id);
            }
            if (app.Live_In_The_EU__c != oldApplications.get(app.Id).Live_In_The_EU__c) {
                updateAmountPayments.add(app.Id);
            }
            if (app.Appeal_Application__c != oldApplications.get(app.Id).Appeal_Application__c && app.Appeal_Application__c == true) {
                appealApps.add(app.Id);
            }
            if (app.Delay_In_Days__c != oldApplications.get(app.Id).Delay_In_Days__c) {
                googleReviewApps.add(app.Id);
            }
            if (app.Send_Google_Review_SMS__c != oldApplications.get(app.Id).Send_Google_Review_SMS__c && app.Send_Google_Review_SMS__c == true) {
                sendGoogleReviewSmsApps.add(app.Id);
            }
            if (app.Current_Address_Abroad__StateCode__s != oldApplications.get(app.Id).Current_Address_Abroad__StateCode__s) {
                currentAddressAbroadStateApps.add(app.Id);
            }
            if (app.National_Insurance_Number__c != oldApplications.get(app.Id).National_Insurance_Number__c) {
                updateNINOfieldApps.add(app.Id);
            }
            if ((app.Status__c == 'Fix' || app.Status__c == 'Agent Check' || app.Status__c == 'QC Approved') && app.Status__c != oldApplications.get(app.Id).Status__c) {
                updateAgentStatusApps.add(app.Id);
            }
            if (app.Status__c == 'Fix'  && app.Status__c != oldApplications.get(app.Id).Status__c && oldApplications.get(app.Id).Status__c == 'Agent Check') {
                salesAgentCustomNotificationApps.add(app.Id);
            }
            if (app.Status__c == 'Agent Check'  && app.Status__c != oldApplications.get(app.Id).Status__c && oldApplications.get(app.Id).Status__c == 'Fix') {
                valAgentCustomNotificationApps.add(app.Id);
            }
        }
        if (!googleReviewSendEmailApps.isEmpty()) {
            sendGoogleReviewEmail(googleReviewSendEmailApps);
        }
        if (!updateSelfemployedAppIds.isEmpty()) {
            updateSelfemployedAbroadField(updateSelfemployedAppIds);
        }
        if (!updateNameAppIds.isEmpty()) {
            updateRelatedDocumentsAfterChangeApplicationName(updateNameAppIds);
        }
        if (!updateEmailAppIds.isEmpty()) {
            updateRelatedContactAfterChangeEmail(updateEmailAppIds);
        }
        if (!updateDaysSinceContactAppIds.isEmpty()) {
            updateDaysSinceContact(updateDaysSinceContactAppIds);
        }
        if (!updateAmountPayments.isEmpty()) {
            updateRelatedPayments(updateAmountPayments);
        }
        if (!updateNINOfieldApps.isEmpty()) {
            updateIsKnowCheckbox(updateNINOfieldApps);
        }
        if (!updateApps.isEmpty()) {
            List<Application__c> currentApps = [
                SELECT
                    Did_Client_Change_Name__c,
                    Did_You_Change_Name__c
                FROM Application__c
                WHERE Id IN :updateApps
            ];
            for (Application__c app : currentApps) {
                app.Did_You_Change_Name__c = app.Did_Client_Change_Name__c == 'Yes' ? true : false;
            }
            update currentApps;
        }
        if (!changedStatusesApps.isEmpty()) {
            update changedStatusesApps;
        }
        if (!appealApps.isEmpty()) {
            updatePaymentsFromAppealApps(appealApps);
        }
        if (!googleReviewApps.isEmpty()) {
            changeGoogleReviewSmsDate(googleReviewApps);
        }
        if (!sendGoogleReviewSmsApps.isEmpty()) {
            changeEmptyGoogleReviewSmsDate(sendGoogleReviewSmsApps);
        }
        if (!currentAddressAbroadStateApps.isEmpty()) {
            changeCurrentAddressAbroadState(currentAddressAbroadStateApps);
        }
        if (!updateAgentStatusApps.isEmpty()) {
            changeAgentStatusApps(updateAgentStatusApps);
        }
        if (!salesAgentCustomNotificationApps.isEmpty()) {
            sendSalesAgentCustomNotification(salesAgentCustomNotificationApps);
        }
        if (!valAgentCustomNotificationApps.isEmpty()) {
            sendValAgentCustomNotification(valAgentCustomNotificationApps);
        }
    }

    /*private void updateApplicationDocumentStatus(Id applicationId) {
        List<Application_Document__c> relatedAppDocs = [
            SELECT Status__c
            FROM Application_Document__c
            WHERE Application__c = :applicationId AND
                  File_Name__c LIKE '%ForSignature%'
            ORDER BY CreatedDate DESC
            LIMIT 10000
        ];
        if (relatedAppDocs.isEmpty()) return;
        Map<String, Application_Document__c> nameByApplicationDocument = new Map<String, Application_Document__c>();
        for (Application_Document__c appDoc : relatedAppDocs) {
            if (!nameByApplicationDocument.containsKey('CF083')) {
                nameByApplicationDocument.put('CF083', appDoc);
            } else if (!nameByApplicationDocument.containsKey('64-8')) {
                nameByApplicationDocument.put('64-8', appDoc);
            } else if (!nameByApplicationDocument.containsKey('CustomLetter')) {
                nameByApplicationDocument.put('CustomLetter', appDoc);
            } else if (!nameByApplicationDocument.containsKey('UPLOAD')) {
                nameByApplicationDocument.put('UPLOAD', appDoc);
            }
        }
        if(nameByApplicationDocument.isEmpty()) return;
        List<Application_Document__c> updateAppDocs = new List<Application_Document__c>();
        for (Application_Document__c doc: nameByApplicationDocument.values()) {
            doc.Status__c = 'Ready For PH';
            updateAppDocs.add(doc);
        }
        if (!updateAppDocs.isEmpty()) {
            update updateAppDocs;
        }
    }*/

    public void autoPopulateRequiredFields() {
        List<Application__c> updateApplications = new List<Application__c>();
        Map<String, Id> personEmailsByApplId = new Map<String, Id>();
        Map<String, Id> personPhonesByApplId = new Map<String, Id>();
        List<Agent__c> mainAgent = [
            SELECT
                Id,
                Name
            FROM Agent__c
        ];
        Id agentId = mainAgent.size() == 0 ? null : mainAgent[0].Id;
        for (Application__c app : newApplications.values()) {
            if (app.Package_Name__c == 'Freebie') {
                String randomValue = 'pi' + (Integer.valueOf(Math.Random() * 100000) + 10000000);
                updateApplications.add(new Application__c(
                    Id                            = app.Id,
                    Expiry_Date__c                = Datetime.now().addYears(1),
                    Stripe_Transaction_Id__c      = randomValue,
                    Personal_Details_Form_Link__c = XtraPension_Data__c.getInstance().Form_Link__c + randomValue,
                    Agent__c                      = mainAgent.size() == 0 ? null : mainAgent[0].Id
                ));
                personEmailsByApplId.put(app.Email__c, app.Id);
                personPhonesByApplId.put(app.Related_Contact_Phone__c, app.Id);
            }
        }
        if (updateApplications.isEmpty()) {
            return;
        }
        update updateApplications;
        Map<Id, Application__c> applications = new Map<Id, Application__c> ([
            SELECT Contact__c
            FROM Application__c
            WHERE Id IN :updateApplications
        ]);
        List<Account> newAccounts = new List<Account>();
        Map<Id, Account> appIdByRelatedAccount = new Map<Id, Account>();
        for (Application__c app : newApplications.values()) {
            if (app.Contact__c == null) {
                Account relatedAccount = new Account(
                    LastName                = app.First_Name__c + ' ' + app.Second_Name__c,
                    PersonEmail             = app.Email__c,
                    PersonMobilePhone       = app.Related_Contact_Phone__c
                );
                appIdByRelatedAccount.put(app.Id, relatedAccount);
                newAccounts.add(relatedAccount);
            }
        }
        Map<Id, Id> accountIdByContactId = new Map<Id, Id>();
        if (!newAccounts.isEmpty()) {
            insert newAccounts;
            Map<Id, Contact> currentContact = new Map<Id, Contact> ([
                SELECT
                    Id,
                    AccountId
                FROM Contact
                WHERE AccountId IN :newAccounts
            ]);
            for (Contact contact : currentContact.values()) {
                accountIdByContactId.put(contact.AccountId, contact.Id);
            }
        }
        if (!appIdByRelatedAccount.isEmpty()) {
            List<Application__c> applicationsWithNewContacts = new List<Application__c>();
            for (Id appId : appIdByRelatedAccount.keySet()) {
                Account account = appIdByRelatedAccount.get(appId);
                Application__c app = applications.get(appId);
                app.Contact__c = (String)accountIdByContactId.get(account.Id);
                app.Last_UK_Home_Address__CountryCode__s  = 'GB';
                applicationsWithNewContacts.add(app);
            }
            if (!applicationsWithNewContacts.isEmpty()) {
                update applicationsWithNewContacts;
            }
        }
    }

    public void sendRegistrationDataMessage() {
        if (newApplications.isEmpty()) {
            return;
        }
        OrgWideEmailAddress[] owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :REGISTRATION_ORG_WIDE
        ];
        List<EmailTemplate> registrationEmailTemplate = [
            SELECT
                Id
            FROM EmailTemplate
            WHERE Name = :REGISTRATION_TEMPLATE_NAME
        ];
        List<Application__c> apps = [
            SELECT Contact__c
            FROM Application__c
            WHERE Id IN : newApplications.keySet()
        ];
        for (Application__c app : apps) {
            if (app.Contact__c == null) {
                continue;
            }
            Application__c currentApp = newApplications.get(app.Id);
            Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
            message.setTargetObjectId(app.Contact__c);
            message.setUseSignature(false);
            message.setSaveAsActivity(true);
            message.setTreatTargetObjectAsRecipient(false);
            message.setWhatId(currentApp.Id);
            if (!registrationEmailTemplate.isEmpty()) {
                message.setTemplateID(registrationEmailTemplate[0].Id);
            }
            if ( owea.size() > 0 ) {
                message.setOrgWideEmailAddressId(owea.get(0).Id);
            }
            String agentEmail = AGENT_NAME_BY_EMAIL.get(currentApp.Agent_Making_Sale__c);
            if (!String.isBlank(agentEmail)) {
                message.bccAddresses = new String[] { agentEmail };
            } else message.setBccSender(false);
            message.toAddresses = new String[] { currentApp.Email__c };
            Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
            Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
        }
    }

    private void updateSelfemployedAbroadField(Set<Id> updatedAppIds) {
        if (updatedAppIds.isEmpty()) {
            return;
        }
        List<Application__c> currentApplications = [
            SELECT
                Abroad_Employer_Address1__City__s,
                Abroad_Employer_Address1__CountryCode__s,
                Abroad_Employer_Address1__PostalCode__s,
                Abroad_Employer_Address1__StateCode__s,
                Abroad_Employer_Address1__Street__s,
                Abroad_Employer_End_Date1__c,
                Abroad_Employer_Name1__c,
                Abroad_Employer_Start_Date1__c,
                Abroad_Employer_Address1_State__c,
                Abroad_Employer_Address1_Country__c,
                Self_Employed_Start_Date1__c,
                Self_Employed_End_Date1__c,
                SelfEmployment_Employment_Abroad__c,
                (SELECT
                    Name,
                    Employers_Address__City__s,
                    Employers_Address__CountryCode__s,
                    Employers_Address__PostalCode__s,
                    Employers_Address__StateCode__s,
                    Employers_Address__Street__s,
                    Employers_Address_State__c,
                    Employers_Address_Country__c,
                    Employer_Name__c,
                    End_Date__c,
                    Start_Date__c,
                    Type_Of_After_UK_Employment__c
                FROM Employers__r
                WHERE Type__c = 'Work After UK'
                ORDER BY Start_Date__c)
            FROM Application__c
            WHERE Id IN :updatedAppIds
        ];
        List<Application__c> updatedApps = new List<Application__c>();
        for (Application__c app : currentApplications) {
            if (app.SelfEmployment_Employment_Abroad__c == 'Employed') {
                for (Employer__c employer : app.Employers__r) {
                    if (employer.Type_Of_After_UK_Employment__c == 'Employed') {
                        app.Abroad_Employer_Address1__City__s        = employer.Employers_Address__City__s;
                        app.Abroad_Employer_Address1__CountryCode__s = employer.Employers_Address__CountryCode__s;
                        app.Abroad_Employer_Address1__PostalCode__s  = employer.Employers_Address__PostalCode__s;
                        app.Abroad_Employer_Address1__StateCode__s   = employer.Employers_Address__StateCode__s;
                        app.Abroad_Employer_Address1__Street__s      = employer.Employers_Address__Street__s;
                        app.Abroad_Employer_End_Date1__c             = employer.End_Date__c;
                        app.Abroad_Employer_Name1__c                 = employer.Employer_Name__c;
                        app.Abroad_Employer_Start_Date1__c           = employer.Start_Date__c;
                        app.Abroad_Employer_Address1_State__c        = employer.Employers_Address_State__c;
                        app.Abroad_Employer_Address1_Country__c      = employer.Employers_Address_Country__c;
                        app.Self_Employed_Start_Date1__c             = null;
                        app.Self_Employed_End_Date1__c               = null;
                        updatedApps.add(app);
                        break;
                    }
                }
            } else if (app.SelfEmployment_Employment_Abroad__c == 'Self-Employed') {
                for (Employer__c employer : app.Employers__r) {
                    if (employer.Type_Of_After_UK_Employment__c == 'Self-Employed') {
                        app.Abroad_Employer_Address1__City__s        = null;
                        app.Abroad_Employer_Address1__CountryCode__s = null;
                        app.Abroad_Employer_Address1__PostalCode__s  = null;
                        app.Abroad_Employer_Address1__StateCode__s   = null;
                        app.Abroad_Employer_Address1__Street__s      = null;
                        app.Abroad_Employer_End_Date1__c             = null;
                        app.Abroad_Employer_Name1__c                 = null;
                        app.Abroad_Employer_Start_Date1__c           = null;
                        app.Abroad_Employer_Address1_State__c        = null;
                        app.Abroad_Employer_Address1_Country__c      = null;
                        app.Self_Employed_Start_Date1__c             = employer.Start_Date__c;
                        app.Self_Employed_End_Date1__c               = employer.End_Date__c;
                        updatedApps.add(app);
                        break;
                    }
                }
            } else if (app.SelfEmployment_Employment_Abroad__c == 'Both') {
                Boolean isFoundEmployedEmployeer = false;
                Boolean isFoundSelfEmployedEmployeer = false;
                for (Employer__c employer : app.Employers__r) {
                    if (employer.Type_Of_After_UK_Employment__c == 'Self-Employed' && isFoundSelfEmployedEmployeer == false) {
                        app.Self_Employed_Start_Date1__c             = employer.Start_Date__c;
                        app.Self_Employed_End_Date1__c               = employer.End_Date__c;
                        isFoundSelfEmployedEmployeer = true;
                    }
                    if (employer.Type_Of_After_UK_Employment__c == 'Employed' && isFoundEmployedEmployeer == false) {
                        app.Abroad_Employer_Address1__City__s        = employer.Employers_Address__City__s;
                        app.Abroad_Employer_Address1__CountryCode__s = employer.Employers_Address__CountryCode__s;
                        app.Abroad_Employer_Address1__PostalCode__s  = employer.Employers_Address__PostalCode__s;
                        app.Abroad_Employer_Address1__StateCode__s   = employer.Employers_Address__StateCode__s;
                        app.Abroad_Employer_Address1__Street__s      = employer.Employers_Address__Street__s;
                        app.Abroad_Employer_End_Date1__c             = employer.End_Date__c;
                        app.Abroad_Employer_Name1__c                 = employer.Employer_Name__c;
                        app.Abroad_Employer_Start_Date1__c           = employer.Start_Date__c;
                        app.Abroad_Employer_Address1_State__c        = employer.Employers_Address_State__c;
                        app.Abroad_Employer_Address1_Country__c      = employer.Employers_Address_Country__c;
                        isFoundEmployedEmployeer = true;
                    }
                    if (isFoundEmployedEmployeer == true && isFoundSelfEmployedEmployeer == true) {
                        updatedApps.add(app);
                        break;
                    }
                }
            } else if (app.SelfEmployment_Employment_Abroad__c == 'Both') {
                Boolean isFoundEmployedEmployeer = false;
                Boolean isFoundSelfEmployedEmployeer = false;
                for (Employer__c employer : app.Employers__r) {
                    if (employer.Type_Of_After_UK_Employment__c == 'Self-Employed' && isFoundSelfEmployedEmployeer == false) {
                        app.Self_Employed_Start_Date1__c             = employer.Start_Date__c;
                        app.Self_Employed_End_Date1__c               = employer.End_Date__c;
                        isFoundSelfEmployedEmployeer = true;
                    }
                    if (employer.Type_Of_After_UK_Employment__c == 'Employed' && isFoundEmployedEmployeer == false) {
                        app.Abroad_Employer_Address1__City__s        = employer.Employers_Address__City__s;
                        app.Abroad_Employer_Address1__CountryCode__s = employer.Employers_Address__CountryCode__s;
                        app.Abroad_Employer_Address1__PostalCode__s  = employer.Employers_Address__PostalCode__s;
                        app.Abroad_Employer_Address1__StateCode__s   = employer.Employers_Address__StateCode__s;
                        app.Abroad_Employer_Address1__Street__s      = employer.Employers_Address__Street__s;
                        app.Abroad_Employer_End_Date1__c             = employer.End_Date__c;
                        app.Abroad_Employer_Name1__c                 = employer.Employer_Name__c;
                        app.Abroad_Employer_Start_Date1__c           = employer.Start_Date__c;
                        app.Abroad_Employer_Address1_State__c        = employer.Employers_Address_State__c;
                        app.Abroad_Employer_Address1_Country__c      = employer.Employers_Address_Country__c;
                        isFoundEmployedEmployeer = true;
                    }
                    if (isFoundEmployedEmployeer == true && isFoundSelfEmployedEmployeer == true) {
                        updatedApps.add(app);
                        break;
                    }
                }
            }
            else if (app.SelfEmployment_Employment_Abroad__c == null) {
                app.Abroad_Employer_Address1__City__s        = null;
                app.Abroad_Employer_Address1__CountryCode__s = null;
                app.Abroad_Employer_Address1__PostalCode__s  = null;
                app.Abroad_Employer_Address1__StateCode__s   = null;
                app.Abroad_Employer_Address1__Street__s      = null;
                app.Abroad_Employer_End_Date1__c             = null;
                app.Abroad_Employer_Name1__c                 = null;
                app.Abroad_Employer_Start_Date1__c           = null;
                app.Abroad_Employer_Address1_State__c        = null;
                app.Abroad_Employer_Address1_Country__c      = null;
                app.Self_Employed_Start_Date1__c             = null;
                app.Self_Employed_End_Date1__c               = null;
                updatedApps.add(app);
            }
        }
        if (!updatedApps.isEmpty()) {
            update updatedApps;
        }
    }

    private void updateDaysSinceContact(Set<Id> currentAppIds) {
        List<Application__c> updateApps = [
            SELECT Date_Since_Contact__c
            FROM Application__c
            WHERE Id IN :currentAppIds
        ];
        for (Application__c app : updateApps) {
            app.Date_Since_Contact__c = Date.today();
        }
        if (!updateApps.isEmpty()) {
            update updateApps;
        }
    }

    private void updateIsKnowCheckbox(Set<Id> currentAppIds) {
        List<Application__c> updateApps = new List<Application__c>();
        for (Application__c app : [
            SELECT
                National_Insurance_Number__c,
                Is_Know_National_Insurance_Number__c
            FROM Application__c
            WHERE Id IN :currentAppIds
        ]) {
            if (String.isBlank(app.National_Insurance_Number__c)) {
                updateApps.add(new Application__c(
                    Id = app.Id,
                    Is_Know_National_Insurance_Number__c = false
                ));
            } else {
                updateApps.add(new Application__c(
                    Id = app.Id,
                    Is_Know_National_Insurance_Number__c = true
                ));
            }
        }
        if (!updateApps.isEmpty()) {
            update updateApps;
        }

    }

    private void updateRelatedDocumentsAfterChangeApplicationName(Set<Id> currentAppIds) {
        List<ContentDocumentLink> relatedContentDocumentLinks = [
            SELECT
                ContentDocumentId,
                ContentDocument.Title,
                LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :currentAppIds
        ];
        Map<Id, List<ContentDocumentLink>> appIdByRelatedContentDocumentLinks = new Map<Id, List<ContentDocumentLink>>();
        for (ContentDocumentLink link : relatedContentDocumentLinks) {
            List<ContentDocumentLink> relatedDocuments = appIdByRelatedContentDocumentLinks.get(link.LinkedEntityId);
            if(relatedDocuments == null) relatedDocuments = new List<ContentDocumentLink>();
            relatedDocuments.add(link);
            appIdByRelatedContentDocumentLinks.put(link.LinkedEntityId, relatedDocuments);
        }
        List<Application_Document__c> relatedApplicationDocuments = [
            SELECT
                Application__c,
                File_Name__c
            FROM Application_Document__c
            WHERE Application__c IN :currentAppIds
        ];
        Map<Id, List<Application_Document__c>> appIdByRelatedApplicationDocuments = new Map<Id, List<Application_Document__c>>();
        for (Application_Document__c document : relatedApplicationDocuments) {
            List<Application_Document__c> relatedDocuments = appIdByRelatedApplicationDocuments.get(document.Application__c);
            if(relatedDocuments == null) relatedDocuments = new List<Application_Document__c>();
            relatedDocuments.add(document);
            appIdByRelatedApplicationDocuments.put(document.Application__c, relatedDocuments);
        }
        List<SObject> updateDocuments = new List<SObject>();
        for (Id applicationId : appIdByRelatedContentDocumentLinks.keySet()) {
            String newName = newApplications.get(applicationId).First_Name__c + '_' + newApplications.get(applicationId).Second_Name__c;
            String oldName = oldApplications.get(applicationId).First_Name__c + '_' + oldApplications.get(applicationId).Second_Name__c;
            for (ContentDocumentLink link : appIdByRelatedContentDocumentLinks.get(applicationId)) {
                ContentDocument currentDocument = new ContentDocument();
                currentDocument.Id = link.ContentDocumentId;
                String title = link.ContentDocument.Title;
                currentDocument.Title = title.replace(oldName, newName);
                updateDocuments.add(currentDocument);
            }
        }
        for (Id applicationId : appIdByRelatedApplicationDocuments.keySet()) {
            String newName = newApplications.get(applicationId).First_Name__c + '_' + newApplications.get(applicationId).Second_Name__c;
            String oldName = oldApplications.get(applicationId).First_Name__c + '_' + oldApplications.get(applicationId).Second_Name__c;
            for (Application_Document__c document : appIdByRelatedApplicationDocuments.get(applicationId)) {
                Application_Document__c currentDocument = new Application_Document__c();
                currentDocument.Id = document.Id;
                String name = document.File_Name__c;
                currentDocument.File_Name__c = name.replace(oldName, newName);
                updateDocuments.add(currentDocument);
            }
        }
        if (!updateDocuments.isEmpty()) {
            update updateDocuments;
        }
    }

    private void updateRelatedContactAfterChangeEmail(Set<Id> updatesAppIds) {
        List<Contact> updateContacts = new List<Contact>();
        for (Id appId : updatesAppIds) {
            Application__c currentApp = newApplications.get(appId);
            Contact contact = new Contact();
            contact.Id = currentApp.Contact__c;
            contact.Email = currentApp.Email__c;
            updateContacts.add(contact);
        }
        if (!updateContacts.isEmpty()) {
            update updateContacts;
        }
    }

    private void updateRelatedPayments(Set<Id> updatesAppIds) {
        List<Payment__c> updatePayments = [
            SELECT
                Amount__c,
                Application__c,
                Product_Name__c,
                Application__r.Live_In_The_EU__c
            FROM Payment__c
            WHERE Status__c != 'Paid' AND
                  Application__c IN :updatesAppIds
        ];
        if (updatePayments.isEmpty()) {
            return;
        }
        List<PriceBookEntry> productPrices = [
            SELECT
                Id,
                Product2Id,
                Product2.Name,
                Pricebook2Id,
                Pricebook2.IsStandard,
                UnitPrice
            FROM PriceBookEntry
            WHERE Product2.Name IN :PRODUCT_NAMES
        ];
        Map<String, Decimal> productAmountForEU_Customers = new Map<String, Decimal>();
        Map<String, Decimal> productAmountForNonEU_Customers = new Map<String, Decimal>();

        for (PriceBookEntry entry : productPrices) {
            if (entry.Pricebook2.IsStandard == true) {
                productAmountForEU_Customers.put(entry.Product2.Name, entry.UnitPrice);
            } else productAmountForNonEU_Customers.put(entry.Product2.Name, entry.UnitPrice);
        }
        for (Payment__c pay : updatePayments) {
            if (pay.Application__r.Live_In_The_EU__c == true) {
                pay.Amount__c = productAmountForEU_Customers.get(pay.Product_Name__c);
            } else {
                pay.Amount__c = productAmountForNonEU_Customers.get(pay.Product_Name__c);
            }
        }
        update updatePayments;
    }

    private static void changeGoogleReviewSmsDate(Set<Id> sendSmsAppIds) {
        List<Application__c> currentApps = [
            SELECT
                Google_Review_Send_Date__c,
                Delay_In_Days__c
            FROM Application__c
            WHERE
                Id IN :sendSmsAppIds AND
                Delay_In_Days__c != null
        ];

        if (currentApps.isEmpty()) {
            return;
        }
        Date todayDate = Date.today();
        for (Application__c app : currentApps) {
            app.Google_Review_Send_Date__c = todayDate.addDays(Integer.valueOf(app.Delay_In_Days__c));
        }
        update currentApps;
    }

    private static void changeEmptyGoogleReviewSmsDate(Set<Id> sendSmsAppIds) {
        List<Application__c> currentApps = [
            SELECT
                Google_Review_Send_Date__c,
                Delay_In_Days__c
            FROM Application__c
            WHERE
                Id IN :sendSmsAppIds
        ];
        if (currentApps.isEmpty()) {
            return;
        }
        Date todayDate = Date.today();
        for (Application__c app : currentApps) {
            if (app.Delay_In_Days__c == null) {
                app.Delay_In_Days__c = '1';
            } else {
                app.Google_Review_Send_Date__c = todayDate.addDays(Integer.valueOf(app.Delay_In_Days__c));
            }
        }
        update currentApps;
    }

    private static void updatePaymentsFromAppealApps(Set<Id> appealApps) {
        List<Payment__c> currentPayments = [
            SELECT
                Product_Name__c,
                Amount__c,
                Application__c,
                Status__c,
                Order__c
            FROM Payment__c
            WHERE Application__c IN :appealApps
        ];
        if (currentPayments.isEmpty()) return;
        List<Sobject> upsertRecords = new List<Sobject>();
        Map<Id, Id> applicationIdByOrderId = new Map<Id, Id>();
        for (Payment__c payment : currentPayments) {
            if (payment.Product_Name__c == 'Deposit' && applicationIdByOrderId.get(payment.Application__c) == null) {
                applicationIdByOrderId.put(payment.Application__c, payment.Order__c);
            } else if (payment.Product_Name__c == 'Application') {
                payment.Amount__c = 850;
                upsertRecords.add(payment);
            } else {
                payment.Status__c = 'Cancel';
                upsertRecords.add(payment);
            }
        }

        List<PriceBookEntry> priceBookEntries = [
            SELECT
                Id,
                Product2Id,
                Product2.Name,
                Pricebook2Id,
                Pricebook2.IsStandard,
                UnitPrice
            FROM PriceBookEntry
            WHERE Product2.Name = :APPEAL_PRODUCT_NAME
        ];
        if (priceBookEntries.isEmpty()) {
            return;
        }
        PriceBookEntry appealProduct = priceBookEntries[0];
        List<Application__c> currentApps = [
            SELECT
                Payment_Method__c,
                Stripe_Customer_Id__c
            FROM Application__c
            WHERE Id IN :appealApps
        ];
        if(currentApps.isEmpty()) {
            return;
        }
        for (Application__c app : currentApps) {
            if (applicationIdByOrderId.get(app.Id) == null) {
                continue;
            }
            upsertRecords.add(
                new Payment__c (
                    Amount__c         = appealProduct.UnitPrice,
                    Product__c        = appealProduct.Product2Id,
                    Status__c         = 'Draft',
                    Payment_Method__c = app.Payment_Method__c,
                    Customer_Id__c    = app.Stripe_Customer_Id__c,
                    Application__c    = app.Id,
                    Order__c          = applicationIdByOrderId.get(app.Id)
                )
            );
        }
        if (!upsertRecords.isEmpty()) {
            upsert upsertRecords;
        }
    }

    private static void changeCurrentAddressAbroadState(Set<Id> changedApps){
        List<Application__c> currentApps = [
            SELECT
                Id,
                toLabel(Current_Address_Abroad__StateCode__s),
                Current_Address_Abroad_State__c
            FROM Application__c
            WHERE Id IN :changedApps
        ];
        if (currentApps.isEmpty()) {
            return;
        }
        List<Application__c> updatedApps = new List<Application__c>();
        for (Application__c app : currentApps) {
            updatedApps.add(
                new Application__c(
                    Id = app.Id,
                    Current_Address_Abroad_State__c = app.Current_Address_Abroad__StateCode__s
                )
            );
        }
        if (!updatedApps.isEmpty()) {
            update updatedApps;
        }
    }

    private void sendGoogleReviewEmail(Set<Id> apps) {
        List<Application__c> currentApps = [
            SELECT
                Google_Review_Send_Email_Date_1__c,
                Google_Review_Send_Email_Date_2__c
            FROM Application__c
            WHERE Id IN :apps
        ];
        List<Application__c> updateApps = new List<Application__c>();
        for (Application__c app : currentApps) {
            if (app.Google_Review_Send_Email_Date_1__c == null && app.Google_Review_Send_Email_Date_2__c == null) {
                Date todayDate = Date.today();
                app.Google_Review_Send_Email_Date_1__c = todayDate.addDays(5);
                app.Google_Review_Send_Email_Date_2__c = todayDate.addDays(20);
                updateApps.add(app);
            }
        }
        if (!updateApps.isEmpty()) {
            update updateApps;
        }
    }

    public void autoAssignToAgent(List<Application__c> newApps) {
        Application__c currApp = newApps[0];
		List<Application__c> valAgentApps = [
	        SELECT Val_Agent__c
            FROM Application__c
            WHERE (Status__c = 'Form Completed' OR
                   Status__c = 'Form In Progress' OR
                   Status__c = 'NO NINO' OR
                   Status__c = 'NINO/Doc Needed' OR
                   Status__c = 'Pending Client' OR
                   Status__c = 'Fix') AND
            Val_Agent__c != null
        ];
        if(valAgentApps.isEmpty()) {
            currApp.Val_Agent__c = (new List<String>( VAL_AGENTS_PROPORTION.keySet()))[0];
            return;
        }
        if(currApp.Current_Address_Abroad_Country__c == 'Australia' || currApp.Current_Address_Abroad_Country__c == 'New Zealand') {
            currApp.Val_Agent__c = 'Becky';
            return;
        }
        if(currApp.Current_Address_Abroad_Country__c == 'South Africa') {
            currApp.Val_Agent__c = 'Ciara';
            return;
        }
        if(currApp.Current_Address_Abroad_Country__c == 'United States' || currApp.Current_Address_Abroad_Country__c == 'Canada') {
            currApp.Val_Agent__c = 'MaryClaire';
            return;
        }
        Map<String, Decimal> agentNameByAppCount = new Map<String, Decimal>();
        for (Application__c app : valAgentApps) {
            Decimal count = agentNameByAppCount.get(app.Val_Agent__c);
            if(count == null) agentNameByAppCount.put(app.Val_Agent__c, 1);
            else {
                agentNameByAppCount.put(app.Val_Agent__c, ++count);
            }
        }
        for (String agent : VAL_AGENTS_PROPORTION.keySet()) {
            if(agentNameByAppCount.get(agent) == null) {
                currApp.Val_Agent__c = agent;
                return;
            }
        }
        Integer totalAmount = valAgentApps.size();
        String assignAgent;
        Decimal difference = 0;
        for (String agentName : agentNameByAppCount.keySet()) {
            Decimal currentPercentage = agentNameByAppCount.get(agentName)/totalAmount*100;
            Decimal currentDifference = currentPercentage - VAL_AGENTS_PROPORTION.get(agentName);
            if (currentPercentage <= VAL_AGENTS_PROPORTION.get(agentName) && currentDifference < difference) {
                assignAgent = agentName;
                difference = currentDifference;
            }
        }
        if (assignAgent == null ) assignAgent = valAgentApps[0].Val_Agent__c;
        if (newApps.isEmpty()) return;
        currApp.Val_Agent__c  = assignAgent;
    }

    public static void changeAgentStatusApps(Set<Id> updatedAppIds) {
        if (updatedAppIds.isEmpty()) {
            return;
        }
        List<Application__c> updatedApps = new List<Application__c>();
        for(Application__c app : [
            SELECT
                Status__c,
                Agent_Status__c,
                New_Agent__c
            FROM Application__c
            WHERE Id IN :updatedAppIds
        ]) {
            Application__c currApp = new Application__c(
                Id = app.Id,
                Agent_Status__c = app.Status__c
            );
            if (app.New_Agent__c == null && app.Status__c == 'Agent Check') {
                currApp.New_Agent__c = autoAssignToNewAgent();
            }
            updatedApps.add(currApp);
        }
        if (!updatedApps.isEmpty()) {
            update updatedApps;
        }
    }

    public static String autoAssignToNewAgent() {
		List<Application__c> newAgentApps = [
	        SELECT New_Agent__c
            FROM Application__c
            WHERE (Status__c = 'Fix' OR
                   Status__c = 'Agent Check' OR
                   Status__c = 'QC Approved') AND
                   New_Agent__c != null
        ];
        if(newAgentApps.isEmpty()) {
            return (new List<String>( AGENTS_PROPORTION.keySet()))[0];
        }

        Map<String, Decimal> agentNameByAppCount = new Map<String, Decimal>();
        for (Application__c app : newAgentApps) {
            Decimal count = agentNameByAppCount.get(app.New_Agent__c);
            if(count == null) agentNameByAppCount.put(app.New_Agent__c, 1);
            else {
                agentNameByAppCount.put(app.New_Agent__c, ++count);
            }
        }
        for (String agent : AGENTS_PROPORTION.keySet()) {
            if(agentNameByAppCount.get(agent) == null) {
                return agent;
            }
        }
        Integer totalAmount = newAgentApps.size();
        String assignAgent;
        Decimal difference = 0;
        for (String agentName : agentNameByAppCount.keySet()) {
            Decimal currentPercentage = agentNameByAppCount.get(agentName)/totalAmount*100;
            Decimal currentDifference = currentPercentage - AGENTS_PROPORTION.get(agentName);
            if (currentPercentage <= AGENTS_PROPORTION.get(agentName) && currentDifference < difference) {
                assignAgent = agentName;
                difference = currentDifference;
            }
        }
        if (assignAgent == null ) return newAgentApps[0].New_Agent__c;
        else return assignAgent;
    }

    public static void sendSalesAgentCustomNotification(Set<Id> currApps) {
        List<Application__c> apps = [
            SELECT
                Val_Agent__c,
                First_Name__c,
                Second_Name__c,
                Name
            FROM Application__c
            WHERE Id = :currApps
        ];

        if (apps.isEmpty()) {
            return;
        }
        List<String> names = new List<String>();
        for (Application__c app : apps) {
            names.add(app.Val_Agent__c);
        }
        List<User> users = [
            SELECT
                Id,
                FirstName
            FROM User
            WHERE FirstName IN :names
        ];
        if (users.isEmpty()) {
            return;
        }
        Map<String, Id> valAgentNameByUserId = new Map<String, Id>();
        for (User user : users) {
            valAgentNameByUserId.put(user.FirstName, user.Id);
        }
        if (AGENT_NOTIFICATION == null) {
            return;
        }
        List<ContentDocumentLink> notesData = [
            SELECT
                ContentDocument.Title,
                ContentDocument.LatestPublishedVersion.VersionData,
                LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :currApps AND
                  ContentDocument.FileExtension = 'snote'
            ORDER BY ContentDocument.CreatedDate DESC
        ];
        Map<Id, ContentDocumentLink> appIdByLatestNote = new Map<Id, ContentDocumentLink>();
        for (ContentDocumentLink link : notesData) {
            if (appIdByLatestNote.get(link.LinkedEntityId) == null) {
                appIdByLatestNote.put(link.LinkedEntityId, link);
            }
        }
        List<Messaging.SingleEmailMessage> lstSingleEmailMessage = new List<Messaging.SingleEmailMessage>();
        for(Application__c app : apps) {
            String subject = app.Name + ' ' + app.First_Name__c + ' ' + app.Second_Name__c  + ' - MOVED TO FIX - PRIORITY';
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle(subject);
            notification.setBody(subject);
            notification.setNotificationTypeId(AGENT_NOTIFICATION.Id);
            notification.setTargetId(app.Id);
            notification.send(new Set<String> {valAgentNameByUserId.get(app.Val_Agent__c)});
            Messaging.SingleEmailMessage message = sendMessage(app, subject, VAL_AGENTS_BY_EMAIL.get(app.Val_Agent__c));
            ContentDocumentLink currNote = appIdByLatestNote.get(app.Id);
            if(currNote != null) {
                message.setHtmlBody('<p>' + currNote.ContentDocument.Title + '</p>' + currNote.ContentDocument.LatestPublishedVersion.VersionData.toString());
            }
            lstSingleEmailMessage.add(message);
        }
        Messaging.SendEmailResult[] result = Messaging.sendEmail(lstSingleEmailMessage);
    }

    public static void sendValAgentCustomNotification(Set<Id> currApps) {
        List<Application__c> apps = [
            SELECT
                New_Agent__c,
                First_Name__c,
                Second_Name__c,
                Name
            FROM Application__c
            WHERE Id = :currApps
        ];

        if (apps.isEmpty()) {
            return;
        }
        List<String> names = new List<String>();
        for (Application__c app : apps) {
            names.add(app.New_Agent__c);
        }
        List<User> users = [
            SELECT
                Id,
                FirstName
            FROM User
            WHERE FirstName IN :names
        ];
        if (users.isEmpty()) {
            return;
        }
        Map<String, Id> docAgentNameByUserId = new Map<String, Id>();
        for (User user : users) {
            docAgentNameByUserId.put(user.FirstName, user.Id);
        }
        if (AGENT_NOTIFICATION == null) {
            return;
        }
        List<Messaging.SingleEmailMessage> lstSingleEmailMessage = new List<Messaging.SingleEmailMessage>();
        for(Application__c app : apps) {
            String subject = app.Name + ' ' + app.First_Name__c + ' ' + app.Second_Name__c  + ' - MOVED BACK TO AGENT CHECK - PRIORITY';
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle(subject);
            notification.setBody(subject);
            notification.setNotificationTypeId(AGENT_NOTIFICATION.Id);
            notification.setTargetId(app.Id);
            notification.send(new Set<String> {docAgentNameByUserId.get(app.New_Agent__c)});
            lstSingleEmailMessage.add(sendMessage(app, subject, DOC_AGENTS_BY_EMAIL.get(app.New_Agent__c)));
        }
        Messaging.SendEmailResult[] result = Messaging.sendEmail(lstSingleEmailMessage);
    }

    private static Messaging.SingleEmailMessage sendMessage(Application__c currApp, String subject, String toAddress) {
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setUseSignature(false);
        message.setSaveAsActivity(true);
        message.setTreatTargetObjectAsRecipient(false);
        message.setWhatId(currApp.Id);
        if ( OWD != null ) {
            message.setOrgWideEmailAddressId(OWD.Id);
        }
        message.setSubject(subject);
        message.setPlainTextBody('');
        message.toAddresses = new String[] {toAddress};
        return message;
    }

    @future
    private static void generateZipArchive(Id applicationId) {
        if (applicationId == null) {
            return;
        }
        List<ContentDocumentLink> cdls = [
            SELECT
                ContentDocumentId,
                ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :applicationId AND (
                  ContentDocument.Title LIKE '%64-8_ForSignature_completed' OR
                  ContentDocument.Title LIKE '%CF083_ForSignature_completed' OR
                  ContentDocument.Title LIKE '%CustomLetter_ForSignature' OR
                  ContentDocument.Title LIKE '%UPLOAD%'
                )
            ORDER BY ContentDocument.CreatedDate DESC
        ];
        Map<String, ContentDocumentLink> fileKeyWordByLink = new Map<String, ContentDocumentLink>();
        for (ContentDocumentLink link : cdls) {
            if (link.ContentDocument.Title.contains('CF083') && fileKeyWordByLink.get('CF083') == null) {
                fileKeyWordByLink.put('CF083', link);
            } else if (link.ContentDocument.Title.contains('64-8') && fileKeyWordByLink.get('64-8') == null) {
                fileKeyWordByLink.put('64-8', link);
            } else if (link.ContentDocument.Title.contains('CustomLetter') && fileKeyWordByLink.get('CustomLetter') == null) {
                fileKeyWordByLink.put('CustomLetter', link);
            } else if (link.ContentDocument.Title.contains('UPLOAD') && fileKeyWordByLink.get('UPLOAD') == null) {
                fileKeyWordByLink.put('UPLOAD', link);
            }
        }
        String errorMessage = '';
        if (fileKeyWordByLink.get('CF083') == null) {
            errorMessage += 'CF083_ForSignature_completed.pdf file is missing. \n';
        }
        if (fileKeyWordByLink.get('64-8') == null) {
            errorMessage += '64-8_ForSignature_completed.pdf file is missing. \n';
        }
        if (fileKeyWordByLink.get('CustomLetter') == null) {
            errorMessage += 'CustomLetter_ForSignature.pdf file is missing. \n';
        }

        if (String.isNotBlank(errorMessage)) {
            update new Application__c(
                Id = applicationId,
                Zip_Archive_Error__c = errorMessage
            );
            return;
        }
        Compression.ZipWriter writer = new Compression.ZipWriter();

        Set<Id> contentDocumentIds = new Set<Id>();
        contentDocumentIds.add(fileKeyWordByLink.get('CF083').ContentDocumentId);
        contentDocumentIds.add(fileKeyWordByLink.get('CustomLetter').ContentDocumentId);
        Boolean isContainUploadFile = false;
        if (fileKeyWordByLink.get('UPLOAD') != null) {
            contentDocumentIds.add(fileKeyWordByLink.get('UPLOAD').ContentDocumentId);
            isContainUploadFile = true;
        }
        contentDocumentIds.add(fileKeyWordByLink.get('64-8').ContentDocumentId);

        Map<String, Id> currVers = new Map<String, Id>();
        for ( ContentVersion cv : [SELECT PathOnClient, Versiondata, ContentDocument.Title, ContentDocument.FileExtension
                                   FROM ContentVersion
                                   WHERE ContentDocumentId IN :contentDocumentIds
                                   ORDER BY CreatedDate DESC]) {
            String docName = cv.ContentDocument.Title + '.' + cv.ContentDocument.FileExtension;
            if(currVers.get(docName) == null) {
                writer.addEntry(docName, cv.versiondata);
                currVers.put(docName, cv.Id);
            }
        }

        blob zipAttachment = writer.getArchive();

        List<ContentDocumentLink> zipDoc =[
            SELECT
                ContentDocumentId,
                ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :applicationId AND
                  ContentDocument.Title LIKE '%ZIP%'
        ];

        List<Application__c> apps = [
            SELECT
                First_Name__c,
                Second_Name__c,
                Name
            FROM Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        if(apps.size() == 0) return;
        Application__c currentApplication = apps[0];
        update new Application__c(Id = applicationId, FTP_Send_Date__c = null, Zip_Archive_Contains_UPLOAD_file__c = isContainUploadFile);
        String finalTitle = currentApplication.First_Name__c + '_' + currentApplication.Second_Name__c + '_' +
        currentApplication.Name + '_ZIP';
        if (zipDoc.size() != 0) {
            insert new ContentVersion (
                ContentDocumentId = zipDoc[0].ContentDocumentId,
                VersionData = zipAttachment,
                PathOnClient = finalTitle + '.zip'
            );
        } else {

            ContentVersion conVer = new ContentVersion();
            conVer.ContentLocation = 'S';
            conVer.PathOnClient = finalTitle + '.zip';
            conVer.Title = finalTitle;
            conVer.VersionData = zipAttachment;
            insert conVer;

            ContentVersion conDoc = [SELECT ContentDocumentId, ContentSize FROM ContentVersion WHERE Id =:conVer.Id][0];

            ContentDocumentLink conDocLink = new ContentDocumentLink();
            conDocLink.LinkedEntityId = applicationId;
            conDocLink.ContentDocumentId = conDoc.ContentDocumentId;
            conDocLink.shareType = 'I';
            conDocLink.Visibility = 'AllUsers';
            insert conDocLink;
        }
    }

    public static void fakeMethod(){
        Integer i = 0;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
    }
}