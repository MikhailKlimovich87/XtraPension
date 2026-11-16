// Claim Check tab: the check team records what the DWP said about a claim (Basic__c), or asks for a check.
// Same idea as ReapplyCheckController, with DWP results instead of HMRC ones.
public with sharing class ClaimCheckController {
    // C00000 is the test claim (it has a real test charge)
    private static final Set<String> TEST_CLAIMS = new Set<String>{ 'C00000' };
    // Claims not yet sent to the DWP have nothing to check
    private static final Set<String> NOT_SENT_STATUSES = new Set<String>{
        'Form In Progress', 'Validation Call', 'Form completed', 'Pending Client', 'Agent Check', 'QC Approved',
        'Sent for eSignature', 'Deposit Refund'
    };

    @AuraEnabled(cacheable=false)
    public static List<Basic__c> getClaims() {
        return [
            SELECT
                Id,
                Name,
                Status__c,
                First_Name__c,
                Last_Name__c,
                Claimant_dob__c,
                Claimant_nino__c,
                Claimant_maiden_Name__c,
                Claimant_address1__c,
                Claimant_address2__c,
                Current_Address_Abroad_Country_Name__c,
                Phone__c,
                Stage_1_Pack_Posted_Date__c,
                Big_Envelop_Posted_Date__c,
                CreatedDate,
                (SELECT
                    Id,
                    Name,
                    Check_Agents__c,
                    Check_Date__c,
                    Not_Received__c,
                    Received_by_DWP__c,
                    Processing__c,
                    More_Info_Requested__c,
                    Approved__c,
                    Rejected__c,
                    Lump_Sum_Letter__c,
                    Payment_Started__c,
                    Called_DWP__c,
                    Notes__c,
                    PDF_GDrive_Link__c,
                    Colour_Label__c,
                    Priority_Request__c,
                    CreatedDate
                 FROM Claim_Checks__r
                 ORDER BY CreatedDate DESC)
            FROM Basic__c
            WHERE Status__c NOT IN :NOT_SENT_STATUSES AND Name NOT IN :TEST_CLAIMS
            ORDER BY Name
        ];
    }

    @AuraEnabled(cacheable=false)
    public static List<Claim_Check__c> createClaimCheckRecords(CheckRequestWrapper checkData) {
        if (checkData == null || checkData.checkReplies == null || checkData.checkReplies.size() == 0) return null;
        Set<String> keys = new Set<String>();
        for (CheckRequest request : checkData.checkReplies) {
            if (String.isNotBlank(request.appName)) keys.add(numberKey(request.appName));
        }
        if (keys.size() == 0) return null;

        Map<String, Basic__c> claimByKey = new Map<String, Basic__c>();
        for (Basic__c claim : [
            SELECT Id, Name
            FROM Basic__c
            WHERE Status__c NOT IN :NOT_SENT_STATUSES AND Name NOT IN :TEST_CLAIMS
        ]) {
            claimByKey.put(numberKey(claim.Name), claim);
        }

        List<Claim_Check__c> checks = new List<Claim_Check__c>();
        for (Integer i = 0; i < checkData.checkReplies.size() && i < 50; i++) {
            CheckRequest reply = checkData.checkReplies[i];
            Basic__c claim = String.isBlank(reply.appName) ? null : claimByKey.get(numberKey(reply.appName));
            if (claim == null) {
                throw new AuraHandledException('Claim not found (or not sent to the DWP yet): ' + reply.appName);
            }
            checks.add(
                new Claim_Check__c(
                    Basic__c = claim.Id,
                    Check_Agents__c = checkData.checkAgent,
                    Check_Date__c = Date.today(),
                    Not_Received__c = reply.notReceived == true,
                    Received_by_DWP__c = reply.received == true,
                    Processing__c = reply.processing == true,
                    More_Info_Requested__c = reply.moreInfo == true,
                    Approved__c = reply.approved == true,
                    Rejected__c = reply.rejected == true,
                    Lump_Sum_Letter__c = reply.lumpSum == true,
                    Payment_Started__c = reply.paymentStarted == true,
                    Called_DWP__c = reply.calledDwp == true,
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
    public static void addRequestCheckData(Id claimId) {
        if (claimId == null) return;
        User currentUser = [
            SELECT Username, FirstName
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];
        // same as the HMRC and Reapply checks: Monica asks from John's login
        String requestBy = currentUser.Username == 'jr@xtrapension.com' ? 'Monica' : currentUser.FirstName;
        update new Basic__c(
            Id = claimId,
            Check_Request_by__c = requestBy,
            Request_Check_Date__c = Date.today()
        );
    }

    // C00123, 00123 and 123 all point to the same claim
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
        public Boolean received {get; set;}
        @AuraEnabled
        public Boolean processing {get; set;}
        @AuraEnabled
        public Boolean moreInfo {get; set;}
        @AuraEnabled
        public Boolean approved {get; set;}
        @AuraEnabled
        public Boolean rejected {get; set;}
        @AuraEnabled
        public Boolean lumpSum {get; set;}
        @AuraEnabled
        public Boolean paymentStarted {get; set;}
        @AuraEnabled
        public Boolean calledDwp {get; set;}
        @AuraEnabled
        public String notes {get; set;}
        @AuraEnabled
        public String pdfLink {get; set;}
    }
}