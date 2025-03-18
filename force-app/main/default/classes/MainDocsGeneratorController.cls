public class MainDocsGeneratorController {

    @AuraEnabled(cacheable=true)
    public static string generateDocs(String recordId) {
        if (recordId == null) return 'Record Id is null';
        List<Application__c> apps = [
            SELECT Is_Generate_Client_Summary_PDF__c
            FROM Application__c
            WITH SECURITY_ENFORCED
        ];
        if (apps.size() == 0) {
            return 'Didn\'t find any records';
        }
        Application__c app = apps[0];
        System.enqueueJob(new GeneratePDFCallout(recordId));
        if (app.Is_Generate_Client_Summary_PDF__c == false) {
            CustomSummerPdf.generateClientSummary(recordId);
        }
        return 'Send Message';
    }
}