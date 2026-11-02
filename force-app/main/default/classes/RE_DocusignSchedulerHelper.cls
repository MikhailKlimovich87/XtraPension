public with sharing class RE_DocusignSchedulerHelper {
    
    // Constants for status values
    private static final String STATUS_FORM_COMPLETED = 'Form Completed';
    
    public void sendFilesToDocusign() {
        List<Reapply__c> reapplyList = [
            SELECT
                Id,
                First_Name__c,
                Second_Name__c, 
                Application__r.Email__c,
                Application__r.Contact__c,
                Status__c
            FROM Reapply__c
            WHERE Status__c = :STATUS_FORM_COMPLETED 
            AND Form_Complete_Date__c <= :Date.today().addDays(-2)
            LIMIT 50
        ];
        
        if (reapplyList.isEmpty()) {
            return;
        }
        
        // Process each record asynchronously
        Set<Id> reapplyIds = new Map<Id, Reapply__c>(reapplyList).keySet();
        sendFilesToDocusignBatch(reapplyIds);
    }
    
    @future(callout=true)
    public static void sendFilesToDocusignBatch(Set<Id> reapplyIds) {
        List<Reapply__c> updatesToProcess = new List<Reapply__c>();
        List<Reapply__c> updatesWithErrors = new List<Reapply__c>();
        
        for (Id reapplyId : reapplyIds) {
            try {
                RE_DocuSignController.ResponseWrapper response = 
                    RE_DocuSignController.sendEnvelopeMethod(reapplyId);
                
                if (!response.isSuccess) {
                    // Log the error and update status
                    System.debug('Error sending envelope for Reapply ' + reapplyId + 
                                ': ' + response.errorMessage);
                    
                    Reapply__c errorRecord = new Reapply__c(
                        Id = reapplyId,
                        Docusign_Error_Message__c = response.errorMessage // Add this field to your object
                    );
                    updatesWithErrors.add(errorRecord);
                }
            } catch (Exception e) {
                System.debug('Exception sending envelope for Reapply ' + reapplyId + 
                            ': ' + e.getMessage());
                
                Reapply__c errorRecord = new Reapply__c(
                    Id = reapplyId,
                    Docusign_Error_Message__c = e.getMessage()
                );
                updatesWithErrors.add(errorRecord);
            }
        }
        // Update records with errors
        if (!updatesWithErrors.isEmpty()) {
            try {
                update updatesWithErrors;
            } catch (Exception e) {
                System.debug('Failed to update error statuses: ' + e.getMessage());
            }
        }
    }

}