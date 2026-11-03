public class CountryCodeHelper {
    public static String getCountryNameByIsoCode(String isoCode){
        List<Country__c> countries = [
            SELECT
                Name,
                Country_Code__c
            FROM Country__c
            WHERE Country_Code__c = :isoCode];
        if(isoCode == 'Canada') {
            return 'CA';
        } else if(isoCode == 'Zimbabwe') {
            return 'ZW';
        } else if (isoCode == 'GBR') {
            return 'United Kingdom';
        }
        if (countries.isEmpty()) return null;
        return countries[0].Name;
    }

    public static String getCountryIsoCodeByCountryName(String countryName) {
        List<Country__c> countries = [
            SELECT
                Name,
                Country_Code__c
            FROM Country__c
            WHERE Name = :countryName];
            if (countries.isEmpty()) return countryName;
            return countries[0].Country_Code__c;
    }

     public static String getCountryStateISOByName(String stateName){
        List<Country_State__c> states = [
            SELECT
                Name,
                Country__r.Country_Code__c,
                State_Code__c
            FROM Country_State__c
            WHERE
                Name = : stateName
            ];
        if (states.isEmpty()) return null;
        return states[0].State_Code__c;
    }

    public static String getCountryStateNameByIsoCode(String countryIsoCode, String stateIsoCode){
        List<Country_State__c> states = [
            SELECT
                Name,
                Country__r.Country_Code__c,
                State_Code__c
            FROM Country_State__c
            WHERE
                Country__r.Country_Code__c = :countryIsoCode AND
                State_Code__c = :stateIsoCode
            ];
        if (states.isEmpty()) return null;
        return states[0].Name;
    }

    public static Map<String, String> getCountryCodeByCountryName(){
        List<Country__c> countries = [
            SELECT
                Name,
                Country_Code__c
            FROM Country__c
        ];
        if (countries.isEmpty()) return null;
        Map<String, String> countryCodeByName = new Map<String, String>();
        for (Country__c country : countries) {
            countryCodeByName.put(country.Country_Code__c, country.Name);
        }
        return countryCodeByName;
    }

    public static String getStateCodeByStateName(String countryIsoCode, String stateName){
        List<Country_State__c> states = [
            SELECT
                Name,
                Country__r.Country_Code__c,
                State_Code__c
            FROM Country_State__c
            WHERE
                Country__r.Country_Code__c = :countryIsoCode AND
                Name = :stateName
        ];
        if (!states.isEmpty())  return states[0].State_Code__c;
        else return null;
    }
}