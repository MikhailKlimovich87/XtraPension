public class RE_DocusignScheduler implements Schedulable {

    public void execute(SchedulableContext tc) {
        RE_DocusignSchedulerHelper helper = new RE_DocusignSchedulerHelper();
        helper.sendFilesToDocusign();
    }
}