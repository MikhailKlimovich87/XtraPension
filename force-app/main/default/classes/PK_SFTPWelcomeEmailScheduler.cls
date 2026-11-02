public class PK_SFTPWelcomeEmailScheduler implements Schedulable {
    public void execute(SchedulableContext tc) {
        Database.executeBatch(new PKNoitificationGenerator(), 1); 
    }
}