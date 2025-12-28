public without sharing class AgentSalesReportController {
    public static final String OBJECT_NAME = 'Application__c';
    public static final String FIELD_NAME ='Agent_Making_Sale__c';

    @AuraEnabled(cacheable=true)
    public static AgentSalesWrapper getAgentSalesApps() {
        AgentSalesWrapper result = new AgentSalesWrapper();
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

        List<Application__c> changedStatusApps = [
            SELECT
                Name,
                Agent_Making_Sale__c,
                Install_from_Website__c,
                Appeal_Application__c,
                CreatedDate
            FROM Application__c
            WHERE
                Agent_Making_Sale__c != null AND
                CreatedDate >= :lastQtrStartDate
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
        Map<String, List<Application__c>> agentNameByApps = new Map<String, List<Application__c>>();
        for (Application__c app : changedStatusApps) {
            List<Application__c> currentAgentsApps = agentNameByApps.get(app.Agent_Making_Sale__c);
            if (currentAgentsApps == null) {
                currentAgentsApps = new List<Application__c>();
            }
            currentAgentsApps.add(app);
            agentNameByApps.put(app.Agent_Making_Sale__c, currentAgentsApps);
        }
        List<AgentWrapper> agentsInfo = new List<AgentWrapper>();
        for (String name : agentsName) {
            List<Application__c> currentAgentApps = agentNameByApps.get(name);

            AgentWrapper agentData = new AgentWrapper();
            agentData.name = name;
            agentData.todayCount = 0;
            agentData.yesterdayCount = 0;
            agentData.thisWeekCount = 0;
            agentData.lastWeekCount = 0;
            agentData.thisMonthCount = 0;
            agentData.lastMonthCount = 0;
            agentData.thisQtrCount = 0;
            agentData.lastQtrCount = 0;
            if (currentAgentApps != null) {
                for (Application__c app : currentAgentApps) {
                    Integer count = app.Appeal_Application__c == true ? 2 : 1;
                    Date createdDate = app.CreatedDate.date();
                    if (createdDate == todayDate) {
                        agentData.todayCount+=count;
                    }
                    if (createdDate == yesterdayDate) {
                        agentData.yesterdayCount+=count;
                    }
                    if (createdDate <= todayDate && createdDate >= currentWeekStartDate) {
                        agentData.thisWeekCount+=count;
                    }
                    if (createdDate < lastWeekEndDate && createdDate >= lastWeekStartDate) {
                        agentData.lastWeekCount+=count;
                    }
                    if (createdDate <= todayDate && createdDate >= currentMonthStartDate) {
                        agentData.thisMonthCount+=count;
                    }
                    if (createdDate < lastMonthEndDate && createdDate >= lastMonthStartDate) {
                        agentData.lastMonthCount+=count;
                    }
                    if (createdDate <= currentQtrEndDate && createdDate >= currentQtrStartDate) {
                        agentData.thisQtrCount+=count;
                    }
                    if (createdDate <= lastQtrEndDate && createdDate >= lastQtrStartDate) {
                        agentData.lastQtrCount+=count;
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
            if (agentsInfo[i].name == 'Christina' ||
                agentsInfo[i].name == 'Carmel' ||
                agentsInfo[i].name == 'Kitty' ||
                agentsInfo[i].name == 'Ann-Louise' ||
                agentsInfo[i].name == 'John H' ||
                agentsInfo[i].name == 'Ciara' ||
                agentsInfo[i].name == 'Emma' ||
                agentsInfo[i].name == 'Elaine' ||
                agentsInfo[i].name == 'Barry' ||
                agentsInfo[i].name == 'Paul' ||
                agentsInfo[i].name == 'George (Irish)' ||
                agentsInfo[i].name == 'George (Aussie)' ||
                agentsInfo[i].name == 'Ciaran' ||
                agentsInfo[i].name == 'Amy' ||
                agentsInfo[i].name == 'Jamie' ||
                agentsInfo[i].name == 'George' ||
                agentsInfo[i].name == 'Brett' ||
                agentsInfo[i].name == 'John R' ||
                agentsInfo[i].name == 'Daniel' ||
                agentsInfo[i].name == 'Mike' ||
                agentsInfo[i].name == 'Gerard') {
            } else {
                todayWrapper.countData.add(agentsInfo[i].todayCount);
                yesterdayWrapper.countData.add(agentsInfo[i].yesterdayCount);
                thisWeekWrapper.countData.add(agentsInfo[i].thisWeekCount);
                lastWeekWrapper.countData.add(agentsInfo[i].lastWeekCount);
                thisMonthWrapper.countData.add(agentsInfo[i].thisMonthCount);
                lastMonthWrapper.countData.add(agentsInfo[i].lastMonthCount);
                thisQtrWrapper.countData.add(agentsInfo[i].thisQtrCount);
                lastQtrWrapper.countData.add(agentsInfo[i].lastQtrCount);
            }
        }
        result.dateData.add(todayWrapper);
        result.dateData.add(yesterdayWrapper);
        result.dateData.add(thisWeekWrapper);
        result.dateData.add(lastWeekWrapper);
        result.dateData.add(thisMonthWrapper);
        result.dateData.add(lastMonthWrapper);
        result.dateData.add(thisQtrWrapper);
        result.dateData.add(lastQtrWrapper);
        List<String> activeAgents = new List<String>();
        for( Schema.PicklistEntry pickListVal : ple) {
            String name = pickListVal.getValue();
            if (name == 'Christina' ||
                name == 'Carmel' ||
                name == 'Kitty' ||
                name == 'Ann-Louise' ||
                name == 'John H' ||
                name == 'Ciara' ||
                name == 'Emma' ||
                name == 'Elaine' ||
                name == 'Barry' ||
                name == 'Paul' ||
                name == 'George (Irish)' ||
                name == 'George (Aussie)' ||
                name == 'Ciaran' ||
                name == 'Amy' ||
                name == 'Jamie' ||
                name == 'George' ||
                name == 'Brett' ||
                name == 'John R' ||
                name == 'Daniel' ||
                name == 'Mike' ||
                name == 'Gerard') {
                continue;
            }
            activeAgents.add(name);
        }
        result.agentsName = activeAgents;
        Date last3MonthDate = todayDate.addMonths(-3);
        List<Application__c> last3MonthsApps = [
            SELECT
                Name,
                CreatedDate
            FROM Application__c
            WHERE CreatedDate >= :last3MonthDate
            ORDER BY CreatedDate DESC
        ];
        Map<String, List<String>> createdAppDateByListAppNames = new Map<String, List<String>>();
        for (Application__c app : last3MonthsApps) {
            List<String> appNames = createdAppDateByListAppNames.get(app.CreatedDate.format('dd MMM'));
            if(appNames == null) {
                appNames = new List<String>();
            }
            appNames.add(app.Name);
            createdAppDateByListAppNames.put(app.CreatedDate.format('dd MMM'),appNames);
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

    public class AgentSalesWrapper{
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
        public Integer todayCount;
        public Integer yesterdayCount;
        public Integer thisWeekCount;
        public Integer lastWeekCount;
        public Integer thisMonthCount;
        public Integer lastMonthCount;
        public Integer thisQtrCount;
        public Integer lastQtrCount;
    }

    public class DateAmountWrapper {
        @AuraEnabled
        public String dateName;
        @AuraEnabled
        public Integer amount;
    }
}