public without sharing class SalesByCountryReportController {
    public static final List<String> COUNTRIES = new List<String> {
        'Ireland',
        'Australia',
        'New Zealand',
        'South Africa',
        'Canada',
        'United States',
        'ROW'
    };

    @AuraEnabled(cacheable=true)
    public static SalesByCountriesWrapper getSalesByCountryApps(){
        SalesByCountriesWrapper result = new SalesByCountriesWrapper();
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

        List<Application__c> currApps = [
            SELECT
                Name,
                toLabel(Current_Address_Abroad__CountryCode__s),
                CreatedDate
            FROM Application__c
        ];

        Map<String, List<Application__c>> countryNameByApps = new Map<String, List<Application__c>>();
        for (Application__c app : currApps) {
            List<Application__c> currentCountryApps;
            if (!COUNTRIES.contains(app.Current_Address_Abroad__CountryCode__s)) {
                currentCountryApps = countryNameByApps.get('ROW');
            } else currentCountryApps = countryNameByApps.get(app.Current_Address_Abroad__CountryCode__s);
            if (currentCountryApps == null) {
                currentCountryApps = new List<Application__c>();
            }
            currentCountryApps.add(app);
            if (!COUNTRIES.contains(app.Current_Address_Abroad__CountryCode__s)) {
                countryNameByApps.put('ROW', currentCountryApps);
            } else countryNameByApps.put(app.Current_Address_Abroad__CountryCode__s, currentCountryApps);
        }
        List<CountryWrapper> countryInfo = new List<CountryWrapper>();
        for (String name : COUNTRIES) {
            List<Application__c> currentCountryApps = countryNameByApps.get(name);

            CountryWrapper countryData = new CountryWrapper();
            countryData.name = name;
            countryData.todayCount = 0;
            countryData.yesterdayCount = 0;
            countryData.thisWeekCount = 0;
            countryData.lastWeekCount = 0;
            countryData.thisMonthCount = 0;
            countryData.lastMonthCount = 0;
            countryData.thisQtrCount = 0;
            countryData.lastQtrCount = 0;
            countryData.allPeriod = 0;
            if (currentCountryApps != null) {
                for (Application__c app : currentCountryApps) {
                    Date createdDate = app.CreatedDate.date();
                    if (createdDate == todayDate) {
                        countryData.todayCount+=1;
                    }
                    if (createdDate == yesterdayDate) {
                        countryData.yesterdayCount+=1;
                    }
                    if (createdDate <= todayDate && createdDate >= currentWeekStartDate) {
                        countryData.thisWeekCount+=1;
                    }
                    if (createdDate < lastWeekEndDate && createdDate >= lastWeekStartDate) {
                        countryData.lastWeekCount+=1;
                    }
                    if (createdDate <= todayDate && createdDate >= currentMonthStartDate) {
                        countryData.thisMonthCount+=1;
                    }
                    if (createdDate < lastMonthEndDate && createdDate >= lastMonthStartDate) {
                        countryData.lastMonthCount+=1;
                    }
                    if (createdDate <= currentQtrEndDate && createdDate >= currentQtrStartDate) {
                        countryData.thisQtrCount+=1;
                    }
                    if (createdDate <= lastQtrEndDate && createdDate >= lastQtrStartDate) {
                        countryData.lastQtrCount+=1;
                    }
                    countryData.allPeriod+=1;
                }
            }
            countryInfo.add(countryData);
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
        DateDifferenceWrapper allTimeWrapper = new DateDifferenceWrapper();
        allTimeWrapper.name = 'All Time';
        for (CountryWrapper wrapper : countryInfo) {
            todayWrapper.countData.add(wrapper.todayCount);
            todayWrapper.fullCount += wrapper.todayCount;
            yesterdayWrapper.countData.add(wrapper.yesterdayCount);
            yesterdayWrapper.fullCount += wrapper.yesterdayCount;
            thisWeekWrapper.countData.add(wrapper.thisWeekCount);
            thisWeekWrapper.fullCount += wrapper.thisWeekCount;
            lastWeekWrapper.countData.add(wrapper.lastWeekCount);
            lastWeekWrapper.fullCount += wrapper.lastWeekCount;
            thisMonthWrapper.countData.add(wrapper.thisMonthCount);
            thisMonthWrapper.fullCount += wrapper.thisMonthCount;
            lastMonthWrapper.countData.add(wrapper.lastMonthCount);
            lastMonthWrapper.fullCount += wrapper.lastMonthCount;
            thisQtrWrapper.countData.add(wrapper.thisQtrCount);
            thisQtrWrapper.fullCount += wrapper.thisQtrCount;
            lastQtrWrapper.countData.add(wrapper.lastQtrCount);
            lastQtrWrapper.fullCount += wrapper.lastQtrCount;
            allTimeWrapper.countData.add(wrapper.allPeriod);
            allTimeWrapper.fullCount += wrapper.allPeriod;
        }
        result.dateData.add(todayWrapper);
        result.dateData.add(yesterdayWrapper);
        result.dateData.add(thisWeekWrapper);
        result.dateData.add(lastWeekWrapper);
        result.dateData.add(thisMonthWrapper);
        result.dateData.add(lastMonthWrapper);
        result.dateData.add(thisQtrWrapper);
        result.dateData.add(lastQtrWrapper);
        result.dateData.add(allTimeWrapper);

        return result;
    }

    public class SalesByCountriesWrapper{
        @AuraEnabled
        public List<DateDifferenceWrapper> dateData = new List<DateDifferenceWrapper>();
        @AuraEnabled
        public List<String> countryNames = COUNTRIES;
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

    public class CountryWrapper {
        public String name;
        public Integer todayCount;
        public Integer yesterdayCount;
        public Integer thisWeekCount;
        public Integer lastWeekCount;
        public Integer thisMonthCount;
        public Integer lastMonthCount;
        public Integer thisQtrCount;
        public Integer lastQtrCount;
        public Integer allPeriod;
    }

    public class DateAmountWrapper {
        @AuraEnabled
        public String dateName;
        @AuraEnabled
        public Integer amount;
    }
}