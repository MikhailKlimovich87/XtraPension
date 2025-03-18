public class ApplicationFormErrorTriggerHandler {
    public final String OWD_NAME = 'clients@xtrapension.com';
    public final List<String> ADMIN_ADDRESSES = new String[] {
        'mihail.klimovich@outlook.com',
        'mishaklimovich87@gmail.com'
    };
    public List<Application_Form_Error__c> newErrors;

    public ApplicationFormErrorTriggerHandler(List<Application_Form_Error__c> newRecords) {
        this.newErrors = newRecords;
    }

    public void sendErrorMessage() {
        OrgWideEmailAddress[] owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :OWD_NAME
        ];
        for (Application_Form_Error__c formError : newErrors) {
            Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
            message.setUseSignature(false);
            message.setBccSender(false);
            message.setSaveAsActivity(true);
            message.setTreatTargetObjectAsRecipient(false);
            message.setWhatId(formError.Id);
            message.setPlainTextBody(formError.Error_Body__c);
            if ( owea.size() > 0 ) {
                message.setOrgWideEmailAddressId(owea.get(0).Id);
            }
            message.toAddresses = ADMIN_ADDRESSES;
            Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
            Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
        }
    }
}