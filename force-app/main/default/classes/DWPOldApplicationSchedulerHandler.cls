public class DWPOldApplicationSchedulerHandler {
    public void changeAppsStatusForOldApps() {
        Date oldDate = Date.today().addYears(-66) + 180;
        List<Application__c> updatedApps = new List<Application__c>();

        for(Application__c app : [
            SELECT
    	        Name,
    	        Status__c,
    	        Date_Of_Birth__c
            FROM Application__c
	        WHERE (Status__c = 'Posted' OR
                   Status__c = 'HMRC Reply 1' OR
                   Status__c = 'HMRC Reply 2') AND
                   Date_Of_Birth__c < :oldDate
        ]) {
            updatedApps.add(
                new Application__c(
                    Id = app.Id,
                    Status__c = 'DWP Teleclaim'
                )
            );
        }
        if (updatedApps.size() != 0) {
            update updatedApps;
        }
    }
}