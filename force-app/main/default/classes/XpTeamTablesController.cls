// Staff sites on xpxp.my.site.com, per person and period: a Total table, the site's old table and a second product.
//   agentCheck     /MoveToAgentCheck         Vol Contributions + Claims moved to Agent Check
//   qcApproved     /MoveToQcApproved         Vol Contributions + Claims moved to QC Approved
//   sendToPH       /SendToPH                 Vol Contributions sent to Printing House + Claims signed on DocuSign,
//                                            for whoever sent the claim for signature (the signing itself is automatic)
//   pensionKeeper  /PensionKeeperAgentSales  Pension Keeper sales + paid Reapplies
// The Vol Contributions and Pension Keeper halves keep the rules of the old controllers (MoveToAgentCheckReport,
// MovedToQCApprovedReportController, SendToPHReportController, PK_AgentSalesReportController).
public without sharing class XpTeamTablesController {
    private static final List<String> MOVE_PERIODS = new List<String>{
        'Today', 'Yesterday', 'This Week', 'Last Week', 'This Month', 'Last Month'
    };
    private static final List<String> SALE_PERIODS = new List<String>{
        'Today', 'Yesterday', 'This Week', 'Last Week', 'This Month', 'Last Month', 'This Qtr', 'Last Qtr'
    };

    // Old MoveToAgentCheckReport: these people are neither columns nor counted
    private static final Set<String> AGENT_CHECK_EXCLUDED = new Set<String>{
        'XtraPension Admin', 'Jessica Viljoen', 'Fiona Carey', 'Rob Landy', 'Grace Coash', 'Camille Gittbao',
        'Edryl Ranido', 'Daniel Gatdula', 'Maria Marmeto', 'Niamh', 'Monica Lorica', 'MaryClaire Mchatton',
        'Stripe Webhooks Site Guest User', 'Richard Talbot'
    };
    private static final Set<String> AGENT_CHECK_PROFILES = new Set<String>{
        'Agent', 'System Administrator', 'Senior Agent', 'Telesales Rep'
    };
    // Old QC Approved and Printing House reports: only these people
    private static final Set<String> QC_USERS = new Set<String>{
        'Edryl Ranido', 'Camille Gittbao', 'Maria Marmeto', 'Daniel Gatdula', 'John Ring'
    };
    private static final Set<String> PH_USERS = new Set<String>{ 'Fiona Carey', 'Rob Landy', 'John Ring' };
    // Old SendToPHReportController: only applications that are now past the printing house
    private static final Set<String> PH_DONE_STATUSES = new Set<String>{
        'DWP Teleclaim', 'Posted', 'DWP 2 Emails Sent', 'DWP Shortfall Pending'
    };
    // Agents who left: no column, but their sales still count in the Total column (same list as the old sales reports)
    private static final Set<String> HIDDEN_AGENTS = new Set<String>{
        'Christina', 'Carmel', 'Kitty', 'Ann-Louise', 'John H', 'Ciara', 'Emma', 'Elaine', 'Barry', 'Paul',
        'George (Irish)', 'George (Aussie)', 'Ciaran', 'Amy', 'Jamie', 'George', 'Brett', 'John R', 'Daniel',
        'Mike', 'Gerard', 'Adrian'
    };
    // Test claim C00000 and test reapply R05511
    private static final Set<String> TEST_RECORDS = new Set<String>{ 'C00000', 'R05511' };
    private static final String SIGNED = 'Signed - Waiting Docs at WDM';
    private static final String SENT_FOR_SIGNATURE = 'Sent for eSignature';

    @AuraEnabled(cacheable=true)
    public static XpAgentSalesController.SalesReport getTables(String report) {
        Date today = Date.today();
        if (report == 'agentCheck') {
            return agentCheck(today);
        }
        if (report == 'qcApproved') {
            return qcApproved(today);
        }
        if (report == 'sendToPH') {
            return sendToPH(today);
        }
        if (report == 'pensionKeeper') {
            return pensionKeeper(today);
        }
        throw new AuraHandledException('Unknown report: ' + report);
    }

    private static XpAgentSalesController.SalesReport agentCheck(Date today) {
        List<String> people = userNames([
            SELECT Name FROM User
            WHERE IsActive = true AND Profile.Name IN :AGENT_CHECK_PROFILES AND Name NOT IN :AGENT_CHECK_EXCLUDED
        ]);
        List<Move> vc = new List<Move>();
        for (Application__History h : [
            SELECT Parent.Name, NewValue, CreatedDate, CreatedById, CreatedBy.Name
            FROM Application__History
            WHERE CreatedDate = LAST_N_DAYS:180 AND Field = 'Status__c' AND CreatedBy.Name NOT IN :AGENT_CHECK_EXCLUDED
            ORDER BY CreatedDate DESC
        ]) {
            if (h.NewValue == 'Agent Check') {
                vc.add(new Move(h.Parent.Name, 'Agent Check', h.CreatedBy.Name, null, h.CreatedDate));
            }
        }
        return moveReport(today, people, firstPerRecord(vc), firstPerRecord(claimMovesTo('Agent Check')),
            'Total Moved to Agent Check', 'Vol Contributions Moved to Agent Check', 'Claims Moved to Agent Check');
    }

    private static XpAgentSalesController.SalesReport qcApproved(Date today) {
        List<String> people = userNames([SELECT Name FROM User WHERE IsActive = true AND Name IN :QC_USERS]);
        List<Move> vc = new List<Move>();
        for (Application__History h : [
            SELECT Parent.Name, NewValue, CreatedDate, CreatedById, CreatedBy.Name
            FROM Application__History
            WHERE CreatedDate = LAST_N_DAYS:180 AND Field = 'Status__c' AND CreatedBy.Name IN :QC_USERS
            ORDER BY CreatedDate DESC
        ]) {
            if (h.NewValue == 'QC Approved') {
                vc.add(new Move(h.Parent.Name, 'QC Approved', h.CreatedBy.Name, null, h.CreatedDate));
            }
        }
        return moveReport(today, people, firstPerRecord(vc), firstPerRecord(claimMovesTo('QC Approved')),
            'Total Moved to QC Approved', 'Vol Contributions Moved to QC Approved', 'Claims Moved to QC Approved');
    }

    private static XpAgentSalesController.SalesReport sendToPH(Date today) {
        List<String> people = userNames([SELECT Name FROM User WHERE IsActive = true AND Name IN :PH_USERS]);
        List<Move> vc = new List<Move>();
        for (Application__History h : [
            SELECT Parent.Name, NewValue, CreatedDate, CreatedById, CreatedBy.Name
            FROM Application__History
            WHERE CreatedDate = LAST_N_DAYS:180 AND Field = 'Status__c' AND CreatedBy.Name IN :PH_USERS
              AND Parent.Status__c IN :PH_DONE_STATUSES
            ORDER BY CreatedDate DESC
        ]) {
            if (h.NewValue == 'Printing House') {
                vc.add(new Move(h.Parent.Name, 'Printing House', h.CreatedBy.Name, null, h.CreatedDate));
            }
        }
        List<Move> claimHistory = new List<Move>();
        for (Basic__History h : [
            SELECT Parent.Name, NewValue, CreatedDate, CreatedById, CreatedBy.Name
            FROM Basic__History
            WHERE CreatedDate = LAST_N_DAYS:365 AND Field = 'Status__c' AND Parent.Name NOT IN :TEST_RECORDS
            ORDER BY CreatedDate DESC
        ]) {
            claimHistory.add(new Move(h.Parent.Name, String.valueOf(h.NewValue), h.CreatedBy.Name, h.CreatedById, h.CreatedDate));
        }
        setUserTypes(claimHistory);
        return moveReport(today, people, firstPerRecord(vc), creditSignatures(claimHistory),
            'Total Sent', 'Vol Contributions Sent to Printing House', 'Claims Signed on DocuSign');
    }

    private static XpAgentSalesController.SalesReport pensionKeeper(Date today) {
        List<List<Date>> windows = XpAgentSalesController.periodWindows(today);
        Date since = windows[windows.size() - 1][0]; // first day of last quarter, the oldest period
        List<String> pkAgents = activeValues(Application__c.PK_Sale_Agent__c);
        List<String> reapplyAgents = activeValues(Reapply__c.Agent__c);

        Tally pk = new Tally(windows, new Set<String>(pkAgents));
        for (Application__c app : [
            SELECT PK_Sale_Agent__c, PK_Registration_Date__c
            FROM Application__c
            WHERE PK_Portal_User_Active__c = true AND PK_Registration_Date__c >= :since AND Status__c != 'Deposit Refund'
        ]) {
            pk.add(app.PK_Sale_Agent__c != null ? app.PK_Sale_Agent__c : 'None', app.PK_Registration_Date__c, 1);
        }

        // A Reapply counts once, on the day of its first paid payment; paid through the link with no agent = None
        Tally reapply = new Tally(windows, new Set<String>(reapplyAgents));
        Set<Id> counted = new Set<Id>();
        for (Reapply_Payment__c payment : [
            SELECT Reapply__c, Reapply__r.Agent__c, Payment_Date__c, CreatedDate
            FROM Reapply_Payment__c
            WHERE Status__c = 'Paid' AND Refunded__c = false AND Reapply__c != null
              AND Reapply__r.Status__c != 'Deposit Refund' AND Reapply__r.Name NOT IN :TEST_RECORDS
            ORDER BY Payment_Date__c ASC NULLS LAST, CreatedDate ASC
        ]) {
            if (!counted.add(payment.Reapply__c)) {
                continue;
            }
            Date paid = payment.Payment_Date__c != null ? payment.Payment_Date__c : payment.CreatedDate.date();
            reapply.add(payment.Reapply__r.Agent__c != null ? payment.Reapply__r.Agent__c : 'None', paid, 1);
        }

        List<String> columns = new List<String>();
        Set<String> seen = new Set<String>();
        for (List<String> source : new List<List<String>>{ pkAgents, reapplyAgents }) {
            for (String agent : source) {
                if (!HIDDEN_AGENTS.contains(agent) && seen.add(agent)) {
                    columns.add(agent);
                }
            }
        }
        return toReport(columns, new List<XpAgentSalesController.SalesTable>{
            pk.plus(reapply).toTable('total', 'Total Sales', SALE_PERIODS, columns),
            pk.toTable('pk', 'Pension Keeper Sales', SALE_PERIODS, columns),
            reapply.toTable('reapply', 'Reapply Sales', SALE_PERIODS, columns)
        });
    }

    // Vol Contributions: only the old report's people. Claims: anyone, and people who are not on the old report
    // get a column after the old ones.
    @TestVisible
    private static XpAgentSalesController.SalesReport moveReport(Date today, List<String> people, List<Move> vcMoves,
            List<Move> claimMoves, String totalTitle, String vcTitle, String claimsTitle) {
        List<List<Date>> windows = moveWindows(today);
        Tally vc = new Tally(windows, new Set<String>(people));
        for (Move m : vcMoves) {
            vc.add(m.userName, Date.valueOf(m.createdDate), 1);
        }
        Tally claims = new Tally(windows, null);
        for (Move m : claimMoves) {
            claims.add(m.userName, Date.valueOf(m.createdDate), 1);
        }
        List<String> columns = new List<String>(people);
        List<String> extra = new List<String>();
        for (String person : claims.people()) {
            if (!columns.contains(person)) {
                extra.add(person);
            }
        }
        extra.sort();
        columns.addAll(extra);
        return toReport(columns, new List<XpAgentSalesController.SalesTable>{
            vc.plus(claims).toTable('total', totalTitle, MOVE_PERIODS, columns),
            vc.toTable('vc', vcTitle, MOVE_PERIODS, columns),
            claims.toTable('claims', claimsTitle, MOVE_PERIODS, columns)
        });
    }

    // Claims moved to a status by a person, newest first
    private static List<Move> claimMovesTo(String status) {
        List<Move> moves = new List<Move>();
        for (Basic__History h : [
            SELECT Parent.Name, NewValue, CreatedDate, CreatedById, CreatedBy.Name
            FROM Basic__History
            WHERE CreatedDate = LAST_N_DAYS:180 AND Field = 'Status__c' AND Parent.Name NOT IN :TEST_RECORDS
            ORDER BY CreatedDate DESC
        ]) {
            if (h.NewValue == status) {
                moves.add(new Move(h.Parent.Name, status, h.CreatedBy.Name, h.CreatedById, h.CreatedDate));
            }
        }
        setUserTypes(moves);
        List<Move> byPeople = new List<Move>();
        for (Move m : moves) {
            if (m.byPerson()) {
                byPeople.add(m);
            }
        }
        return byPeople;
    }

    // History rows only reach the user's name, so the user type (person or automation) is looked up by Id
    private static void setUserTypes(List<Move> moves) {
        Set<Id> ids = new Set<Id>();
        for (Move m : moves) {
            ids.add(m.userId);
        }
        Map<Id, User> users = new Map<Id, User>([SELECT Id, UserType FROM User WHERE Id IN :ids]);
        for (Move m : moves) {
            m.userType = users.containsKey(m.userId) ? users.get(m.userId).UserType : null;
        }
    }

    // Like the old reports: each record once, at its latest move (the list is newest first)
    @TestVisible
    private static List<Move> firstPerRecord(List<Move> newestFirst) {
        List<Move> result = new List<Move>();
        Set<String> seen = new Set<String>();
        for (Move m : newestFirst) {
            if (seen.add(m.recordName)) {
                result.add(m);
            }
        }
        return result;
    }

    // Each claim once, on the day of its latest DocuSign signature, for the person who last sent it for signature
    // before that; a signature nobody sent by hand is not counted
    @TestVisible
    private static List<Move> creditSignatures(List<Move> newestFirst) {
        Map<String, List<Move>> byClaim = new Map<String, List<Move>>();
        List<String> order = new List<String>();
        for (Move m : newestFirst) {
            if (!byClaim.containsKey(m.recordName)) {
                byClaim.put(m.recordName, new List<Move>());
                order.add(m.recordName);
            }
            byClaim.get(m.recordName).add(m);
        }
        List<Move> credited = new List<Move>();
        for (String claim : order) {
            Move signature;
            for (Move m : byClaim.get(claim)) {
                if (signature == null && m.newValue == SIGNED) {
                    signature = m;
                } else if (signature != null && m.newValue == SENT_FOR_SIGNATURE && m.byPerson()) {
                    Move credit = new Move(claim, SIGNED, m.userName, m.userId, signature.createdDate);
                    credit.userType = m.userType;
                    credited.add(credit);
                    break;
                }
            }
        }
        return credited;
    }

    @TestVisible
    private static List<List<Date>> moveWindows(Date today) {
        List<List<Date>> all = XpAgentSalesController.periodWindows(today);
        List<List<Date>> windows = new List<List<Date>>();
        for (Integer i = 0; i < MOVE_PERIODS.size(); i++) {
            windows.add(all[i]);
        }
        return windows;
    }

    private static List<String> userNames(List<User> users) {
        List<String> names = new List<String>();
        for (User u : users) {
            names.add(u.Name);
        }
        return names;
    }

    private static List<String> activeValues(Schema.SObjectField field) {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                values.add(entry.getValue());
            }
        }
        return values;
    }

    private static XpAgentSalesController.SalesReport toReport(List<String> columns, List<XpAgentSalesController.SalesTable> tables) {
        XpAgentSalesController.SalesReport result = new XpAgentSalesController.SalesReport();
        result.agents = columns;
        result.tables = tables;
        return result;
    }

    @TestVisible
    private class Move {
        public String recordName;
        public String newValue;
        public String userName;
        public Id userId;
        public String userType;
        public Datetime createdDate;

        public Move(String recordName, String newValue, String userName, Id userId, Datetime createdDate) {
            this.recordName = recordName;
            this.newValue = newValue;
            this.userName = userName;
            this.userId = userId;
            this.createdDate = createdDate;
        }

        // A person, not an automation (DocuSign, the portal, the admin integration user)
        public Boolean byPerson() {
            return userType == 'Standard' && userName != 'XtraPension Admin';
        }
    }

    // Counts per person and period; allowed = null counts anyone
    private class Tally {
        private final List<List<Date>> windows;
        private final Set<String> allowed;
        private final Map<String, List<Integer>> byPerson = new Map<String, List<Integer>>();

        public Tally(List<List<Date>> windows, Set<String> allowed) {
            this.windows = windows;
            this.allowed = allowed;
        }

        public void add(String person, Date day, Integer weight) {
            if (person == null || day == null || (allowed != null && !allowed.contains(person))) {
                return;
            }
            List<Integer> counts = countsFor(person);
            for (Integer i = 0; i < windows.size(); i++) {
                if (day >= windows[i][0] && day <= windows[i][1]) {
                    counts[i] += weight;
                }
            }
        }

        public Set<String> people() {
            return byPerson.keySet();
        }

        public Tally plus(Tally other) {
            Tally sum = new Tally(windows, null);
            for (Tally part : new List<Tally>{ this, other }) {
                for (String person : part.byPerson.keySet()) {
                    List<Integer> source = part.byPerson.get(person);
                    List<Integer> target = sum.countsFor(person);
                    for (Integer i = 0; i < source.size(); i++) {
                        target[i] += source[i];
                    }
                }
            }
            return sum;
        }

        // Total includes people without a column (agents who left), like the old Total columns
        public XpAgentSalesController.SalesTable toTable(String key, String title, List<String> periods, List<String> columns) {
            XpAgentSalesController.SalesTable table = new XpAgentSalesController.SalesTable();
            table.key = key;
            table.title = title;
            table.rows = new List<XpAgentSalesController.SalesRow>();
            for (Integer i = 0; i < periods.size(); i++) {
                XpAgentSalesController.SalesRow row = new XpAgentSalesController.SalesRow();
                row.name = periods[i];
                row.total = 0;
                for (List<Integer> counts : byPerson.values()) {
                    row.total += counts[i];
                }
                row.counts = new List<Integer>();
                for (String person : columns) {
                    row.counts.add(byPerson.containsKey(person) ? byPerson.get(person)[i] : 0);
                }
                table.rows.add(row);
            }
            return table;
        }

        private List<Integer> countsFor(String person) {
            if (!byPerson.containsKey(person)) {
                List<Integer> zeros = new List<Integer>();
                for (Integer i = 0; i < windows.size(); i++) {
                    zeros.add(0);
                }
                byPerson.put(person, zeros);
            }
            return byPerson.get(person);
        }
    }
}