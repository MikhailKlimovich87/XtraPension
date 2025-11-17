public class CheckModuleController {
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

    private static final Map<String, String> AGENT_MESSAGE = new Map<String, String> {
        'Not Received' => XtraPensionConstants.NOT_RECEIVED_CHECK_AGENT_MESSAGE,
        'C2/C3/Received' => XtraPensionConstants.C2_C3_CHECK_AGENT_MESSAGE,
        'BadNINO' => XtraPensionConstants.BAD_NINO_CHECK_AGENT_MESSAGE,
        '64-8' => XtraPensionConstants.X64_8_CHECK_AGENT_MESSAGE,
        'Reject' => XtraPensionConstants.REJECT_CHECK_AGENT_MESSAGE,
        'Appeal Not Received' => XtraPensionConstants.APPEAL_CHECK_AGENT_MESSAGE
    };

    private static final Map<String, String> AGENT_NAME_BY_EMAIL {
        get {
            if (AGENT_NAME_BY_EMAIL == null) {
                List<XtraPension_Settings__mdt> setts = [
    				SELECT Recheck_Agent_Name_By_Email__c
    				FROM XtraPension_Settings__mdt
    				WHERE DeveloperName = 'Configuration'
                    LIMIT 1
                ];
                if (!setts.isEmpty()) {
                    AGENT_NAME_BY_EMAIL = (Map<String, String>)JSON.deserialize(setts[0].Recheck_Agent_Name_By_Email__c, Map<String, String>.class);
                }
            }
            return AGENT_NAME_BY_EMAIL;
        }
        private set;
    }

    private static final Map<String, Id> AGENT_BY_USER_ID_NOTIFICATION {
        get {
            if (AGENT_BY_USER_ID_NOTIFICATION == null) {
                List<User> sentAgents = [
                   SELECT
                        Id,
                        FirstName,
                        Username
                    FROM User
                     WHERE FirstName IN :AGENT_NAME_BY_EMAIL.keySet() OR Username = 'jr@xtrapension.com'
                ];
                if (!sentAgents.isEmpty()) {
                    AGENT_BY_USER_ID_NOTIFICATION = new Map<String, Id>();
                    for (User user : sentAgents) {
                        if (user.FirstName == 'Monica') continue;
                        if (user.Username == 'jr@xtrapension.com' ) {
                            AGENT_BY_USER_ID_NOTIFICATION.put('Monica', user.Id);
                        } else AGENT_BY_USER_ID_NOTIFICATION.put(user.FirstName, user.Id);
                    }
                }
            }
            return AGENT_BY_USER_ID_NOTIFICATION;
        }
        private set;
    }

    @AuraEnabled(cacheable=false)
    public static List<Application__c> getApplicationNames() {
        List<Application__c> apps = [
            SELECT
                Name,
                Status__c,
                First_Name__c,
                Second_Name__c,
                Date_Of_Birth__c,
                Full_Current_Address_Abroad__c,
                Related_Contact_Phone__c,
                Full_Maiden_Previous_Name__c,
                National_Insurance_Number__c,
                Age__c,
                CreatedDate,
                Appeal_Application__c,
                Tracking_Number_Received_Date__c,
                Tracking_Number_Received_Date_2__c,
                Tracking_Number_Received_Date_3__c,
                (SELECT
                    Id,
                    X64_8__c,
                    BadInfo__c,
                    BadNINO__c,
                    C2__c,
                    C3__c,
                    Check_Agents__c,
                    DWP__c,
                    HMRC_Reply_Sent_Date__c,
                    HMRC_Reply_Sent_to__c,
                    Not_Received__c,
                    Notes__c,
                    PDF_GDrive_Link__c,
                    Processing_Received__c,
                    Reject__c,
                    Work_Item__c,
                    CreatedDate,
                    Actioned_Date__c,
                    Notification_sent_to__c,
                    Recheck_Date__c,
                    Has_the_request_been_processed__c,
                    Colour_Label__c,
                    Priority_Request__c,
                    Appeal_Letter_Not_Received__c,
                    Appeal_Letter_Received__c,
                    Agent_To_Sent_Notification__c,
                    Payment_Received__c,
                    Payment_Not_Received__c
                 FROM HMRC_Check_Requests__r
                 ORDER BY CreatedDate DESC
                 LIMIT 1)
            FROM Application__c
        ];
        return apps;
    }

    @AuraEnabled(cacheable=false)
    public static List<HMRC_Check__c> createHMRCCheckRequestRecord(CheckRequestWrapper checkData) {
        if (checkData == null || checkData.checkReplies.size() == 0) return null;
        Set<String> appNames = new Set<String>();
        for (CheckRequest request : checkData.checkReplies) {
            if (request.appName != null) appNames.add(conevertAppName(request.appName));
        }
        if(appNames.size() == 0) return null;
        List<Application__c> currentApps = [
            SELECT
                Id,
                Name,
                First_Name__c,
                Second_Name__c, 
                Status__c
            FROM Application__c
            WHERE Name IN :appNames
        ];
        if (currentApps.size() == 0) return null;
        Map<String, Application__c> appNoByAppRecord = new Map<String, Application__c>();
        for (Application__c app : currentApps) {
            appNoByAppRecord.put(app.Name, app);
        }

        List<HMRC_Check__c> currRequests = new List<HMRC_Check__c>();
        for (Integer i = 0; i < checkData.checkReplies.size() && i < 50; i++) {
            CheckRequest reply = checkData.checkReplies[i];
            currRequests.add(
                new HMRC_Check__c(
                    Application__c = appNoByAppRecord.get(conevertAppName(reply.appName)).Id,
                    Check_Agents__c = checkData.checkAgent,
                    Not_Received__c = reply.notReceived,
                    C2__c = reply.c2,
                    Work_Item__c = reply.workItem,
                    BadInfo__c = reply.badInfo,
                    BadNINO__c = reply.badNINO,
                    Processing_Received__c = reply.processing,
                    C3__c = reply.c3,
                    DWP__c = reply.dwp,
                    X64_8__c = reply.X64_8,
                    Reject__c = reply.reject,
                    HMRC_Reply_Sent_to__c = reply.sentTo,
                    HMRC_Reply_Sent_Date__c = reply.sentDate == null ? null : Date.valueOf(reply.sentDate),
                    Notes__c = reply.notes,
                    PDF_GDrive_Link__c  = reply.pdfLink,
                    Appeal_Letter_Not_Received__c = reply.appealLetterNotReceived,
                    Appeal_Letter_Received__c = reply.appealLetterReceived,
                    Have_you_requested_a_copy__c = reply.requestedCopy == 'Yes' ? 'Yes' : 'No',
                    Was_the_payment_made_by_the_client__c = reply.paymentMadeByClient == 'Yes' ? 'Yes' : 'No',
                    When__c = reply.whenDate == null ? null : Date.valueOf(reply.whenDate),
                    Check_Date__c = Date.today(),
                    Payment_Received__c = reply.paymentReceived,
                    Payment_Not_Received__c = reply.paymentNotReceived
                )
            );
        }

        if (currRequests.size() != 0) {
            Database.insert(currRequests, true);
        }
        for (HMRC_Check__c req : currRequests) {
            if (req.Id != null) {
                sendNotificationsToAgent(req.Id);
            }
        }
        return currRequests;
    }

    private static String conevertAppName(String appNo) {
        String currAppName = '';
        if (appNo.length() == 4) {
            currAppName = 'A0' + appNo;
        } else if (appNo.length() == 5) {
            currAppName = 'A' + appNo;
        } else currAppName = appNo;
        return currAppName;
    }

    @future
    private static void sendNotificationsToAgent(Id checkRequestId) {
        if(checkRequestId == null) return;
        List<HMRC_Check__c> checkRequests = [
            SELECT
                Name,
                Application__c,
                Application__r.Name,
                Application__r.First_Name__c,
                Application__r.Second_Name__c,
                Priority_Request__c,
                Agent_To_Sent_Notification__c,
                Recheck_Date__c,
                C2__c,
                C3__c,
                Application__r.Status__c
            FROM HMRC_Check__c
            WHERE Id = :checkRequestId
        ];
        if (checkRequests.size() == 0) return;
        HMRC_Check__c currRequest = checkRequests[0];

        if (currRequest.Agent_To_Sent_Notification__c == null ||
            currRequest.Application__r.Status__c == 'Annual Service' ||
            currRequest.Application__r.Status__c == 'No Annual' ||
            currRequest.Application__r.Status__c == 'Closed') return;

        List<Messaging.SingleEmailMessage> lstSingleEmailMessage = new List<Messaging.SingleEmailMessage>();
        String messageBody = AGENT_MESSAGE.get(currRequest.Priority_Request__c);
        Messaging.CustomNotification notification = new Messaging.CustomNotification();
        notification.setTitle(messageBody);
        notification.setBody(currRequest.Application__r.Name + ' - ' + messageBody);
        notification.setNotificationTypeId(AGENT_NOTIFICATION.Id);
        notification.setTargetId(currRequest.Application__c);

        if (AGENT_BY_USER_ID_NOTIFICATION.get(currRequest.Agent_To_Sent_Notification__c) != null) {
            notification.send(new Set<String> {AGENT_BY_USER_ID_NOTIFICATION.get(currRequest.Agent_To_Sent_Notification__c)});
        }

        currRequest.Notification_sent_to__c = true;
        currRequest.Recheck_Date__c = currRequest.Priority_Request__c == 'Not Received' ||
                                      currRequest.Priority_Request__c == 'BadNINO' ||
                                      currRequest.Priority_Request__c == '64-8' ||
                                      currRequest.Priority_Request__c == 'Reject' ||
                                      currRequest.Priority_Request__c == 'Appeal Not Received' ?
                                        Date.today().addDays(28) :
                                        currRequest.Priority_Request__c == 'Work Item' ?
                                            Date.today().addDays(14) :
                                            (currRequest.C2__c == true ||
                                             currRequest.C3__c == true) &&
                                            (currRequest.Application__r.Status__c == 'Posted' ||
                                             currRequest.Application__r.Status__c == '64-8 Bounce' ||
                                             currRequest.Application__r.Status__c == 'HMRC Reply 1' ||
                                             currRequest.Application__r.Status__c == 'DWP Teleclaim' ||
                                             currRequest.Application__r.Status__c == 'DWP 2 Emails Sent' ||
                                             currRequest.Application__r.Status__c == 'DWP Shortfall Pending' ||
                                             currRequest.Application__r.Status__c == 'XP Letter Sent' ||
                                             currRequest.Application__r.Status__c == 'HMRC Reply 2') ?
                                                Date.today().addDays(7) :
                                                null;
        update currRequest;

        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setUseSignature(false);
        message.setSaveAsActivity(true);
        message.setTreatTargetObjectAsRecipient(false);
        message.setWhatId(currRequest.Application__c);
        if ( OWD != null ) {
            message.setOrgWideEmailAddressId(OWD.Id);
        }
        message.setSubject(currRequest.Application__r.Name + ' - ' + messageBody);
        message.setPlainTextBody('');
        message.toAddresses = new String[] {AGENT_NAME_BY_EMAIL.get(currRequest.Agent_To_Sent_Notification__c)};
        lstSingleEmailMessage.add(message);

        Messaging.SendEmailResult[] result = Messaging.sendEmail(lstSingleEmailMessage);
    }

    @AuraEnabled
    public static void addRequestCheckData(Id appId) {
        if (appId == null) return;
        User currentUser = [
            SELECT
                Username,
                FirstName
            FROM User
            WHERE Id =: UserInfo.getUserId()];
        if (currentUser == null) return;
        String requestBy = currentUser.Username == 'jr@xtrapension.com' ? 'Monica' : currentUser.FirstName;
        update new Application__c(
            Id = appId,
            Check_Request_by__c = requestBy,
            Request_Check_Date__c = Date.today()
        );
    }

    public class CheckRequestWrapper {
        @AuraEnabled
        public List<CheckRequest> checkReplies {get; set;}
        @AuraEnabled
        public String checkAgent {get; set;}
    }

    public class CheckRequest {
        @AuraEnabled
        public String appName {get; set;}
        @AuraEnabled
        public Boolean notReceived {get; set;}
        @AuraEnabled
        public Boolean c2 {get; set;}
        @AuraEnabled
        public Boolean workItem {get; set;}
        @AuraEnabled
        public Boolean badNINO {get; set;}
        @AuraEnabled
        public Boolean badInfo {get; set;}
        @AuraEnabled
        public Boolean processing {get; set;}
        @AuraEnabled
        public Boolean c3 {get; set;}
        @AuraEnabled
        public Boolean dwp {get; set;}
        @AuraEnabled
        public Boolean X64_8 {get; set;}
        @AuraEnabled
        public Boolean reject {get; set;}
        @AuraEnabled
        public String sentTo {get; set;}
        @AuraEnabled
        public String sentDate {get; set;}
        @AuraEnabled
        public String notes {get; set;}
        @AuraEnabled
        public String pdfLink {get; set;}
        @AuraEnabled
        public Boolean appealLetterNotReceived{get; set;}
        @AuraEnabled
        public Boolean appealLetterReceived{get; set;}
        @AuraEnabled
        public String requestedCopy{get; set;}
        @AuraEnabled
        public String paymentMadeByClient{get; set;}
        @AuraEnabled
        public String whenDate{get; set;}
        @AuraEnabled
        public Boolean paymentReceived{get; set;}
        @AuraEnabled
        public Boolean paymentNotReceived{get; set;}
    }
}