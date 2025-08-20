public class CheckModuleController {

    @AuraEnabled(cacheable=false)
    public static String createHMRCCheckRequestRecord(String checkReply) {
        CheckRequest reply = (CheckRequest)JSON.deserialize(checkReply, CheckRequest.class);
        if (checkReply == null) return null;
        List<Application__c> currentApps = [
            SELECT Id
            FROM Application__c
            WHERE Name = :reply.appName
        ];
        if (currentApps.size() == 0) return null;
        HMRC_Check__c checkRequest = new HMRC_Check__c(
            Application__c = currentApps[0].Id,
            Check_Agents__c = reply.agent,
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
            PDF_GDrive_Link__c  = reply.pdfLink
        );
        insert checkRequest;
        System.debug('checkRequest ' + checkRequest);
        System.debug('checkRequest ' + checkRequest.Id);
        return checkRequest.Id;
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
                (SELECT
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
                    Has_the_request_been_processed__c
                 FROM HMRC_Check_Requests__r
                 ORDER BY CreatedDate DESC
                 LIMIT 1)
            FROM Application__c
        ];
        return apps;
    }

    public class CheckRequest {
        @AuraEnabled
        public String agent {get; set;}
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
        public String  pdfLink {get; set;}
    }
}