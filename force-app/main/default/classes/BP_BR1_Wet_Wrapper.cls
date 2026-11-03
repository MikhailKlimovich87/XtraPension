public with sharing class BP_BR1_Wet_Wrapper {
    public class ApplicationDataWrapper {
        Public String q65;
        Public String headerTitle;

        public ApplicationDataWrapper(Basic__c app) {
            String names = '';
            names = String.isBlank(app.First_Name__c) ? names : names + app.First_Name__c + ' ';
            names = String.isBlank(app.Claimant_Middle_Name__c) ? names : names + app.Claimant_Middle_Name__c + ' ';
            names = String.isBlank(app.Last_Name__c) ? names : names + app.Last_Name__c+ ' ';

            String header = '';
            if(String.isNotBlank(app.Name)) {
                header = app.Name;
            }
            header+= ' - ';
            if(String.isNotBlank(app.First_Name__c)) {
                header += app.First_Name__c +' ';
            }
             if(String.isNotBlank(app.Last_Name__c)) {
                header += app.Last_Name__c;
            }
            this.headerTitle = header;
            this.q65 = names;
        }
    }
}