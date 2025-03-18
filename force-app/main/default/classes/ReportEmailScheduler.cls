public class ReportEmailScheduler implements Schedulable {
    public void execute(SchedulableContext SC) {
        Date todayDate = Date.today();
        Date startWeekDate = todayDate.addDays(-6);
        ReportEmailHandler.sendReport(
            'Applications_With_Posted_Status_7ea',
	        new String[]{
                'john@tinderpoint.com',
                'monica@tinderpoint.com'
            },
            'Applications With Posted Status (' + startWeekDate.day() + '/' + startWeekDate.month() + '/' + startWeekDate.year() + ' - ' + todayDate.day() + '/' + todayDate.month() + '/' + todayDate.year() + ')'
        );
        ReportEmailHandler.sendReport(
            'NOT_SIGNED_AFTER_7_DAYS_09a',
	        new String[]{
                'jr@xtrapension.com'
            },
            'Unsigned Apps Waiting 7+ Days'
        );
    }
}