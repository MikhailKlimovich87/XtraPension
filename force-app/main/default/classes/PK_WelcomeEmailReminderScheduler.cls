public class PK_WelcomeEmailReminderScheduler implements Schedulable {

    public void execute(SchedulableContext tc) {
        Database.executeBatch(new PK_WelcomeEmailReminderBatch(), 1); 
    }

}