// Agent's Sales site (xpxp.my.site.com/AgentSales): sales per agent and period in three tables,
// Total (Vol Contributions + Claims), Vol Contributions (Application__c) and Claims (Basic__c).
public without sharing class XpAgentSalesController {
    // Agents who left: no column, but their sales still count in the Total column (same list as AgentSalesReportController)
    private static final Set<String> HIDDEN_AGENTS = new Set<String>{
        'Christina', 'Carmel', 'Kitty', 'Ann-Louise', 'John H', 'Ciara', 'Emma', 'Elaine', 'Barry', 'Paul',
        'George (Irish)', 'George (Aussie)', 'Ciaran', 'Amy', 'Jamie', 'George', 'Brett', 'John R', 'Daniel',
        'Mike', 'Gerard', 'Adrian'
    };
    // Test claim (it has a real test charge)
    private static final Set<String> TEST_CLAIMS = new Set<String>{ 'C00000' };
    private static final List<String> PERIODS = new List<String>{
        'Today', 'Yesterday', 'This Week', 'Last Week', 'This Month', 'Last Month', 'This Qtr', 'Last Qtr'
    };

    @AuraEnabled(cacheable=true)
    public static SalesReport getSales() {
        return build(Date.today());
    }

    @TestVisible
    private static SalesReport build(Date today) {
        List<List<Date>> windows = periodWindows(today);
        Date since = windows[windows.size() - 1][0]; // first day of last quarter, the oldest period

        List<String> vcAgents = activeAgents(Application__c.Agent_Making_Sale__c);
        List<String> claimAgents = activeAgents(Basic__c.Agent_Making_Sale__c);

        // Same rules as the old Agent's Sales table: appeals and Megan's South Africa sales count twice,
        // Deposit Refund is out and A10286 counts on 08/07/2026
        Tally vc = new Tally(new Set<String>(vcAgents), windows);
        for (Application__c app : [
            SELECT Name, Agent_Making_Sale__c, Appeal_Application__c, CreatedDate, Current_Abroad_Country__c
            FROM Application__c
            WHERE (Agent_Making_Sale__c != null AND CreatedDate >= :since AND Status__c != 'Deposit Refund')
               OR Name = 'A10286'
        ]) {
            Integer weight = app.Appeal_Application__c == true ||
                (app.Agent_Making_Sale__c == 'Megan' && app.Current_Abroad_Country__c == 'South Africa') ? 2 : 1;
            Date sold = app.Name == 'A10286' ? Date.newInstance(2026, 7, 8) : app.CreatedDate.date();
            vc.add(app.Agent_Making_Sale__c, sold, weight);
        }

        // A claim is created when the deposit is paid
        Tally claims = new Tally(new Set<String>(claimAgents), windows);
        for (Basic__c claim : [
            SELECT Agent_Making_Sale__c, CreatedDate
            FROM Basic__c
            WHERE Agent_Making_Sale__c != null AND CreatedDate >= :since
              AND Status__c != 'Deposit Refund' AND Name NOT IN :TEST_CLAIMS
        ]) {
            claims.add(claim.Agent_Making_Sale__c, claim.CreatedDate.date(), 1);
        }

        // One set of columns for the three tables: Vol Contributions agents first, then agents who only sell Claims
        List<String> columns = new List<String>();
        Set<String> seen = new Set<String>();
        for (List<String> source : new List<List<String>>{ vcAgents, claimAgents }) {
            for (String agent : source) {
                if (!HIDDEN_AGENTS.contains(agent) && seen.add(agent)) {
                    columns.add(agent);
                }
            }
        }

        SalesReport report = new SalesReport();
        report.agents = columns;
        report.tables = new List<SalesTable>{
            vc.plus(claims).toTable('total', 'Total Sales', columns),
            vc.toTable('vc', 'Vol Contributions Sales', columns),
            claims.toTable('claims', 'Claims Sales', columns)
        };
        return report;
    }

    // [first day, last day] of each period, in PERIODS order (XpTeamTablesController uses it too)
    public static List<List<Date>> periodWindows(Date today) {
        Date weekStart = today.toStartOfWeek();
        Date monthStart = today.toStartOfMonth();
        Date qtrStart = Date.newInstance(today.year(), ((today.month() - 1) / 3) * 3 + 1, 1);
        return new List<List<Date>>{
            new List<Date>{ today, today },
            new List<Date>{ today.addDays(-1), today.addDays(-1) },
            new List<Date>{ weekStart, today },
            new List<Date>{ weekStart.addDays(-7), weekStart.addDays(-1) },
            new List<Date>{ monthStart, today },
            new List<Date>{ monthStart.addMonths(-1), monthStart.addDays(-1) },
            new List<Date>{ qtrStart, qtrStart.addMonths(3).addDays(-1) },
            new List<Date>{ qtrStart.addMonths(-3), qtrStart.addDays(-1) }
        };
    }

    private static List<String> activeAgents(Schema.SObjectField field) {
        List<String> names = new List<String>();
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                names.add(entry.getValue());
            }
        }
        return names;
    }

    // Weighted sales per agent and period
    private class Tally {
        private final Set<String> agents;
        private final List<List<Date>> windows;
        private final Map<String, List<Integer>> byAgent = new Map<String, List<Integer>>();

        public Tally(Set<String> agents, List<List<Date>> windows) {
            this.agents = agents;
            this.windows = windows;
        }

        // Like the old table, a value that is no longer on the picklist is not counted
        public void add(String agent, Date sold, Integer weight) {
            if (!agents.contains(agent)) {
                return;
            }
            List<Integer> counts = countsFor(agent);
            for (Integer i = 0; i < windows.size(); i++) {
                if (sold >= windows[i][0] && sold <= windows[i][1]) {
                    counts[i] += weight;
                }
            }
        }

        public Tally plus(Tally other) {
            Set<String> allAgents = new Set<String>(agents);
            allAgents.addAll(other.agents);
            Tally sum = new Tally(allAgents, windows);
            for (Tally part : new List<Tally>{ this, other }) {
                for (String agent : part.byAgent.keySet()) {
                    List<Integer> source = part.byAgent.get(agent);
                    List<Integer> target = sum.countsFor(agent);
                    for (Integer i = 0; i < source.size(); i++) {
                        target[i] += source[i];
                    }
                }
            }
            return sum;
        }

        public SalesTable toTable(String key, String title, List<String> columns) {
            SalesTable table = new SalesTable();
            table.key = key;
            table.title = title;
            table.rows = new List<SalesRow>();
            for (Integer i = 0; i < XpAgentSalesController.PERIODS.size(); i++) {
                SalesRow row = new SalesRow();
                row.name = XpAgentSalesController.PERIODS[i];
                row.total = 0;
                // Total includes the hidden agents, like the old Total column
                for (List<Integer> counts : byAgent.values()) {
                    row.total += counts[i];
                }
                row.counts = new List<Integer>();
                for (String agent : columns) {
                    row.counts.add(byAgent.containsKey(agent) ? byAgent.get(agent)[i] : 0);
                }
                table.rows.add(row);
            }
            return table;
        }

        private List<Integer> countsFor(String agent) {
            if (!byAgent.containsKey(agent)) {
                List<Integer> zeros = new List<Integer>();
                for (Integer i = 0; i < windows.size(); i++) {
                    zeros.add(0);
                }
                byAgent.put(agent, zeros);
            }
            return byAgent.get(agent);
        }
    }

    public class SalesReport {
        @AuraEnabled public List<String> agents;
        @AuraEnabled public List<SalesTable> tables;
    }

    public class SalesTable {
        @AuraEnabled public String key;
        @AuraEnabled public String title;
        @AuraEnabled public List<SalesRow> rows;
    }

    public class SalesRow {
        @AuraEnabled public String name;
        @AuraEnabled public Integer total;
        @AuraEnabled public List<Integer> counts;
    }
}