public with sharing class PK_AnnualService30DaysReminderScheduler implements Schedulable {

	public void execute(SchedulableContext SC) {
		Database.executeBatch(new PK_AnnualService30DaysReminder(), 1);
	}
}