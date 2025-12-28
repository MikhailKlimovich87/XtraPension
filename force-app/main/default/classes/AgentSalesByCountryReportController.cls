public without sharing class AgentSalesByCountryReportController {
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
                CreatedDate,
                Current_Address_Abroad__CountryCode__s,
                CurrencyIsoCode
            FROM Application__c
            WHERE
                Agent_Making_Sale__c != null AND
                CreatedDate >= :lastQtrStartDate
        ];
        Map<String, List<Application__c>> durationByCurrentApps = new Map<String, List<Application__c>>();
        for (Application__c app : changedStatusApps) {
            Date createdDate = app.CreatedDate.date();
            if (createdDate == todayDate) {
                List<Application__c> currApps = durationByCurrentApps.get('TODAY');
                if(currApps == null) currApps = new List<Application__c>{app};
                else currApps.add(app);
                durationByCurrentApps.put('TODAY', currApps);
            }
            if (createdDate == yesterdayDate) {
                List<Application__c> currApps = durationByCurrentApps.get('YESTERDAY');
                if(currApps == null) currApps = new List<Application__c>{app};
                else currApps.add(app);
                durationByCurrentApps.put('YESTERDAY', currApps);
            }
            if (createdDate <= todayDate && createdDate >= currentWeekStartDate) {
                List<Application__c> currApps = durationByCurrentApps.get('THIS WEEK');
                if(currApps == null) currApps = new List<Application__c>{app};
                else currApps.add(app);
                durationByCurrentApps.put('THIS WEEK', currApps);
            }
            if (createdDate < lastWeekEndDate && createdDate >= lastWeekStartDate) {
                List<Application__c> currApps = durationByCurrentApps.get('LAST WEEK');
                if(currApps == null) currApps = new List<Application__c>{app};
                else currApps.add(app);
                durationByCurrentApps.put('LAST WEEK', currApps);
            }
            if (createdDate <= todayDate && createdDate >= currentMonthStartDate) {
                List<Application__c> currApps = durationByCurrentApps.get('THIS MONTH');
                if(currApps == null) currApps = new List<Application__c>{app};
                else currApps.add(app);
                durationByCurrentApps.put('THIS MONTH', currApps);
            }
            if (createdDate < lastMonthEndDate && createdDate >= lastMonthStartDate) {
                List<Application__c> currApps = durationByCurrentApps.get('LAST MONTH');
                if(currApps == null) currApps = new List<Application__c>{app};
                else currApps.add(app);
                durationByCurrentApps.put('LAST MONTH', currApps);
            }
            if (createdDate <= currentQtrEndDate && createdDate >= currentQtrStartDate) {
                List<Application__c> currApps = durationByCurrentApps.get('THIS QTR');
                if(currApps == null) currApps = new List<Application__c>{app};
                else currApps.add(app);
                durationByCurrentApps.put('THIS QTR', currApps);
            }
            if (createdDate <= lastQtrEndDate && createdDate >= lastQtrStartDate) {
                List<Application__c> currApps = durationByCurrentApps.get('LAST QTR');
                if(currApps == null) currApps = new List<Application__c>{app};
                else currApps.add(app);
                durationByCurrentApps.put('LAST QTR', currApps);
            }
        }

        Schema.SObjectType objSobjectType = Schema.getGlobalDescribe().get(OBJECT_NAME);
        Schema.DescribeSObjectResult objDescribeSobject = objSobjectType.getDescribe();
        Map<String,Schema.SObjectField> fields = objDescribeSobject.fields.getMap();
        Schema.DescribeFieldResult fieldResult = fields.get(FIELD_NAME).getDescribe();
        List<Schema.PicklistEntry> ple = fieldResult.getPicklistValues();
        List<String> agentsName = new List<String>();
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
            agentsName.add(name);
        }
        result.agentsName = agentsName;

        result.dateData.addAll(addRowData('TODAY', durationByCurrentApps.get('TODAY'), agentsName).dateData);
        result.dateData.addAll(addRowData('YESTERDAY', durationByCurrentApps.get('YESTERDAY'), agentsName).dateData);
        result.dateData.addAll(addRowData('THIS WEEK', durationByCurrentApps.get('THIS WEEK'), agentsName).dateData);
        result.dateData.addAll(addRowData('LAST WEEK', durationByCurrentApps.get('LAST WEEK'), agentsName).dateData);
        result.dateData.addAll(addRowData('THIS MONTH', durationByCurrentApps.get('THIS MONTH'), agentsName).dateData);
        result.dateData.addAll(addRowData('LAST MONTH', durationByCurrentApps.get('LAST MONTH'), agentsName).dateData);
        result.dateData.addAll(addRowData('THIS QTR', durationByCurrentApps.get('THIS QTR'), agentsName).dateData);
        result.dateData.addAll(addRowData('LAST QTR', durationByCurrentApps.get('LAST QTR'), agentsName).dateData);
        for (Integer i = 0; i < result.dateData.size(); i++) {
            result.dateData[i].key = i;
        }
        return result;
    }

    private static AgentSalesWrapper addRowData(String blockName, List<Application__c> changedStatusApps, List<String> agentsName) {
        AgentSalesWrapper result = new AgentSalesWrapper();
        Date todayDate = Date.today();
        Map<String, List<Application__c>> agentNameByApps = new Map<String, List<Application__c>>();
        if (changedStatusApps != null) {
            for (Application__c app : changedStatusApps) {
                List<Application__c> currentAgentsApps = agentNameByApps.get(app.Agent_Making_Sale__c);
                if (currentAgentsApps == null) {
                    currentAgentsApps = new List<Application__c>();
                }
                currentAgentsApps.add(app);
                agentNameByApps.put(app.Agent_Making_Sale__c, currentAgentsApps);
            }
        }
        List<AgentWrapper> agentsInfo = new List<AgentWrapper>();
        for (String name : agentsName) {
            List<Application__c> currentAgentApps = agentNameByApps.get(name);
            AgentWrapper agentData = new AgentWrapper();
            agentData.name = name;
            agentData.todayCount = 0;
            agentData.australianCount = 0;
            agentData.irelandCount = 0;
            agentData.australianCount = 0;
            agentData.southAfricaCount = 0;
            agentData.canadaCount = 0;
            agentData.newZealandCount = 0;
            agentData.europeCount = 0;
            agentData.rowCount = 0;
            agentData.unitedStatesCount = 0;

            if (currentAgentApps != null) {
                for (Application__c app : currentAgentApps) {
                    Integer count = app.Appeal_Application__c == true ? 2 : 1;
                    Date createdDate = app.CreatedDate.date();
                    agentData.todayCount+=count;
                    if (app.Current_Address_Abroad__CountryCode__s == 'AU') {
                        agentData.australianCount+=count;
                    }
                    if (app.Current_Address_Abroad__CountryCode__s == 'IE') {
                        agentData.irelandCount+=count;
                    }
                    if (app.Current_Address_Abroad__CountryCode__s == 'ZA') {
                        agentData.southAfricaCount+=count;
                    }
                    if (app.Current_Address_Abroad__CountryCode__s == 'US') {
                        agentData.unitedStatesCount+=count;
                    }
                    if (app.Current_Address_Abroad__CountryCode__s == 'CA') {
                        agentData.canadaCount+=count;
                    }
                    if (app.Current_Address_Abroad__CountryCode__s == 'NZ') {
                        agentData.newZealandCount+=count;
                    }
                    if (app.Current_Address_Abroad__CountryCode__s != 'IE' && app.CurrencyIsoCode == 'EUR') {
                        agentData.europeCount+=count;
                    }
                    if (app.Current_Address_Abroad__CountryCode__s != 'IE' &&
                               app.Current_Address_Abroad__CountryCode__s != 'AU' &&
                               app.Current_Address_Abroad__CountryCode__s != 'ZA'&&
                               app.Current_Address_Abroad__CountryCode__s != 'US'&&
                               app.Current_Address_Abroad__CountryCode__s != 'CA'&&
                               app.Current_Address_Abroad__CountryCode__s != 'NZ' &&
                               app.CurrencyIsoCode != 'EUR') {
                        agentData.rowCount+=count;
                    }
                }
            }
            agentsInfo.add(agentData);
        }
        DateDifferenceWrapper todayWrapper = new DateDifferenceWrapper();
        todayWrapper.name = blockName;
        todayWrapper.fontBold = 'font-weight:bold;background-color:silver';
        DateDifferenceWrapper irelandWrapper = new DateDifferenceWrapper();
        irelandWrapper.name = 'Ireland';
        DateDifferenceWrapper australianWrapper = new DateDifferenceWrapper();
        australianWrapper.name = 'Australia';
        DateDifferenceWrapper canadaWrapper = new DateDifferenceWrapper();
        canadaWrapper.name = 'Canada';
        DateDifferenceWrapper southAfricaWrapper = new DateDifferenceWrapper();
        southAfricaWrapper.name = 'South Africa';
        DateDifferenceWrapper newZealandWrapper = new DateDifferenceWrapper();
        newZealandWrapper.name = 'New Zealand';
        DateDifferenceWrapper europeWrapper = new DateDifferenceWrapper();
        europeWrapper.name = 'Europe';
        DateDifferenceWrapper unitedStatesWrapper = new DateDifferenceWrapper();
        unitedStatesWrapper.name = 'United States';
        DateDifferenceWrapper rowWrapper = new DateDifferenceWrapper();
        rowWrapper.name = 'Row';
        for (Integer i = 0; i< agentsInfo.size(); i++) {
            todayWrapper.fullCount += agentsInfo[i].todayCount;
            irelandWrapper.fullCount += agentsInfo[i].irelandCount;
            australianWrapper.fullCount += agentsInfo[i].australianCount;
            canadaWrapper.fullCount += agentsInfo[i].canadaCount;
            southAfricaWrapper.fullCount += agentsInfo[i].southAfricaCount;
            newZealandWrapper.fullCount += agentsInfo[i].newZealandCount;
            europeWrapper.fullCount += agentsInfo[i].europeCount;
            rowWrapper.fullCount += agentsInfo[i].rowCount;
            unitedStatesWrapper.fullCount += agentsInfo[i].unitedStatesCount;

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
                irelandWrapper.countData.add(agentsInfo[i].irelandCount);
                australianWrapper.countData.add(agentsInfo[i].australianCount);
                canadaWrapper.countData.add(agentsInfo[i].canadaCount);
                southAfricaWrapper.countData.add(agentsInfo[i].southAfricaCount);
                newZealandWrapper.countData.add(agentsInfo[i].newZealandCount);
                europeWrapper.countData.add(agentsInfo[i].europeCount);
                rowWrapper.countData.add(agentsInfo[i].rowCount);
                unitedStatesWrapper.countData.add(agentsInfo[i].unitedStatesCount);
            }
        }
        result.dateData.add(todayWrapper);
        result.dateData.add(irelandWrapper);
        result.dateData.add(australianWrapper);
        result.dateData.add(canadaWrapper);
        result.dateData.add(southAfricaWrapper);
        result.dateData.add(newZealandWrapper);
        result.dateData.add(europeWrapper);
        result.dateData.add(unitedStatesWrapper);
        result.dateData.add(rowWrapper);

        return result;
    }

    public class AgentSalesWrapper{
        @AuraEnabled
        public List<DateDifferenceWrapper> dateData = new List<DateDifferenceWrapper>();
        @AuraEnabled
        public List<String> agentsName = new List<String>();
    }

    public class DateDifferenceWrapper {
        @AuraEnabled
        public String name;
        @AuraEnabled
        public List<Integer> countData = new List<Integer>();
        @AuraEnabled
        public Integer fullCount = 0;
        @AuraEnabled
        public Integer key = 0;
        @AuraEnabled
        public String fontBold;
    }

    public class AgentWrapper {
        public String name;
        public Integer todayCount;
        public Integer irelandCount;
        public Integer australianCount;
        public Integer southAfricaCount;
        public Integer canadaCount;
        public Integer newZealandCount;
        public Integer europeCount;
        public Integer unitedStatesCount;
        public Integer rowCount;
    }
}