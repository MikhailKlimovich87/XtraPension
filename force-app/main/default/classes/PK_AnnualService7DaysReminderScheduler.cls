public with sharing class PK_AnnualService7DaysReminderScheduler implements Schedulable {

	public void execute(SchedulableContext SC) {
		Database.executeBatch(new PK_AnnualService7DaysReminder(), 1);
	}
}