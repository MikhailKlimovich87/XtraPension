public class PensionKeeperLetterPdf {
    public String MstrId{get;set;}
    public Application__c appObj{get;set;}
    public String annualAmount{get;set;}
    List<String> euCounties= new List<String>{'AD','AL','AT','BA','BE','BG','BY','CH','CY','CZ','DE','DK','EE','ES','FI','FR','GB','GI','GR','HR','HU','IE','IS','IT','LI','LT','LU','LV','MC','MD','ME','MK','MT','NL','NO','PL','PT','RO','RS','RU','SE','SI','SK','SM','UA','VA'};
    
    public PensionKeeperLetterPdf(ApexPages.StandardController Controller) {
        MstrId = ApexPages.currentPage().getParameters().get('id');
        System.debug('MstrId: ' + MstrId);
        List<Application__c> apps = [
            SELECT 
                Name,
                First_Name__c,
                Second_Name__c,
                Email__c,
                Short_Email__c,
                Current_Address_Abroad__CountryCode__s
            FROM Application__c
            WHERE Id =: MstrId
        ];
        System.debug('Apps: ' + apps);
        if(apps.size() > 0) {
            appObj = apps[0];
            String countryCode = appObj.Current_Address_Abroad__CountryCode__s;
            if(euCounties.contains(countryCode)) {
                annualAmount = '€125';
            } else if(countryCode == 'CA') {
                annualAmount = 'CA $200';
            } else if(countryCode == 'AU') {
                annualAmount = 'AU $200';
            } else if(countryCode == 'NZ') {
                annualAmount = 'NZ $200';
            } else if (countryCode == 'ZA') {
                annualAmount = 'R2000';
            } else {
                annualAmount = '$150';
            }
        }
    }
}