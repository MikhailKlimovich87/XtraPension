public class StatusServerSchedulerHelper {
    public static final Server_Status__c SERVER_STATUS = Server_Status__c.getInstance();
    public static final String ORG_WIDE_EMAIL_ADDRESS = 'clients@xtrapension.com';

    @future(callout=true)
    public static void checkServerStatus() {
        HttpResponse response = requestToServer();
        Integer statusCode = response.getStatusCode();
        Map<String, Object> responseBody = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());
        String status = (String)responseBody.get('status');
        if (statusCode == 200 && status == 'Success') {
            return;
        } else {
            User adminUser = [
                SELECT Email
                FROM User
                WHERE Username = :SERVER_STATUS.Admin_Username__c
                LIMIT 1
            ];
            if (adminUser == null) {
                return;
            }
            OrgWideEmailAddress[] owea = [
                SELECT Id
                FROM OrgWideEmailAddress
                WHERE Address = :ORG_WIDE_EMAIL_ADDRESS
            ];
            Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
            message.setUseSignature(false);
            message.setBccSender(false);
            message.setSaveAsActivity(false);
            message.setSubject('XtraPension server doesn\'t work!');
            message.setPlainTextBody('Please, check your XtraPension Server on Heroku. You have some error!');
            message.toAddresses = new String[] { 'mihail.klimovich@outlook.com', 'sergey.martsinovsky@succraft.com'};
            if ( owea.size() > 0 ) {
                message.setOrgWideEmailAddressId(owea.get(0).Id);
            }
            Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
            Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
        }
    }

    public static HttpResponse requestToServer() {

        HttpRequest request = new HttpRequest();
        request.setEndpoint(SERVER_STATUS.HTTP_Endpoint__c);
        request.setHeader('Content-Type', 'application/json');
        request.setMethod('GET');
        request.setTimeout(110000);
        Http http = new Http();

        return http.send(request);
    }
}