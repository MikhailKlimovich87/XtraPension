public class ApplicationPathController {

    @AuraEnabled
    public static String saveAppStatus(String statusName, String recordId) {
        if (statusName != null && recordId != null) {
            update new Application__c (
                Id = recordId,
                Status__c = statusName,
                Agent_Status__c = statusName
            );
            return 'Success';
        }
        return null;
    }
}