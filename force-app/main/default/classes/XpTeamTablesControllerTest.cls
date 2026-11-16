@IsTest
private class XpTeamTablesControllerTest {
    private static XpTeamTablesController.Move move(String record, String status, String person, String userType, Datetime at) {
        XpTeamTablesController.Move m = new XpTeamTablesController.Move(record, status, person, null, at);
        m.userType = userType;
        return m;
    }

    @IsTest
    static void eachRecordCountsOnceAtItsLatestMove() {
        Datetime now = Datetime.now();
        List<XpTeamTablesController.Move> moves = XpTeamTablesController.firstPerRecord(new List<XpTeamTablesController.Move>{
            move('A1', 'Agent Check', 'Sean Byrne', 'Standard', now),
            move('A1', 'Agent Check', 'Becky McAllister', 'Standard', now.addDays(-3)),
            move('A2', 'Agent Check', 'Becky McAllister', 'Standard', now.addDays(-1))
        });
        System.assertEquals(2, moves.size());
        System.assertEquals('Sean Byrne', moves[0].userName);
    }

    @IsTest
    static void totalAddsVolContributionsAndClaimsWithClaimsOnlyPeopleAtTheEnd() {
        Date today = Date.today();
        Datetime now = Datetime.now();
        List<String> people = new List<String>{ 'Sean Byrne', 'Becky McAllister' };
        XpAgentSalesController.SalesReport report = XpTeamTablesController.moveReport(today, people,
            new List<XpTeamTablesController.Move>{
                move('A1', 'Agent Check', 'Sean Byrne', 'Standard', now),
                move('A2', 'Agent Check', 'Becky McAllister', 'Standard', now),
                move('A3', 'Agent Check', 'Someone Else', 'Standard', now) // not on the old report: not counted
            },
            new List<XpTeamTablesController.Move>{
                move('C1', 'Agent Check', 'Sean Byrne', 'Standard', now),
                move('C2', 'Agent Check', 'MaryClaire Mchatton', 'Standard', now)
            },
            'Total', 'Vol Contributions', 'Claims');

        System.assertEquals(new List<String>{ 'Sean Byrne', 'Becky McAllister', 'MaryClaire Mchatton' }, report.agents);
        System.assertEquals(3, report.tables.size());
        XpAgentSalesController.SalesTable total = report.tables[0];
        XpAgentSalesController.SalesTable vc = report.tables[1];
        XpAgentSalesController.SalesTable claims = report.tables[2];
        System.assertEquals(6, vc.rows.size(), 'Today to Last Month, like the old reports');
        System.assertEquals('Today', vc.rows[0].name);
        System.assertEquals(2, vc.rows[0].total);
        System.assertEquals(new List<Integer>{ 1, 1, 0 }, vc.rows[0].counts);
        System.assertEquals(2, claims.rows[0].total);
        System.assertEquals(new List<Integer>{ 1, 0, 1 }, claims.rows[0].counts);
        System.assertEquals(4, total.rows[0].total);
        System.assertEquals(new List<Integer>{ 2, 1, 1 }, total.rows[0].counts);
        System.assertEquals(0, total.rows[1].total, 'nothing yesterday');
    }

    @IsTest
    static void signatureCountsForWhoeverSentTheClaimForSignature() {
        Datetime now = Datetime.now();
        List<XpTeamTablesController.Move> credited = XpTeamTablesController.creditSignatures(new List<XpTeamTablesController.Move>{
            move('C1', 'Signed - Waiting Docs at WDM', 'DocuSign', 'Guest', now),
            move('C1', 'Sent for eSignature', 'Fiona Carey', 'Standard', now.addDays(-2)),
            move('C1', 'Sent for eSignature', 'Rob Landy', 'Standard', now.addDays(-5)),
            move('C2', 'Signed - Waiting Docs at WDM', 'DocuSign', 'Guest', now),
            move('C2', 'Sent for eSignature', 'XtraPension Admin', 'Standard', now.addDays(-1)),
            move('C3', 'Sent for eSignature', 'Fiona Carey', 'Standard', now)
        });
        System.assertEquals(1, credited.size(), 'C2 was sent by the integration user and C3 is not signed yet');
        System.assertEquals('C1', credited[0].recordName);
        System.assertEquals('Fiona Carey', credited[0].userName);
        System.assertEquals(now, credited[0].createdDate, 'counted on the day it was signed');
    }

    @IsTest
    static void everyReportBuildsThreeTables() {
        Test.startTest();
        for (String report : new List<String>{ 'agentCheck', 'qcApproved', 'sendToPH', 'pensionKeeper' }) {
            XpAgentSalesController.SalesReport result = XpTeamTablesController.getTables(report);
            System.assertEquals(3, result.tables.size(), report);
            System.assertEquals(result.agents.size(), result.tables[0].rows[0].counts.size(), report);
        }
        Test.stopTest();
        System.assertEquals(8, XpTeamTablesController.getTables('pensionKeeper').tables[2].rows.size(), 'sales periods include the quarters');
        System.assertEquals('Reapply Sales', XpTeamTablesController.getTables('pensionKeeper').tables[2].title);
        Boolean failed = false;
        try {
            XpTeamTablesController.getTables('nope');
        } catch (AuraHandledException e) {
            failed = true;
        }
        System.assert(failed, 'unknown report');
    }
}