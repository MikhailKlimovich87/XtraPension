/**
 * PC1_UkTime — small BST/GMT-aware helper for UK wall-clock time.
 *
 * Apex Datetime is stored in UTC. Salesforce Scheduled Apex fires on UTC
 * cron expressions, so any job that must land at a specific UK-local hour
 * needs a runtime check that reconciles DST. This helper exists because
 * PC1_BusinessDayHelper focuses on *forward-shifting* date maths (next
 * business day at 08:00 UK) — it does not expose "what is the current UK
 * wall-clock hour". The DST-aware morning-reminder scheduler needs exactly
 * that: it registers TWO cron entries (06:00 UTC + 07:00 UTC) covering
 * BST and GMT respectively, and each invocation calls hourUk(now) to
 * decide whether it's the correct one to actually run.
 *
 * Kept intentionally small — anything more complex should live in
 * PC1_BusinessDayHelper alongside the retry-cadence maths.
 */
public with sharing class PC1_UkTime {

    /** Current UK wall-clock hour (0..23) for the given moment. */
    public static Integer hourUk(Datetime dt) {
        return Integer.valueOf(dt.format('H', 'Europe/London'));
    }

    /** Current UK wall-clock date for the given moment. */
    public static Date dateUk(Datetime dt) {
        String s = dt.format('yyyy-MM-dd', 'Europe/London');
        List<String> parts = s.split('-');
        return Date.newInstance(
            Integer.valueOf(parts[0]),
            Integer.valueOf(parts[1]),
            Integer.valueOf(parts[2])
        );
    }

    /**
     * Return the pair of UTC Datetimes that bracket the UK-local calendar
     * day of `anchor` — i.e. [00:00 UK, 24:00 UK) expressed as UTC. Used
     * by the morning scheduler to build a SOQL range over today's calls.
     */
    public static Datetime[] ukDayBoundsUtc(Datetime anchor) {
        Date d = dateUk(anchor);
        Datetime startUk = PC1_BusinessDayHelper.buildUkDatetime(d, 0);
        Datetime endUk   = PC1_BusinessDayHelper.buildUkDatetime(d.addDays(1), 0);
        return new Datetime[] { startUk, endUk };
    }
}