public with sharing class PK_PortalSignUpHelper {

    public static Map<String, Object> findApplication(PK_RequestWrappers.ApplicationDataWrapper wrapper) {
        Map<String, Object> results = new Map<String, Object>();
        try {
            if (wrapper.applicationNumber == null || wrapper.email == null ) {
                results.put('status', 'error');
                results.put('message', 'Application Number or Email is null');
                return results;
            }
            List<Application__c> apps = [
                SELECT
                    Id,
                    Name,
                    PK_Portal_User_PW__c,
                    First_Name__c,
                    Second_Name__c,
                    Email__c,
                    Full_Maiden_Previous_Name__c,
                    Date_Of_Birth__c,
                    National_Insurance_Number__c,
                    Private_UK_Pension__c,
                    Current_Occupation__c,
                    Current_Address_Abroad__City__s,
                    Related_Contact_Phone__c,
                    Current_Address_Abroad__CountryCode__s,
                    toLabel(Current_Address_Abroad__CountryCode__s) CountryCode,
                    Current_Address_Abroad__PostalCode__s,
                    toLabel(Current_Address_Abroad__StateCode__s),
                    Current_Address_Abroad__Street__s,
                    Stripe_Customer_Id__c,
                    Payment_Method__c,
                    PK_Portal_User_Active__c,
                    CurrencyIsoCode,
                    Current_Customer_Id__c,
                    PK_HideAppData__c
                FROM Application__c
                WHERE Name = :wrapper.applicationNumber.trim() AND
                      Email__c = :wrapper.email.trim()
                LIMIT 1
            ];
            if (apps.size() == 0) {
                results.put('status', 'error');
                results.put('message', 'We couldn\'t find a match. \nPlease double-check the application number and email, then try again.');
                return results;
            }
            Application__c currApp =  apps[0];
            if(currApp.PK_Portal_User_Active__c) {
                results.put('status', 'error');
                results.put('message', 'XtraPension client with this application number has already signed up. \nPlease log in to your account or contact support if you need assistance.');
            } else {
                results.put('status', 'success');
                results.put(
                    'foundApplication',
                    new PK_ResponseWrappers.CurrentApplicationDataWrapper(currApp)
                );
            }
            return results;
        } catch (Exception ex) {
            results.put('status', 'error');
            results.put('message', ex.getLineNumber() + ' - ' + ex.getMessage());
            return results;
        }
    }
}