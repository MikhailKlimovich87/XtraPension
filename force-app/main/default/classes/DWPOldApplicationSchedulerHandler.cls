public class DWPOldApplicationSchedulerHandler {
    public void changeAppsStatusForOldApps() {
        List<Application__c> updatedApps = new List<Application__c>();
        for(Application__c app : [
            SELECT
    	        Name,
    	        Status__c,
                Date_Of_Birth__c
            FROM Application__c
            WHERE PK_Date_Pension_Age_Reached__c = null AND
    	         Date_Of_Birth__c != null AND
                (Status__c = 'Posted' OR
                 Status__c = 'HMRC Reply 1' OR
                 Status__c = 'HMRC Reply 2')
        ]) {
            Date pensionAge = PK_PortalUtils.calculatePensionDate(app.Date_Of_Birth__c);
            if(pensionAge != null) {
                updatedApps.add(
                    new Application__c(
                        Id = app.Id,
                        PK_Date_Pension_Age_Reached__c = pensionAge
                    )
                );
            }
        }
        if(updatedApps.size() > 0) {
            update updatedApps;
        }
        Date oldDate = Date.today().addMonths(4);
        List<Application__c> dwpApps = new List<Application__c>();

        for(Application__c app : [
            SELECT
    	        Name,
    	        Status__c,
    	        Date_Of_Birth__c,
                PK_Date_Pension_Age_Reached__c
            FROM Application__c
	        WHERE (Status__c = 'Posted' OR
                   Status__c = 'HMRC Reply 1' OR
                   Status__c = 'HMRC Reply 2') AND
                   PK_Date_Pension_Age_Reached__c < :oldDate
        ]) {
            dwpApps.add(
                new Application__c(
                    Id = app.Id,
                    Status__c = 'DWP Teleclaim'
                )
            );
        }
        if (dwpApps.size() != 0) {
            update dwpApps;
        }
    }
}