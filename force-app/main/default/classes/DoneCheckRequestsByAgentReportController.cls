public without sharing class DoneCheckRequestsByAgentReportController {
    public static final String OBJECT_NAME = 'HMRC_Check__c';
    public static final String FIELD_NAME ='Check_Agents__c';

    @AuraEnabled(cacheable=true)
    public static AgentAppsWrapper getCheckAgentsData() {
        AgentAppsWrapper result = new AgentAppsWrapper();
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

        List<HMRC_Check__c> checks = [
            SELECT
                Name,
                Check_Agents__c,
                CreatedDate
            FROM HMRC_Check__c
            WHERE CreatedDate >= :lastQtrStartDate
            ORDER BY CreatedDate DESC
        ];

        Schema.SObjectType objSobjectType = Schema.getGlobalDescribe().get(OBJECT_NAME);
        Schema.DescribeSObjectResult objDescribeSobject = objSobjectType.getDescribe();
        Map<String,Schema.SObjectField> fields = objDescribeSobject.fields.getMap();
        Schema.DescribeFieldResult fieldResult = fields.get(FIELD_NAME).getDescribe();
        List<Schema.PicklistEntry> ple = fieldResult.getPicklistValues();
        List<String> agentsName = new List<String>();
        for( Schema.PicklistEntry pickListVal : ple) {
            String name = pickListVal.getValue();
            agentsName.add(name);
        }
        result.agentsName = agentsName;
        Map<String, List<HMRC_Check__c>> agentNameByApps = new Map<String, List<HMRC_Check__c>>();
        for (HMRC_Check__c check : checks) {
            List<HMRC_Check__c> currentAgentsApps = agentNameByApps.get(check.Check_Agents__c);
            if (currentAgentsApps == null) {
                currentAgentsApps = new List<HMRC_Check__c>();
            }
            currentAgentsApps.add(check);
            agentNameByApps.put(check.Check_Agents__c, currentAgentsApps);
        }
        List<AgentWrapper> agentsInfo = new List<AgentWrapper>();
        for (String name : agentsName) {
            List<HMRC_Check__c> currentAgentApps = agentNameByApps.get(name);

            AgentWrapper agentData = new AgentWrapper();
            agentData.name = name;

            if (currentAgentApps != null) {
                for (HMRC_Check__c check : currentAgentApps) {
                    Date createdDate = check.CreatedDate.date();
                    if (createdDate == todayDate) {
                        agentData.todayCount+=1;
                    }
                    if (createdDate == yesterdayDate) {
                        agentData.yesterdayCount+=1;
                    }
                    if (createdDate <= todayDate && createdDate >= currentWeekStartDate) {
                        agentData.thisWeekCount+=1;
                    }
                    if (createdDate < lastWeekEndDate && createdDate >= lastWeekStartDate) {
                        agentData.lastWeekCount+=1;
                    }
                    if (createdDate <= todayDate && createdDate >= currentMonthStartDate) {
                        agentData.thisMonthCount+=1;
                    }
                    if (createdDate < lastMonthEndDate && createdDate >= lastMonthStartDate) {
                        agentData.lastMonthCount+=1;
                    }
                    if (createdDate <= currentQtrEndDate && createdDate >= currentQtrStartDate) {
                        agentData.thisQtrCount+=1;
                    }
                    if (createdDate <= lastQtrEndDate && createdDate >= lastQtrStartDate) {
                        agentData.lastQtrCount+=1;
                    }
                }
            }
            agentsInfo.add(agentData);
        }
        DateDifferenceWrapper todayWrapper = new DateDifferenceWrapper();
        todayWrapper.name = 'Today';
        DateDifferenceWrapper yesterdayWrapper = new DateDifferenceWrapper();
        yesterdayWrapper.name = 'Yesterday';
        DateDifferenceWrapper thisWeekWrapper = new DateDifferenceWrapper();
        thisWeekWrapper.name = 'This Week';
        DateDifferenceWrapper lastWeekWrapper = new DateDifferenceWrapper();
        lastWeekWrapper.name = 'Last Week';
        DateDifferenceWrapper thisMonthWrapper = new DateDifferenceWrapper();
        thisMonthWrapper.name = 'This Month';
        DateDifferenceWrapper lastMonthWrapper = new DateDifferenceWrapper();
        lastMonthWrapper.name = 'Last Month';
        DateDifferenceWrapper thisQtrWrapper = new DateDifferenceWrapper();
        thisQtrWrapper.name = 'This Qtr';
        DateDifferenceWrapper lastQtrWrapper = new DateDifferenceWrapper();
        lastQtrWrapper.name = 'Last Qtr';
        for (Integer i = 0; i< agentsInfo.size(); i++) {
            todayWrapper.fullCount += agentsInfo[i].todayCount;
            yesterdayWrapper.fullCount += agentsInfo[i].yesterdayCount;
            thisWeekWrapper.fullCount += agentsInfo[i].thisWeekCount;
            lastWeekWrapper.fullCount += agentsInfo[i].lastWeekCount;
            thisMonthWrapper.fullCount += agentsInfo[i].thisMonthCount;
            lastMonthWrapper.fullCount += agentsInfo[i].lastMonthCount;
            thisQtrWrapper.fullCount += agentsInfo[i].thisQtrCount;
            lastQtrWrapper.fullCount += agentsInfo[i].lastQtrCount;

            todayWrapper.countData.add(agentsInfo[i].todayCount);
            yesterdayWrapper.countData.add(agentsInfo[i].yesterdayCount);
            thisWeekWrapper.countData.add(agentsInfo[i].thisWeekCount);
            lastWeekWrapper.countData.add(agentsInfo[i].lastWeekCount);
            thisMonthWrapper.countData.add(agentsInfo[i].thisMonthCount);
            lastMonthWrapper.countData.add(agentsInfo[i].lastMonthCount);
            thisQtrWrapper.countData.add(agentsInfo[i].thisQtrCount);
            lastQtrWrapper.countData.add(agentsInfo[i].lastQtrCount);

        }
        result.dateData.add(todayWrapper);
        result.dateData.add(yesterdayWrapper);
        result.dateData.add(thisWeekWrapper);
        result.dateData.add(lastWeekWrapper);
        result.dateData.add(thisMonthWrapper);
        result.dateData.add(lastMonthWrapper);
        result.dateData.add(thisQtrWrapper);
        result.dateData.add(lastQtrWrapper);

        Date last3MonthDate = todayDate.addMonths(-3);
        List<HMRC_Check__c> last3MonthsChecks = [
            SELECT
                Name,
                Check_Agents__c,
                CreatedDate
            FROM HMRC_Check__c
            WHERE CreatedDate >= :last3MonthDate
            ORDER BY CreatedDate DESC
        ];
        Map<String, List<String>> createdAppDateByListAppNames = new Map<String, List<String>>();
        for (HMRC_Check__c check : last3MonthsChecks) {
            List<String> appNames = createdAppDateByListAppNames.get(check.CreatedDate.format('dd MMM'));
            if(appNames == null) {
                appNames = new List<String>();
            }
            appNames.add(check.Name);
            createdAppDateByListAppNames.put(check.CreatedDate.format('dd MMM'),appNames);
        }
        if (createdAppDateByListAppNames.size() != 0) {
            for (String dayOfDate : createdAppDateByListAppNames.keySet()) {
                DateAmountWrapper dayWrapper = new DateAmountWrapper();
                dayWrapper.dateName = dayOfDate;
                dayWrapper.amount = createdAppDateByListAppNames.get(dayOfDate).size();
                result.amountByDay.add(dayWrapper);
            }
        }
        return result;
    }

    public class AgentAppsWrapper{
        @AuraEnabled
        public List<DateDifferenceWrapper> dateData = new List<DateDifferenceWrapper>();
        @AuraEnabled
        public List<String> agentsName = new List<String>();
        @AuraEnabled
        public List<DateAmountWrapper> amountByDay = new List<DateAmountWrapper>();
    }

    public class DateDifferenceWrapper {
        @AuraEnabled
        public String name;
        @AuraEnabled
        public List<Integer> countData = new List<Integer>();
        @AuraEnabled
        public Integer fullCount = 0;
    }

    public class AgentWrapper {
        public String name;
        public Integer todayCount = 0;
        public Integer yesterdayCount = 0;
        public Integer thisWeekCount = 0;
        public Integer lastWeekCount = 0;
        public Integer thisMonthCount = 0;
        public Integer lastMonthCount = 0;
        public Integer thisQtrCount = 0;
        public Integer lastQtrCount = 0;
    }

    public class DateAmountWrapper {
        @AuraEnabled
        public String dateName;
        @AuraEnabled
        public Integer amount;
    }
}