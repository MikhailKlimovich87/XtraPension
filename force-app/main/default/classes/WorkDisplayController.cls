public class WorkDisplayController {
    @AuraEnabled
    public static ResultData getApplication(String recordId) {
        List<Employer__c> lastUkEmployer= [
            SELECT
                Id,
                End_Date__c,
                Employer_Name__c,
                Employers_Address__PostalCode__s,
                Type_Of_UK_Employment__c
            FROM Employer__c
            WHERE Application__c =: recordId
                AND Type__c = 'UK Work'
            LIMIT 1
        ];
        List<Employer__c> afterUKEmployers = [
            SELECT
                Id,
                Start_Date__c,
                Type_Of_After_UK_Employment__c
            FROM Employer__c
            WHERE Application__c =: recordId
                AND Type__c = 'Work After UK'
                //AND Is_First_Employer__c = true
            ORDER BY Start_Date__c ASC
            LIMIT 1
        ];

        ResultData result = new ResultData();
        result.lastUKEmployerId       = !lastUkEmployer.isEmpty() ? lastUkEmployer[0] : null;
        result.firstAfterUKEmployerId = !afterUKEmployers.isEmpty() ? afterUKEmployers[0].Id : null;
        result.lastUKWorkLastDate     = !lastUkEmployer.isEmpty() ? ((Datetime)lastUkEmployer[0].End_Date__c).format('EEE dd MMM yyyy') : null;
        result.abroadStartDate        = !afterUKEmployers.isEmpty() ? ((Datetime)afterUKEmployers[0].Start_Date__c).format('EEE dd MMM yyyy') : null;
        result.typeOfAfterUKEmployer  = !afterUKEmployers.isEmpty() ? afterUKEmployers[0].Type_Of_After_UK_Employment__c : null;

        result.status = 'Success';
        return result;
    }

    @AuraEnabled
    public static ResultAddressesData getUKAddresses(String recordId) {
        String queryLine =
            'SELECT ' +
                'Previous_UK_Address_1__City__s, ' +
                'Previous_UK_Address_1__CountryCode__s, ' +
                'Previous_UK_Address_1__PostalCode__s, ' +
                'Previous_UK_Address_1__StateCode__s, ' +
                'Previous_UK_Address_1__Street__s, ' +
                'Previous_UK_Address_1_Country__c, ' +
                'Previous_UK_Address1_State__c, ' +
                'Previous_UK_Address_2__City__s, ' +
                'Previous_UK_Address_2__CountryCode__s, ' +
                'Previous_UK_Address_2__PostalCode__s, ' +
                'Previous_UK_Address_2__StateCode__s, ' +
                'Previous_UK_Address_2__Street__s, ' +
                'Previous_UK_Address_2_Country__c, ' +
                'Previous_UK_Address2_State__c, ' +
                'Previous_UK_Address_3__City__s, ' +
                'Previous_UK_Address_3__CountryCode__s, ' +
                'Previous_UK_Address_3__PostalCode__s, ' +
                'Previous_UK_Address_3__StateCode__s, ' +
                'Previous_UK_Address_3__Street__s, ' +
                'Previous_UK_Address_3_Country__c, ' +
                'Previous_UK_Address3_State__c, ' +
                'Current_Address_Abroad__City__s, ' +
                'Current_Address_Abroad__CountryCode__s, ' +
                'Current_Address_Abroad__PostalCode__s, ' +
                'Current_Address_Abroad__StateCode__s, ' +
                'Current_Address_Abroad__Street__s, ' +
                'Current_Address_Abroad_Country__c, ' +
                'Current_Address_Abroad_State__c ' +
            'FROM Application__c ' +
            'WHERE Id =: recordId ' +
            'LIMIT 1';
            ResultAddressesData result = new ResultAddressesData();
            result.ukAddresses = new List<AddressData>();
            try {
                Application__c app = Database.query(queryLine);
                for (Integer i = 1; i <= 3; i++) {
                    if(app.get('Previous_UK_Address_' + i + '__City__s') != null ) {
                        AddressData address = new AddressData();
                        address.city       = (String)app.get('Previous_UK_Address_' + i + '__City__s');
                        address.street     = (String)app.get('Previous_UK_Address_' + i + '__Street__s');
                        address.postalCode = (String)app.get('Previous_UK_Address_' + i + '__PostalCode__s');
                        address.country    = (String)app.get('Previous_UK_Address_' + i + '_Country__c');
                        address.state      = (String)app.get('Previous_UK_Address' + i + '_State__c');
                        address.id = i;
                        address.title = 'Prev UK Addr ' + i;
                        result.ukAddresses.add(address);
                    }
                }
                if (app.Current_Address_Abroad__City__s != null) {
                    result.abroadAddress = new AddressData();
                    result.abroadAddress.city       = app?.Current_Address_Abroad__City__s;
                    result.abroadAddress.postalCode = app?.Current_Address_Abroad__PostalCode__s;
                    result.abroadAddress.country    = app?.Current_Address_Abroad_Country__c;
                    result.abroadAddress.state      = app?.Current_Address_Abroad_State__c;
                    result.abroadAddress.street     = app?.Current_Address_Abroad__Street__s;
                    result.abroadAddress.title      = 'Abroad Addr';
                }
                result.status = 'Success';
                result.errorMessage = null;
                return result;
            } catch (Exception ex) {
                result.status = 'Error';
                result.ukAddresses = null;
                result.errorMessage = String.valueOf(ex.getLineNumber());
                return result;
            }
    }

    // @AuraEnabled(cacheable=true)
    // public static List<CountryData> getCountries() {
    //     List<Country__c> countries = [
    //         SELECT
    //             Name,
    //             Country_Code__c
    //         FROM Country__c
    //         ORDER BY Name
    //     ];
    //     if (countries.isEmpty()) {
    //         return null;
    //     }
    //     List<CountryData> currentCountries = new List<CountryData>();
    //     for (Country__c item : countries) {
    //         currentCountries.add(
    //             new CountryData(item.Name, item.Country_Code__c)
    //         );
    //     }
    //     return currentCountries;
    // }

    // @AuraEnabled(cacheable=true)
    // public static Map<String, List<StateData>> getCountryStates() {
    //     List<Country_State__c> states = [
    //         SELECT
    //             Name,
    //             State_Code__c,
    //             Country__r.Country_Code__c
    //         FROM Country_State__c
    //         ORDER BY Name
    //     ];
    //     if (states.isEmpty()) {
    //         return null;
    //     }
    //     Map<String, List<StateData>> currentStates = new Map<String, List<StateData>>();
    //     for (Country_State__c item : states) {
    //         if (currentStates.get(item.Country__r.Country_Code__c) == null) {
    //             List<StateData> countryStates = new List<StateData>();
    //             countryStates.add(
    //                 new StateData(item.Name, item.State_Code__c)
    //             );
    //             currentStates.put(item.Country__r.Country_Code__c, countryStates);
    //         }
    //         else {
    //             currentStates.get(item.Country__r.Country_Code__c).add(
    //                 new StateData(item.Name, item.State_Code__c)
    //             );
    //             // countryStates.add(
    //             //     new StateData(item.Name, item.State_Code__c)
    //             // );
    //             // currentStates.put(item.Country__r.Country_Code__c, countryStates);
    //         }
    //     }
    //     return currentStates;
    // }

    // public class CountryData {
    //     @AuraEnabled
    //     public String label{get;set;}
    //     @AuraEnabled
    //     public String value{get;set;}

    //     public CountryData(String label, String value) {
    //         this.label = label;
    //         this.value = value;
    //     }
    // }

    // public class StateData {
    //     @AuraEnabled
    //     public String label{get;set;}
    //     @AuraEnabled
    //     public String value{get;set;}

    //     public StateData(String label, String value) {
    //         this.label = label;
    //         this.value = value;
    //     }
    // }

    public class ResultData {
        @AuraEnabled
        public String status{get;set;}
        @AuraEnabled
        public Employer__c lastUKEmployerId{get;set;}
        @AuraEnabled
        public Id firstAfterUKEmployerId{get;set;}
        @AuraEnabled
        public String abroadStartDate{get;set;}
        @AuraEnabled
        public String lastUKWorkLastDate{get;set;}
        @AuraEnabled
        public String typeOfAfterUKEmployer{get;set;}
    }

    public class Employer {
        @AuraEnabled
        public Integer id{get;set;}
        @AuraEnabled
        public String type{get;set;}
        @AuraEnabled
        public String status{get;set;}
        @AuraEnabled
        public String company{get;set;}
        @AuraEnabled
        public String startDay{get;set;}
    }

    public class ResultAddressesData {
        @AuraEnabled
        public String status{get;set;}
        @AuraEnabled
        public List<AddressData> ukAddresses{get;set;}
        @AuraEnabled
        public AddressData abroadAddress{get;set;}
        @AuraEnabled
        public String errorMessage{get;set;}
    }

    public class AddressData {
        @AuraEnabled
        public String title{get;set;}
        @AuraEnabled
        public String street{get;set;}
        @AuraEnabled
        public String city{get;set;}
        @AuraEnabled
        public String country{get;set;}
        @AuraEnabled
        public String state{get;set;}
        @AuraEnabled
        public String postalCode{get;set;}
        @AuraEnabled
        public Integer id{get;set;}
    }
}