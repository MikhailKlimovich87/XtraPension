/**
 * Service for sending notifications
 */
public class AwsS3NotificationService {
    public final String ADMIN_EMAIL = 'mihail.klimovich@outlook.com';
    
    public void sendFailureNotification(String message) {
        
        AwsS3Logger.error(message);
        
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new String[]{ADMIN_EMAIL});
        email.setSubject('AWS S3 Upload Failed');
        email.setPlainTextBody(message);
        
        Messaging.SendEmailResult[] results =
        Messaging.sendEmail(new Messaging.SingleEmailMessage[]{email});
        
        if (!results[0].isSuccess()) {
            for (Messaging.SendEmailError err : results[0].getErrors()) {
                AwsS3Logger.error(err.getMessage());
            }
        }
    }
    
    public void sendFailRetrieveNotification(String message) {
        
        
        AwsS3Logger.error(message);
        
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new String[]{ADMIN_EMAIL});
        email.setSubject('AWS S3 Retrieve Failed');
        email.setPlainTextBody(message);
        
        Messaging.SendEmailResult[] results =
        Messaging.sendEmail(new Messaging.SingleEmailMessage[]{email});
        
        if (!results[0].isSuccess()) {
            for (Messaging.SendEmailError err : results[0].getErrors()) {
                AwsS3Logger.error(err.getMessage());
            }
        }
    }
    
    public void sendFailureNotification(String subject, String message) {
        AwsS3Logger.error(message);
        
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new String[]{ADMIN_EMAIL});
        email.setSubject(subject);
        email.setPlainTextBody(message);
        
        Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[]{email});
        
        if (!results[0].isSuccess()) {
            for (Messaging.SendEmailError err : results[0].getErrors()) {
                AwsS3Logger.error(err.getMessage());
            }
        }
    }
}