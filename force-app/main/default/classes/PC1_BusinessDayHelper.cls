/**
 * PC1_BusinessDayHelper — UK business-day date maths for Mary's retry cadence.
 *
 * The Mary retry policy from the Hostinger POC:
 *   miss #1 → +2h
 *   miss #2 → +2h
 *   miss #3 → next business day at 08:00 UK local (BST or GMT)
 *   miss #4+ → next business day
 *
 * Salesforce Apex Datetime is always UTC internally. To land at "08:00 UK time"
 * we compute the next business day's date in Europe/London, then add hours in
 * that timezone (UTC + 0 in winter / +1 in summer). Apex has no first-class
 * timezone conversion so we lean on Datetime.newInstance + formatGmt tricks.
 */
public with sharing class PC1_BusinessDayHelper {

    /**
     * Return `anchor` shifted forward to the next Monday-through-Friday date,
     * at 08:00 UK local time. If `anchor` is already Mon-Fri and it's before
     * 08:00 UK on that day, returns TODAY 08:00 UK (not next day).
     */
    public static Datetime nextBusinessDayAtUkTime(Datetime anchor) {
        return nextBusinessDayAtUkTime(anchor, 8);
    }

    public static Datetime nextBusinessDayAtUkTime(Datetime anchor, Integer hourUk) {
        Date d = dateInUkTimezone(anchor);
        // Roll forward to first Mon-Fri after `anchor` — but if anchor time is
        // before target hour on a Mon-Fri, keep same day.
        Datetime candidate = buildUkDatetime(d, hourUk);
        if (candidate <= anchor) {
            d = d.addDays(1);
            candidate = buildUkDatetime(d, hourUk);
        }
        // Skip Sat/Sun
        Integer safety = 0;
        while (isWeekend(d) && safety < 10) {
            d = d.addDays(1);
            candidate = buildUkDatetime(d, hourUk);
            safety++;
        }
        return candidate;
    }

    /**
     * True if the given UK-local date falls on a Saturday or Sunday.
     */
    public static Boolean isWeekend(Date d) {
        // Apex Date has no day-of-week — go via Datetime.formatGmt('u') would
        // give ISO day (1=Mon..7=Sun) but that's timezone-tricky. Use a fixed
        // reference: 1900-01-01 was a Monday (=1). Days delta mod 7 gives dow.
        Date monday = Date.newInstance(1900, 1, 1); // Monday
        Integer delta = Math.mod(monday.daysBetween(d), 7);
        // 0=Mon, 1=Tue, ..., 5=Sat, 6=Sun
        return delta == 5 || delta == 6;
    }

    /**
     * Convert an Apex Datetime (UTC internally) to the wall-clock Date in
     * Europe/London. Uses format('yyyy-MM-dd') with the running user's TZ —
     * safe on Heroku dyno because we do all logic in Apex, not on JS side.
     * If the running user is UK-based (fernando@xtrapension is), this returns
     * the same date they see in Setup. For non-UK users we use formatGmt +
     * an offset lookup (BST vs GMT).
     */
    public static Date dateInUkTimezone(Datetime dt) {
        String uk = dt.format('yyyy-MM-dd', 'Europe/London');
        List<String> parts = uk.split('-');
        return Date.newInstance(
            Integer.valueOf(parts[0]),
            Integer.valueOf(parts[1]),
            Integer.valueOf(parts[2])
        );
    }

    /**
     * Build a Datetime representing `d` at `hourUk`:00 UK-local, returned as
     * UTC (which is what SF stores). Uses formatGmt round-trip.
     */
    public static Datetime buildUkDatetime(Date d, Integer hourUk) {
        // Format `hourUk` as UK-local string, parse back as UK time.
        String s = String.valueOf(d.year()) + '-'
                 + zeroPad(d.month()) + '-'
                 + zeroPad(d.day()) + ' '
                 + zeroPad(hourUk) + ':00:00';
        // Datetime.parse uses user locale which is unreliable — use valueOfGmt
        // then subtract offset. Easier: build via newInstanceGmt from a UK
        // wall-clock guess, then check whether we got it right via format.
        // For BST vs GMT: UK is UTC+0 in winter, UTC+1 in summer (BST). Use
        // TimeZone SidKey lookup.
        TimeZone tz = TimeZone.getTimeZone('Europe/London');
        // Naive UTC assuming no offset:
        Datetime naive = Datetime.newInstanceGmt(d.year(), d.month(), d.day(), hourUk, 0, 0);
        // Offset in ms — negative during BST because "wall UK 08:00" == UTC 07:00
        Integer offsetMs = tz.getOffset(naive);
        // Subtract offset: wall clock UK 08:00 in UTC ms = UTC 08:00 - offsetMs
        return Datetime.newInstance(naive.getTime() - offsetMs);
    }

    private static String zeroPad(Integer n) {
        return (n < 10 ? '0' : '') + String.valueOf(n);
    }
}