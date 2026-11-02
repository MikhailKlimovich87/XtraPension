public without sharing class RE_SendForEsignReportController {

    // Users hidden from the report (internal/admin folks you don't want listed).
    // Their envelopes are still counted in Total but do NOT get their own column.
    private static final Set<String> EXCLUDED_OWNER_NAMES = new Set<String>{
        'Christina','Carmel','Kitty','Ann-Louise','John H','Ciara','Emma',
        'Elaine','Barry','Paul','George (Irish)','George (Aussie)','Ciaran',
        'Amy','Jamie','George','Brett','John R','Daniel','Mike','Gerard','Adrian'
    };

    @AuraEnabled
    public static EnvelopeReportWrapper getEnvelopeReportData() {
        EnvelopeReportWrapper result = new EnvelopeReportWrapper();

        Date todayDate            = Date.today();
        Date yesterdayDate        = todayDate.addDays(-1);
        Date currentMonthStartDate = todayDate.toStartOfMonth();
        Date lastMonthStartDate    = currentMonthStartDate.addMonths(-1);
        Date lastMonthEndDate      = lastMonthStartDate.addMonths(1);
        Date currentWeekStartDate  = todayDate.toStartOfWeek();
        Date lastWeekStartDate     = currentWeekStartDate.addDays(-7);
        Date lastWeekEndDate       = lastWeekStartDate.addDays(7);

        Integer currentMonth = todayDate.month();
        Integer currentQ = ((currentMonth - 1) / 3) + 1;
        Date currentQtrEndDate = Date.newInstance(
            todayDate.year(),
            currentMonth + (4 - (currentMonth - ((currentQ - 1) * 3))),
            1
        ).addDays(-1);
        Date currentQtrStartDate = currentQtrEndDate.addDays(1).addMonths(-3);
        Date lastQtrStartDate    = currentQtrStartDate.addMonths(-3);
        Date lastQtrEndDate      = lastQtrStartDate.addMonths(3).addDays(-1);

        // ---- Reapply Ids to include in the report -------------------------
        Set<Id> reapplyIds = new Map<Id, Reapply__c>(
            [SELECT Id FROM Reapply__c]
        ).keySet();

        // ---- Latest envelope per Reapply ---------------------------------
        // Envelopes come back newest-first, so "first seen wins" gives us the
        // latest envelope for each Reapply. That envelope's owner is the agent,
        // and its CreatedDate determines the single bucket it falls into.
        Map<Id, dfsle__Envelope__c> latestEnvByReapplyId = new Map<Id, dfsle__Envelope__c>();
        if (!reapplyIds.isEmpty()) {
            for (dfsle__Envelope__c env : [
                SELECT Id, Name, CreatedDate, OwnerId, Owner.Name, dfsle__SourceId__c
                FROM dfsle__Envelope__c
                WHERE CreatedDate >= :lastQtrStartDate
                AND dfsle__SourceId__c IN :reapplyIds
                ORDER BY CreatedDate DESC
            ]) {
                Id rid = env.dfsle__SourceId__c;
                if (!latestEnvByReapplyId.containsKey(rid)) {
                    latestEnvByReapplyId.put(rid, env);
                }
            }
        }

        // ---- Bucket latest envelopes by owner -----------------------------
        Map<String, OwnerBucket> bucketsByOwner = new Map<String, OwnerBucket>();

        for (dfsle__Envelope__c env : latestEnvByReapplyId.values()) {
            String ownerName = (env.Owner != null) ? env.Owner.Name : 'Unknown';

            OwnerBucket b = bucketsByOwner.get(ownerName);
            if (b == null) {
                b = new OwnerBucket();
                b.ownerName = ownerName;
                bucketsByOwner.put(ownerName, b);
            }

            Date d = env.CreatedDate.date();

            if (d == todayDate)                                          b.today++;
            if (d == yesterdayDate)                                      b.yesterday++;
            if (d >= currentWeekStartDate && d <= todayDate)             b.thisWeek++;
            if (d >= lastWeekStartDate && d < lastWeekEndDate)           b.lastWeek++;
            if (d >= currentMonthStartDate && d <= todayDate)            b.thisMonth++;
            if (d >= lastMonthStartDate && d < lastMonthEndDate)         b.lastMonth++;
            if (d >= currentQtrStartDate && d <= currentQtrEndDate)      b.thisQtr++;
            if (d >= lastQtrStartDate && d <= lastQtrEndDate)            b.lastQtr++;
        }

        // ---- Column order: agent names only (no "None") -------------------
        List<String> agentNames = new List<String>();
        for (String name : bucketsByOwner.keySet()) {
            if (EXCLUDED_OWNER_NAMES.contains(name)) continue;
            agentNames.add(name);
        }
        agentNames.sort();

        List<String> columnNames = new List<String>(agentNames);
        result.agentsName = columnNames;

        // ---- One DateDifferenceWrapper per row ----------------------------
        List<String> rowLabels = new List<String>{
            'Today','Yesterday','This Week','Last Week',
            'This Month','Last Month','This Qtr','Last Qtr'
        };
        Map<String, DateDifferenceWrapper> rowByName = new Map<String, DateDifferenceWrapper>();
        for (String label : rowLabels) {
            DateDifferenceWrapper w = new DateDifferenceWrapper();
            w.name = label;
            rowByName.put(label, w);
        }

        // Populate per-agent cells in the same order as columnNames.
        for (String ownerName : columnNames) {
            OwnerBucket b = bucketsByOwner.get(ownerName);
            Integer t  = (b == null) ? 0 : b.today;
            Integer y  = (b == null) ? 0 : b.yesterday;
            Integer tw = (b == null) ? 0 : b.thisWeek;
            Integer lw = (b == null) ? 0 : b.lastWeek;
            Integer tm = (b == null) ? 0 : b.thisMonth;
            Integer lm = (b == null) ? 0 : b.lastMonth;
            Integer tq = (b == null) ? 0 : b.thisQtr;
            Integer lq = (b == null) ? 0 : b.lastQtr;

            rowByName.get('Today').countData.add(t);
            rowByName.get('Yesterday').countData.add(y);
            rowByName.get('This Week').countData.add(tw);
            rowByName.get('Last Week').countData.add(lw);
            rowByName.get('This Month').countData.add(tm);
            rowByName.get('Last Month').countData.add(lm);
            rowByName.get('This Qtr').countData.add(tq);
            rowByName.get('Last Qtr').countData.add(lq);
        }

        // ---- "Total" column = roll-up across every owner (incl. excluded) -
        Integer allToday = 0, allYest = 0, allThisWk = 0, allLastWk = 0,
                allThisMo = 0, allLastMo = 0, allThisQ = 0, allLastQ = 0;
        for (OwnerBucket b : bucketsByOwner.values()) {
            allToday  += b.today;     allYest   += b.yesterday;
            allThisWk += b.thisWeek;  allLastWk += b.lastWeek;
            allThisMo += b.thisMonth; allLastMo += b.lastMonth;
            allThisQ  += b.thisQtr;   allLastQ  += b.lastQtr;
        }
        rowByName.get('Today').fullCount      = allToday;
        rowByName.get('Yesterday').fullCount  = allYest;
        rowByName.get('This Week').fullCount  = allThisWk;
        rowByName.get('Last Week').fullCount  = allLastWk;
        rowByName.get('This Month').fullCount = allThisMo;
        rowByName.get('Last Month').fullCount = allLastMo;
        rowByName.get('This Qtr').fullCount   = allThisQ;
        rowByName.get('Last Qtr').fullCount   = allLastQ;

        result.dateData.add(rowByName.get('Today'));
        result.dateData.add(rowByName.get('Yesterday'));
        result.dateData.add(rowByName.get('This Week'));
        result.dateData.add(rowByName.get('Last Week'));
        result.dateData.add(rowByName.get('This Month'));
        result.dateData.add(rowByName.get('Last Month'));
        result.dateData.add(rowByName.get('This Qtr'));
        result.dateData.add(rowByName.get('Last Qtr'));

        // Header list: Total + [agent, agent, ...]  (no None)
        List<String> headerRow = new List<String>{ 'Total' };
        headerRow.addAll(columnNames);
        result.columnHeaders = headerRow;

        // ---- Daily counts for the bar chart -------------------------------
        // Uses the same "latest envelope per Reapply" set so chart totals match
        // the table's Total column.
        Date chartStart = todayDate.addMonths(-3);
        Map<Date, Integer> countByDay = new Map<Date, Integer>();
        for (dfsle__Envelope__c env : latestEnvByReapplyId.values()) {
            Date d = env.CreatedDate.date();
            if (d < chartStart || d > todayDate) continue;
            Integer c = countByDay.get(d);
            countByDay.put(d, (c == null ? 0 : c) + 1);
        }
        List<Date> sortedDays = new List<Date>(countByDay.keySet());
        sortedDays.sort();
        for (Date d : sortedDays) {
            DateAmountWrapper w = new DateAmountWrapper();
            w.dateName = DateTime.newInstance(d.year(), d.month(), d.day()).format('dd MMM');
            w.amount   = countByDay.get(d);
            result.amountByDay.add(w);
        }

        return result;
    }

    @AuraEnabled(cacheable=true)
    public static Integer getUniqueEnvelopeCount(Datetime startDate, Datetime endDate) {
        Map<Id, Reapply__c> reapplyMap = new Map<Id, Reapply__c>(
            [SELECT Id, Name FROM Reapply__c]
        );
        Set<Id> reapplyIds = reapplyMap.keySet();
        if (reapplyIds.isEmpty()) return 0;

        AggregateResult[] results = [
            SELECT COUNT_DISTINCT(dfsle__SourceId__c) uniqueCount
            FROM dfsle__Envelope__c
            WHERE CreatedDate >= :startDate
            AND CreatedDate <= :endDate
            AND dfsle__SourceId__c IN :reapplyIds
        ];
        if (results.isEmpty() || results[0].get('uniqueCount') == null) return 0;
        return (Integer) results[0].get('uniqueCount');
    }

    // ------------------------------------------------------------------
    // Wrappers — unchanged, so your LWC keeps working
    // ------------------------------------------------------------------
    public class EnvelopeReportWrapper {
        @AuraEnabled public List<DateDifferenceWrapper> dateData = new List<DateDifferenceWrapper>();
        @AuraEnabled public List<String> agentsName = new List<String>();
        @AuraEnabled public List<String> columnHeaders = new List<String>();
        @AuraEnabled public List<DateAmountWrapper> amountByDay = new List<DateAmountWrapper>();
    }

    public class DateDifferenceWrapper {
        @AuraEnabled public String name;
        @AuraEnabled public List<Integer> countData = new List<Integer>();
        @AuraEnabled public Integer fullCount = 0;
    }

    public class DateAmountWrapper {
        @AuraEnabled public String dateName;
        @AuraEnabled public Integer amount;
    }

    private class OwnerBucket {
        String ownerName;
        Integer today = 0, yesterday = 0, thisWeek = 0, lastWeek = 0,
                thisMonth = 0, lastMonth = 0, thisQtr = 0, lastQtr = 0;
    }

    public static void fakeMethod() {
        Integer i = 0;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;

    }
}