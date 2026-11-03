public class SFTPProcessQueueable implements Queueable, Database.AllowsCallouts {
    public void execute(QueueableContext context) {
        SFTP_ListFileHelper.getFiles();
    }
}