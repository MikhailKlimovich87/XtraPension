public class SFTP_PK_ListFileUploaderScheduler implements Schedulable {
	public void execute(SchedulableContext SC) {
		try {
			SFTP_ListFileHelper.getFiles();
		} catch (Exception e) {
			System.debug(LoggingLevel.ERROR,
				'Scheduler error: ' + e.getMessage() + '\n' + e.getStackTraceString());
		}
	}
}