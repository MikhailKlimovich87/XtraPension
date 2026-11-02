public class PK_DataHelper {
    public static Map<String, Object> findReapply(RE_RequestWrapper.ReapplyDataWrapper reapplyData) {
        Map<String, Object> result = new Map<String, Object>();
        RE_ResponseWrapper.ApplicationDataWrapper appDataWrapper = new RE_ResponseWrapper.ApplicationDataWrapper();
        try {
            if (reapplyData.recordId == null) {
                result.put('status', 'error');
                result.put('message', 'Record ID is null');
                return result;
            }
            List<Reapply__c> reapplies = [
                SELECT Application__c 
                FROM Reapply__c
                WHERE Id = :reapplyData.recordId
                LIMIT 1
            ];
            if (reapplies.size() == 0) {
                result.put('status', 'error');
                result.put('message', 'Reapply record not found');
                return result;
            }
            Reapply__c reapply = reapplies[0];
            if (reapply.Application__c == null) {
                result.put('status', 'error');
                result.put('message', 'Application ID is null in Reapply record');
                return result;
            }
            List<Application__History> appHistories = [
                SELECT
                    OldValue,
                    NewValue 
                FROM Application__History 
                WHERE Field = 'Years_Of_Work_In_The_UK__c' 
                AND ParentId = :reapply.Application__c 
                ORDER BY CreatedDate
            ];
            if (appHistories.size() > 0) {
                Application__History firstHistory = appHistories[0];
                Application__History lastHistory = appHistories[appHistories.size() - 1];
                appDataWrapper.ukYears = String.valueOf(firstHistory.OldValue);
                appDataWrapper.payNationalInsuranceYears = String.valueOf(lastHistory.NewValue);
            }
            result.put('status', 'success');
            result.put('reapply', appDataWrapper);
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getMessage());
        }
        return result;
    }
}