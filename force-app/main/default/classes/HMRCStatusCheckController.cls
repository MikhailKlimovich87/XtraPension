public class HMRCStatusCheckController {
    public static Map<String, Integer> totalSummary = new Map<String, Integer>{
       'Not Received'     => 0,
       'Processing'       => 0,
       'Sent to (Client)' => 0,
       'Sent to (Agent)'  => 0,
       'Sent to (Both)'   => 0,
       'C2'               => 0,
       'C3'               => 0,
       'Work Item'        => 0,
       'DWP'              => 0,
       'BadNINO'          => 0,
       'No 64-8'          => 0,
       'BadInfo'          => 0,
       'Rejected'         => 0
    };



    @AuraEnabled(cacheable=true)
    public static GetDataWrapper getRepeatedApps() {
        GetDataWrapper getResult = new GetDataWrapper();
        List<Application__c> repeatedApps = [
            SELECT
                Name,
                First_Name__c,
                Second_Name__c,
                Status__c,
                Not_Received__c,
                Processing__c,
                Sent_to__c,
                Sent_Date__c,
                C2__c,
                C3__c,
                Work_Item__c,
                DWP__c,
                BadNINO__c,
                BadInfo__c,
                No_64_8__c,
                Rejected__c,
                Notes__c,
                Repeat_EDITS_NO_EDITS_Date__c,
                Recheck_Date__c,
                X64_8_Repost__c,
                Recheck_64_8__c,
                Days_Since_Posted__c,
                National_Insurance_Number__c,
                Date_Of_Birth__c,
                Full_Current_Address_Abroad__c,
                Related_Contact_Phone__c
            FROM Application__c
            WHERE Amount_PH_Responses__c > 1 AND
                  (Status__c = 'Posted' OR
                   Status__c = 'HMRC Reply 1' OR
                   Status__c = 'HMRC Reply 2' OR
                   Status__c = 'XP Letter Sent' OR
                   Status__c = 'REPEAT(edits)' OR
                   Status__c = 'REPEAT(NO edits)')
            ORDER BY Name DESC
        ];
        if (!repeatedApps.isEmpty()) {
            getResult.repeatedApps = repeatedApps;
            for (Application__c app : repeatedApps) {
                if (app.Not_Received__c == true) {
                    Integer notReceivedAmount = totalSummary.get('Not Received') + 1;
                    totalSummary.put('Not Received', notReceivedAmount);
                }
                if (app.Processing__c == true) {
                    Integer processingAmount = totalSummary.get('Processing') + 1;
                    totalSummary.put('Processing', processingAmount);
                }
                if (app.Sent_to__c == 'Client') {
                    Integer processingClientAmount = totalSummary.get('Sent to (Client)') + 1;
                    totalSummary.put('Sent to (Client)', processingClientAmount);
                }
                if (app.Sent_to__c == 'Agent') {
                    Integer processingAgentAmount = totalSummary.get('Sent to (Agent)') + 1;
                    totalSummary.put('Sent to (Agent)', processingAgentAmount);
                }
                if (app.Sent_to__c == 'Both') {
                    Integer processingBothAmount = totalSummary.get('Sent to (Both)') + 1;
                    totalSummary.put('Sent to (Both)', processingBothAmount);
                }
                if (app.C2__c == true) {
                    Integer c2Amount = totalSummary.get('C2') + 1;
                    totalSummary.put('C2', c2Amount);
                }
                if (app.C3__c == true) {
                    Integer c3Amount = totalSummary.get('C3') + 1;
                    totalSummary.put('C3', c3Amount);
                }
                if (app.Work_Item__c == true) {
                    Integer workItemAmount = totalSummary.get('Work Item') + 1;
                    totalSummary.put('Work Item', workItemAmount);
                }
                if (app.DWP__c == true) {
                    Integer dwpAmount = totalSummary.get('DWP') + 1;
                    totalSummary.put('DWP', dwpAmount);
                }
                if (app.BadNINO__c == true) {
                    Integer badNINO_Amount = totalSummary.get('BadNINO') + 1;
                    totalSummary.put('BadNINO', badNINO_Amount);
                }
                if (app.No_64_8__c == true) {
                    Integer no64_8Amount = totalSummary.get('No 64-8') + 1;
                    totalSummary.put('No 64-8', no64_8Amount);
                }
                if (app.BadInfo__c == true) {
                    Integer badInfoAmount = totalSummary.get('BadInfo') + 1;
                    totalSummary.put('BadInfo', badInfoAmount);
                }
                if (app.Rejected__c == true) {
                    Integer rejectedAmount = totalSummary.get('Rejected') + 1;
                    totalSummary.put('Rejected', rejectedAmount);
                }
            }
            getResult.totalData = totalSummary;
        }
        return getResult;
    }

    @AuraEnabled
    public static ResultUpdateWrapper updateCurrentApplication(ChangeDataWrapper inputData) {
        ResultUpdateWrapper result = new ResultUpdateWrapper();
        if (inputData == null) {
            result.isError = true;
            result.errorMessage = 'Input data is empty';
            return result;
        }
        try {
            SObjectType r = ((SObject)(Type.forName('Schema.Application__c').newInstance())).getSObjectType();
            DescribeSObjectResult d = r.getDescribe();
            String currFieldType = d.fields.getMap().get(inputData?.fieldName).getDescribe().getType().toString();
            Application__c updateApp = new Application__c(
                Id = inputData?.appId
            );
            Object newValue;
            if (currFieldType == 'BOOLEAN') {
                newValue = Boolean.valueOf(inputData?.newFieldValue);
            } else if (currFieldType == 'DATE') {
                newValue = Date.valueOf(inputData?.newFieldValue);
            } else newValue = inputData?.newFieldValue;
            updateApp.put(inputData?.fieldName, newValue);
            update updateApp;
            result.isSuccess = true;
            return result;
        } catch (Exception ex) {
            result.isError = true;
            result.errorMessage = ex.getMessage();
            return result;
        }
    }

    public class ChangeDataWrapper {
        @AuraEnabled
        public String fieldName {get; set;}
        @AuraEnabled
        public String newFieldValue {get; set;}
        @AuraEnabled
        public String appId {get; set;}
    }

    public class ResultUpdateWrapper {
        @AuraEnabled
        public Boolean isError = false;
        @AuraEnabled
        public Boolean isSuccess = false;
        @AuraEnabled
        public String  errorMessage {get; set;}
    }

    public class GetDataWrapper {
        @AuraEnabled
        public List<Application__c> repeatedApps{get; set;}
        @AuraEnabled
        public Map<String, Integer> totalData {get; set;}
    }
}