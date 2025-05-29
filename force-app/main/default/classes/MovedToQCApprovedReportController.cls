public without sharing class MovedToQCApprovedReportController {
    private static final List<User> ACTIVE_USERS{
        get {
            if (ACTIVE_USERS == null) {
                List<User> activeUsers = [
                    SELECT Name
                    FROM User
                    WHERE IsActive = true AND
                        (Name = 'Edryl Ranido' OR
                        Name = 'Daniel Gatdula' OR
                        Name = 'Camille Gittbao'  OR
                        Name = 'Maria Marmeto')
                ];
                if (!activeUsers.isEmpty()) {
                    ACTIVE_USERS = activeUsers;
                }
            }
            return ACTIVE_USERS;
        }
        private set;
    }

    @AuraEnabled(cacheable=true)
    public static ResultDataWrapper getReportData() {
        ResultDataWrapper result = new ResultDataWrapper();
        List<Application__history> historyData = [
            SELECT
                OldValue,
                NewValue,
                Parent.name,
                CreatedDate,
                CreatedBy.Name
            FROM Application__history
            WHERE CreatedDate = LAST_N_DAYS:180 AND
                  Field = 'Status__c' AND (
                  CreatedBy.Name = 'Edryl Ranido' OR
                  CreatedBy.Name = 'Daniel Gatdula' OR
                  CreatedBy.Name = 'Camille Gittbao' OR
                  CreatedBy.Name = 'Maria Marmeto')
            ORDER BY CreatedDate DESC];
        if (historyData.size() == 0) {
            return null;
        }
        Set<String> appNames = new Set<String>();
        List<Application__history> uniqueChanges = new List<Application__history>();
        for (Application__history change : historyData) {
            if (change.NewValue == 'QC Approved' && !appNames.contains(change.Parent.Name)) {
                uniqueChanges.add(change);
                appNames.add(change.Parent.Name);
            } else continue;
        }
        Map<Date, List<Application__history>> agentCheckChanges = new Map<Date, List<Application__history>>();
        for (Application__history history : uniqueChanges) {
            List<Application__history> currChange;
            if (agentCheckChanges.get(Date.valueOf(history.CreatedDate)) == null) {
                currChange = new List<Application__history>();
                currChange.add(history);
                agentCheckChanges.put(Date.valueOf(history.CreatedDate), currChange);
            } else if (agentCheckChanges.get(Date.valueOf(history.CreatedDate)) != null) {
                currChange = agentCheckChanges.get(Date.valueOf(history.CreatedDate));
                currChange.add(history);
                agentCheckChanges.put(Date.valueOf(history.CreatedDate), currChange);
            }
        }

        Date todayDate = Date.today();
        Date yesterdayDate = Date.today().addDays(-1);
        Date currentMonthStartDate = todayDate.toStartOfMonth();
        Date lastMonthStartDate = currentMonthStartDate.addMonths(-1);
        Date lastMonthEndDate = lastMonthStartDate.addMonths(1);
        Date currentWeekStartDate = todayDate.toStartOfWeek();
        Date lastWeekStartDate = currentWeekStartDate.addDays(-7);
        Date lastWeekEndDate = lastWeekStartDate.addDays(7);

        Integer currentMonth = todayDate.month();
        Integer currentQ =((currentMonth-1)/3) + 1;
        Date currentQtrEndDate = Date.newInstance(todayDate.year(),currentMonth + (4 - (currentMonth - ((currentQ -1)*3))) , 1).addDays(-1);
        Date currentQtrStartDate = currentQtrEndDate.addDays(1).addMonths(-3);
        Date lastQtrStartDate  = currentQtrStartDate.addMonths(-3);
        Date lastQtrEndDate = lastQtrStartDate.addMonths(3).addDays(-1);

        //Map<Date, Map<String, List<Application__history>>> agentCheckChangesCounter = new Map<Date, Map<String, List<Application__history>>>();
        Map<Date, Map<String, List<Application__history>>> todayAgentCheckChangesCounter = new Map<Date, Map<String, List<Application__history>>>();
        Map<Date, Map<String, List<Application__history>>> yesterdayAgentCheckChangesCounter = new Map<Date, Map<String, List<Application__history>>>();
        Map<Date, Map<String, List<Application__history>>> thisWeekAgentCheckChangesCounter = new Map<Date, Map<String, List<Application__history>>>();
        Map<Date, Map<String, List<Application__history>>> lastWeekAgentCheckChangesCounter = new Map<Date, Map<String, List<Application__history>>>();
        Map<Date, Map<String, List<Application__history>>> thisMonthAgentCheckChangesCounter = new Map<Date, Map<String, List<Application__history>>>();
        Map<Date, Map<String, List<Application__history>>> lastMonthAgentCheckChangesCounter = new Map<Date, Map<String, List<Application__history>>>();

        for (Date changeDate : agentCheckChanges.keySet()) {
            List<Application__history> currChange = agentCheckChanges.get(changeDate);
            Map<String, List<Application__history>> currMapChanges = new Map<String, List<Application__history>>();
            for (Application__history change : currChange) {
                List<Application__history> currChangeData;
                if (currMapChanges.get(change.CreatedBy.Name) == null) {
                    currChangeData = new List<Application__history>();
                } else currChangeData = currMapChanges.get(change.CreatedBy.Name);
                currChangeData.add(change);
                currMapChanges.put(change.CreatedBy.Name, currChangeData);
            }
            if (changeDate == todayDate) {
                todayAgentCheckChangesCounter.put(changeDate,currMapChanges);
            }
            if (changeDate == yesterdayDate) {
                yesterdayAgentCheckChangesCounter.put(changeDate,currMapChanges);
            }
            if (changeDate <= todayDate && changeDate >= currentWeekStartDate) {
                thisWeekAgentCheckChangesCounter.put(changeDate,currMapChanges);
            }
            if (changeDate < lastWeekEndDate && changeDate >= lastWeekStartDate) {
                lastWeekAgentCheckChangesCounter.put(changeDate,currMapChanges);
            }
            if (changeDate <= todayDate && changeDate >= currentMonthStartDate) {
                thisMonthAgentCheckChangesCounter.put(changeDate,currMapChanges);
            }
            if (changeDate < lastMonthEndDate && changeDate >= lastMonthStartDate) {
                lastMonthAgentCheckChangesCounter.put(changeDate,currMapChanges);
            }
        }

        result.activeUsers = ACTIVE_USERS;
        result.todayChanges = getChanges('Today', todayAgentCheckChangesCounter);
        result.yesterdayChanges = getChanges('Yesterday', yesterdayAgentCheckChangesCounter);
        result.thisWeekChanges = getChanges('This Week', thisWeekAgentCheckChangesCounter);
        result.lastWeekChanges = getChanges('Last Week', lastWeekAgentCheckChangesCounter);
        result.thisMonthChanges = getChanges('This Month', thisMonthAgentCheckChangesCounter);
        result.lastMonthChanges = getChanges('Last Month', lastMonthAgentCheckChangesCounter);
        return result;
    }

    private static PeriodData getChanges(String periodName, Map<Date, Map<String, List<Application__history>>> agentCheckChangesCounter) {
        List<PeriodData> fullChanges = new List<PeriodData>();
        for(Date changeDate : agentCheckChangesCounter.keySet()) {
            PeriodData usersData = new PeriodData();
            usersData.dataValue = new List<String>();
            Map<String, List<Application__history>> currChange= agentCheckChangesCounter.get(changeDate);
            usersData.dataValue.add(periodName);
            List<String> changes = new List<String>();
            for (User activeUser : ACTIVE_USERS) {
                if(currChange.get(activeUser.Name) == null) {
                    usersData.dataValue.add('0');
                } else usersData.dataValue.add(String.valueOf(currChange.get(activeUser.Name).size()));
            }
            fullChanges.add(usersData);
        }
        PeriodData finalResult = new PeriodData();
        finalResult.dataValue = new List<String>();
        finalResult.dataValue.add(periodName);
        for (Integer i = 0; i < fullChanges.size(); i++ ) {
            for (Integer j = 1; j < fullChanges[i].dataValue.size(); j++) {
                if (i == 0) {
                    finalResult.dataValue.add(fullChanges[i].dataValue[j]);
                } else {
                    finalResult.dataValue[j] = String.valueOf(Integer.valueOf(finalResult.dataValue[j]) +  Integer.valueOf(fullChanges[i].dataValue[j]));
                }
            }
        }
        return finalResult;
    }

    public class UserChanges {
        public Date dateValue {get; set;}
        public List<Integer> dataValue{get; set;}
    }

    public class PeriodData {
        @AuraEnabled
        public List<String> dataValue{get; set;}
    }

    public class ResultDataWrapper {
        @AuraEnabled
        public List<User> activeUsers{get; set;}
        @AuraEnabled
        public PeriodData todayChanges{get; set;}
        @AuraEnabled
        public PeriodData yesterdayChanges{get; set;}
        @AuraEnabled
        public PeriodData thisWeekChanges{get; set;}
        @AuraEnabled
        public PeriodData lastWeekChanges{get; set;}
        @AuraEnabled
        public PeriodData thisMonthChanges{get; set;}
        @AuraEnabled
        public PeriodData lastMonthChanges{get; set;}
    }

}