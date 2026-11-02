public with sharing class PK_PortalAuthHelper {

    public static Map<String, Object> login(PK_RequestWrappers.LoginDataWrapper wrapper) {
        Map<String, Object> results = new Map<String, Object>();
        try {
            if (wrapper.applicationNumber == null || wrapper.password == null) {
                results.put('status', 'error');
                results.put('message', 'Applcation Name or Password is empty');
                return results;
            }
            List<Application__c> activePortalApps = PK_PortalUtils.getActiveAppPortalUser(wrapper);
            if (activePortalApps.size() == 0) {
                results.put('status', 'error');
                results.put('message', 'Active Application not found');
                return results;
            }
            Application__c currApp = activePortalApps[0];
            if (currApp.PK_Portal_User_PW__c == wrapper.password) {
                insert new PK_Portal_User_Login_History__c (
                    IP_Address__c  = wrapper.ip,
                    Device__c      = wrapper.device,
                    Country_ISO__c = wrapper.countryISO,
                    Browser__c     = wrapper.browser,
                    Login_Time__c  = Datetime.now(),
                    Application__c = currApp.Id
                );
                results.put('status', 'success');
                results.put(
                    'application',
                    new PK_ResponseWrappers.ApplicationDataWrapper(currApp)
                );
            } else {
                results.put('status', 'error');
                results.put('message', 'Wrong password');
            }
            return results;
        } catch (Exception ex) {
            results.put('status', 'error');
            results.put('message', ex.getLineNumber() + ' - ' + ex.getMessage());
            return results;
        }
    }

    public static Map<String, Object> forgotPassword(PK_RequestWrappers.ApplicationDataWrapper wrapper) {
        Map<String, Object> results = new Map<String, Object>();
        try{
            if (wrapper.applicationNumber == null) {
                results.put('status', 'error');
                results.put('message', 'Application Number is null');
                return results;
            }
            List<Application__c> activePortalApps = PK_PortalUtils.getActiveAppPortalUser(wrapper);
            if (activePortalApps.size() == 0) {
                results.put('status', 'error');
                results.put('message', 'Active Application not found');
                return results;
            }
            List<Application__c> apps = [
                SELECT
                    PK_Portal_User_PW__c,
                    Contact__c,
                    Email__c,
                    Name
                FROM Application__c
                WHERE Name = :wrapper.applicationNumber
                LIMIT 1
            ];
            if (apps.size() == 0) {
                results.put('status', 'error');
                results.put('message', 'Application not found');
            } else {
                Application__c currApp = apps[0];
                PK_PortalUtils.sendRegistrationEmail(currApp);
                // Messaging.SingleEmailMessage message = generateForgotPasswordMessage(currApp);
                // Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
                // Messaging.SendEmailResult[] sendEmailresults = Messaging.sendEmail(messages);
                results.put('status', 'success');
            }
            return results;
        } catch (Exception ex) {
            results.put('status', 'error');
            results.put('message', ex.getLineNumber() + ' - ' + ex.getMessage());
            return results;
        }
    }

    public static String generatePassword(Application__c app) {
        String pw = app.National_Insurance_Number__c + app.Second_Name__c;
        return pw.replaceAll('\'', '').toUpperCase().deleteWhitespace();
    }

}