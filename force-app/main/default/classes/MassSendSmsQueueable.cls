public class MassSendSmsQueueable implements Queueable, Database.AllowsCallouts {

    public String message;
    public String phoneNumber;
    public String countryData;

    public MassSendSmsQueueable(String messageBody, String phoneData, String countryCode) {
        this.message     = messageBody;
        this.phoneNumber = phoneData;
        this.countryData = countryCode;
    }

    public void execute(QueueableContext context) {
        try {
            HttpResponse res = TwilioSmsSender.send(message, phoneNumber, countryData);
            if (res != null) {
                System.debug(res.getBody());
            } else {
                System.debug('MassSendSmsQueueable: no callout made (blank phone).');
            }
        } catch (Exception ex) {
            System.debug('Error: ' + ex.getMessage());
        }
    }
}