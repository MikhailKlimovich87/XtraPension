public class GoogleReviewSMSScheduler implements Schedulable {

    public void execute(SchedulableContext SC) {
        GoogleReviewSMSHandler.sendGoogleReviewSMS();
    }
}