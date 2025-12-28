public class CheckAgentDistributorSchedulerHandler {

    private Map<String, Integer> CHECK_AGENT_BY_EMPTY_APPS {
        get {
            CHECK_AGENT_BY_EMPTY_APPS = new Map<String, Integer>{
                'Clydel' => 0,
                'Daniel' => 0,
                'Hannah' => 0,
                'Vince'  => 0
            };
            for(Application__c app : [
	            SELECT
    	            Name,
    	            Check_Agent__c,
                    (SELECT Id FROM HMRC_Check_Requests__r)
                FROM Application__c
                WHERE (Status__c = 'Posted' OR
                       Status__c = '64-8 Bounce' OR
                       Status__c = 'HMRC Reply 1'  OR
                       Status__c = 'HMRC Reply 2'  OR
                       Status__c  = 'DWP Teleclaim' OR
                       Status__c = 'DWP 2 Emails Sent' OR
                       Status__c = 'XP Letter Sent') AND
                       Check_Agent__c != null
                ]) {
                if(app.HMRC_Check_Requests__r.size() == 0) {
    	            Integer countApps = CHECK_AGENT_BY_EMPTY_APPS.get(app.Check_Agent__c);
    	            if (countApps == null ) CHECK_AGENT_BY_EMPTY_APPS.put(app.Check_Agent__c, 1);
    	            else CHECK_AGENT_BY_EMPTY_APPS.put(app.Check_Agent__c, ++countApps);
                }
            }
            return CHECK_AGENT_BY_EMPTY_APPS;
        }
        private set;
    }

    public void assignedCheckUser() {
        Date day2WeeksAgo = Date.today().addDays(-14);
        List<Application__c> postedApps2WeeksAgo = [
            SELECT
                Id,
                Name,
                Tracking_Number_Sent_Date__c
            FROM Application__c
            WHERE Tracking_Number_Sent_Date__c = :day2WeeksAgo AND
                  Check_Agent__c = null
        ];
        if (postedApps2WeeksAgo.size() == 0) return;
        List<Application__c> updatedApps = new List<Application__c>();
        for (Application__c app : postedApps2WeeksAgo) {
            String assignAgent = getAssignedAgent();
            Integer countOfAssignedApps = CHECK_AGENT_BY_EMPTY_APPS.get(assignAgent);
            updatedApps.add(
                new Application__c(
                    Id = app.Id,
                    Check_Agent__c = assignAgent
                )
            );
            CHECK_AGENT_BY_EMPTY_APPS.put(assignAgent, ++countOfAssignedApps);
        }
        if (updatedApps.size() > 0) {
            update updatedApps;
        }
    }

    private String getAssignedAgent() {
        String agentName = '';
        List<String> checkAgent = new List<String> (CHECK_AGENT_BY_EMPTY_APPS.keySet());
        for (Integer i = 0; i < checkAgent.size()-1; i++) {
            if (i == 0) {
                agentName = checkAgent[i];
                continue;
            }
            if (CHECK_AGENT_BY_EMPTY_APPS.get(agentName) > CHECK_AGENT_BY_EMPTY_APPS.get(checkAgent[i + 1])) {
                agentName = checkAgent[i + 1];
            }
        }
        return agentName;
    }

}