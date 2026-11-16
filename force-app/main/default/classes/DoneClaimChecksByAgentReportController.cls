// Claims version of DoneReapplyChecksByAgentReportController for the Agent's Checks site:
// Claim_Check__c records per check agent (today ... last quarter), no chart.
// Without sharing because the site runs as the guest user.
public without sharing class DoneClaimChecksByAgentReportController {

    @AuraEnabled(cacheable=true)
    public static DoneCheckRequestsByAgentReportController.AgentAppsWrapper getClaimCheckAgentsData() {
        DoneCheckRequestsByAgentReportController.AgentAppsWrapper result = new DoneCheckRequestsByAgentReportController.AgentAppsWrapper();
        Date today = Date.today();
        Date monthStart = today.toStartOfMonth();
        Date lastMonthStart = monthStart.addMonths(-1);
        Date weekStart = today.toStartOfWeek();
        Date lastWeekStart = weekStart.addDays(-7);
        Date qtrStart = Date.newInstance(today.year(), ((today.month() - 1) / 3) * 3 + 1, 1);
        Date lastQtrStart = qtrStart.addMonths(-3);

        List<String> agents = new List<String>();
        for (Schema.PicklistEntry entry : Claim_Check__c.Check_Agents__c.getDescribe().getPicklistValues()) {
            agents.add(entry.getValue());
        }
        result.agentsName = agents;

        List<String> periods = new List<String>{ 'Today', 'Yesterday', 'This Week', 'Last Week', 'This Month', 'Last Month', 'This Qtr', 'Last Qtr' };
        Map<String, Map<String, Integer>> countByPeriodAndAgent = new Map<String, Map<String, Integer>>();
        for (String period : periods) {
            Map<String, Integer> byAgent = new Map<String, Integer>();
            for (String agent : agents) byAgent.put(agent, 0);
            countByPeriodAndAgent.put(period, byAgent);
        }

        for (Claim_Check__c check : [
            SELECT Check_Agents__c, CreatedDate
            FROM Claim_Check__c
            WHERE CreatedDate >= :lastQtrStart
        ]) {
            Date day = check.CreatedDate.date();
            if (check.Check_Agents__c == null || !agents.contains(check.Check_Agents__c)) continue;
            List<String> hits = new List<String>();
            if (day == today) hits.add('Today');
            if (day == today.addDays(-1)) hits.add('Yesterday');
            if (day >= weekStart && day <= today) hits.add('This Week');
            if (day >= lastWeekStart && day < weekStart) hits.add('Last Week');
            if (day >= monthStart && day <= today) hits.add('This Month');
            if (day >= lastMonthStart && day < monthStart) hits.add('Last Month');
            if (day >= qtrStart && day <= today) hits.add('This Qtr');
            if (day >= lastQtrStart && day < qtrStart) hits.add('Last Qtr');
            for (String period : hits) {
                Map<String, Integer> byAgent = countByPeriodAndAgent.get(period);
                byAgent.put(check.Check_Agents__c, byAgent.get(check.Check_Agents__c) + 1);
            }
        }

        for (String period : periods) {
            DoneCheckRequestsByAgentReportController.DateDifferenceWrapper row = new DoneCheckRequestsByAgentReportController.DateDifferenceWrapper();
            row.name = period;
            for (String agent : agents) {
                Integer n = countByPeriodAndAgent.get(period).get(agent);
                row.countData.add(n);
                row.fullCount += n;
            }
            result.dateData.add(row);
        }
        return result;
    }
}