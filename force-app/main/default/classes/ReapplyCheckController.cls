public with sharing class ReapplyCheckController {

    @AuraEnabled(cacheable=false)
    public static List<Reapply__c> getReapplyNames() {
        return [
            SELECT
                Id,
                Name,
                Status__c,
                First_Name__c,
                Second_Name__c,
                Date_of_birth__c,
                Full_Address_abroad__c,
                Phone__c,
                Daytime_phone_number__c,
                Former_Name__c,
                NINO__c,
                Application__c,
                Application__r.Name,
                Tracking_Number_Send_Date__c,
                Tracking_No_to_HMRC__c,
                (SELECT
                    Id,
                    Name,
                    X64_8__c,
                    BadInfo__c,
                    BadNINO__c,
                    C2__c,
                    C3__c,
                    Check_Agents__c,
                    Check_Date__c,
                    DWP__c,
                    DWP_Call__c,
                    HMRC_Reply_Sent_Date__c,
                    HMRC_Reply_Sent_to__c,
                    Not_Received__c,
                    Notes__c,
                    PDF_GDrive_Link__c,
                    Processing_Received__c,
                    Reject__c,
                    Work_Item__c,
                    Colour_Label__c,
                    Priority_Request__c,
                    Have_you_requested_a_copy__c,
                    CreatedDate
                 FROM Reapply_Checks__r
                 ORDER BY CreatedDate DESC)
            FROM Reapply__c
            WHERE Status__c != 'Pre Sale'
            ORDER BY Name
        ];
    }

    @AuraEnabled(cacheable=false)
    public static List<Reapply_Check__c> createReapplyCheckRecords(CheckRequestWrapper checkData) {
        if (checkData == null || checkData.checkReplies == null || checkData.checkReplies.size() == 0) return null;
        Set<String> keys = new Set<String>();
        for (CheckRequest request : checkData.checkReplies) {
            if (String.isNotBlank(request.appName)) keys.add(numberKey(request.appName));
        }
        if (keys.size() == 0) return null;

        Map<String, Reapply__c> reapplyByKey = new Map<String, Reapply__c>();
        for (Reapply__c reapply : [
            SELECT Id, Name, Application__c
            FROM Reapply__c
            WHERE Status__c != 'Pre Sale'
        ]) {
            reapplyByKey.put(numberKey(reapply.Name), reapply);
        }

        List<Reapply_Check__c> checks = new List<Reapply_Check__c>();
        for (Integer i = 0; i < checkData.checkReplies.size() && i < 50; i++) {
            CheckRequest reply = checkData.checkReplies[i];
            Reapply__c reapply = String.isBlank(reply.appName) ? null : reapplyByKey.get(numberKey(reply.appName));
            if (reapply == null) {
                throw new AuraHandledException('Reapply not found: ' + reply.appName);
            }
            checks.add(
                new Reapply_Check__c(
                    Reapply__c = reapply.Id,
                    Application__c = reapply.Application__c,
                    Check_Agents__c = checkData.checkAgent,
                    Check_Date__c = Date.today(),
                    Not_Received__c = reply.notReceived == true,
                    Processing_Received__c = reply.processing == true,
                    C2__c = reply.c2 == true,
                    C3__c = reply.c3 == true,
                    Work_Item__c = reply.workItem == true,
                    BadNINO__c = reply.badNINO == true,
                    BadInfo__c = reply.badInfo == true,
                    DWP__c = reply.dwp == true,
                    DWP_Call__c = reply.dwpCall == true,
                    X64_8__c = reply.X64_8 == true,
                    Reject__c = reply.reject == true,
                    HMRC_Reply_Sent_to__c = reply.sentTo,
                    HMRC_Reply_Sent_Date__c = String.isBlank(reply.sentDate) ? null : Date.valueOf(reply.sentDate),
                    Have_you_requested_a_copy__c = reply.requestedCopy == 'Yes' ? 'Yes' : 'No',
                    Notes__c = reply.notes,
                    PDF_GDrive_Link__c = reply.pdfLink
                )
            );
        }
        if (checks.size() != 0) {
            Database.insert(checks, true);
        }
        return checks;
    }

    @AuraEnabled
    public static void addRequestCheckData(Id reapplyId) {
        if (reapplyId == null) return;
        User currentUser = [
            SELECT Username, FirstName
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];
        String requestBy = currentUser.Username == 'jr@xtrapension.com' ? 'Monica' : currentUser.FirstName;
        update new Reapply__c(
            Id = reapplyId,
            Check_Request_by__c = requestBy,
            Request_Check_Date__c = Date.today()
        );
    }

    // subjects of the "Has HMRC's letter reached you?" emails (same marks as RE_AwaitingLetterScheduler)
    @TestVisible static final String LETTER_APPROVED = 'HMRC approved your REAPPLY';
    @TestVisible static final String LETTER_NO_UPDATE = 'Your REAPPLY: has HMRC written to you?';

    /** Latest "Has HMRC's letter reached you?" email of each Reapply, for the queue (sent by the scheduler or by hand). */
    @AuraEnabled(cacheable=false)
    public static List<LetterRequest> getLetterRequests() {
        Map<Id, LetterRequest> byReapply = new Map<Id, LetterRequest>();
        String approved = '%' + LETTER_APPROVED + '%';
        String noUpdate = '%' + LETTER_NO_UPDATE + '%';
        for (EmailMessage m : [
            SELECT RelatedToId, MessageDate, Subject
            FROM EmailMessage
            WHERE RelatedTo.Type = 'Reapply__c' AND (Subject LIKE :approved OR Subject LIKE :noUpdate)
            ORDER BY MessageDate DESC
            LIMIT 5000
        ]) {
            if (byReapply.containsKey(m.RelatedToId)) continue;
            LetterRequest r = new LetterRequest();
            r.reapplyId = m.RelatedToId;
            r.sentDate = m.MessageDate;
            r.version = m.Subject.contains(LETTER_APPROVED) ? 'approved' : 'no update';
            byReapply.put(m.RelatedToId, r);
        }
        return byReapply.values();
    }

    public class LetterRequest {
        @AuraEnabled
        public Id reapplyId {get; set;}
        @AuraEnabled
        public Datetime sentDate {get; set;}
        @AuraEnabled
        public String version {get; set;}
    }

    // R08694, A08694, 08694 and 8694 all point to the same reapply
    @TestVisible
    private static String numberKey(String value) {
        String digits = value == null ? '' : value.trim().replaceAll('^[A-Za-z]+', '').replaceFirst('^0+', '');
        return digits;
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
        public Boolean dwpCall {get; set;}
        @AuraEnabled
        public String sentTo {get; set;}
        @AuraEnabled
        public String sentDate {get; set;}
        @AuraEnabled
        public String notes {get; set;}
        @AuraEnabled
        public String pdfLink {get; set;}
        @AuraEnabled
        public String requestedCopy {get; set;}
    }
}