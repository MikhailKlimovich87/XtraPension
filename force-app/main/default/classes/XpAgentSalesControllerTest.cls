@IsTest
private class XpAgentSalesControllerTest {
    @TestSetup
    static void makeData() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Id contactId = [SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1].Id;

        List<Application__c> apps = new List<Application__c>();
        Application__c sale = TestDataFactory.createApplication(contactId, false);
        sale.Agent_Making_Sale__c = 'Sean';
        apps.add(sale);
        Application__c appeal = TestDataFactory.createApplication(contactId, false);
        appeal.Agent_Making_Sale__c = 'Sean';
        appeal.Appeal_Application__c = true;
        apps.add(appeal);
        Application__c leftAgent = TestDataFactory.createApplication(contactId, false);
        leftAgent.Agent_Making_Sale__c = 'Carmel';
        apps.add(leftAgent);
        insert apps;

        List<Basic__c> claims = new List<Basic__c>{
            new Basic__c(First_Name__c = 'Claim', Status__c = 'Form In Progress', Agent_Making_Sale__c = 'Sean'),
            new Basic__c(First_Name__c = 'Claim', Status__c = 'Form In Progress', Agent_Making_Sale__c = 'John'),
            new Basic__c(First_Name__c = 'Yesterday', Status__c = 'Form In Progress', Agent_Making_Sale__c = 'Sean'),
            new Basic__c(First_Name__c = 'Refunded', Status__c = 'Deposit Refund', Agent_Making_Sale__c = 'Sean')
        };
        insert claims;
        Test.setCreatedDate(claims[2].Id, Datetime.now().addDays(-1));
    }

    @IsTest
    static void countsEachTableAndAddsThemUpInTotal() {
        Test.startTest();
        XpAgentSalesController.SalesReport report = XpAgentSalesController.getSales();
        Test.stopTest();

        Integer sean = report.agents.indexOf('Sean');
        Integer john = report.agents.indexOf('John');
        System.assert(sean >= 0, 'Sean has a column');
        System.assert(john > sean, 'Claims-only agents come after the Vol Contributions agents');
        System.assertEquals(-1, report.agents.indexOf('Carmel'), 'agents who left have no column');
        System.assertEquals(-1, report.agents.indexOf('Mike'), 'agents who left have no column');

        System.assertEquals(3, report.tables.size());
        XpAgentSalesController.SalesTable total = report.tables[0];
        XpAgentSalesController.SalesTable vc = report.tables[1];
        XpAgentSalesController.SalesTable claims = report.tables[2];
        System.assertEquals('Total Sales', total.title);
        System.assertEquals('Vol Contributions Sales', vc.title);
        System.assertEquals('Claims Sales', claims.title);
        System.assertEquals(8, vc.rows.size());
        System.assertEquals('Today', vc.rows[0].name);
        System.assertEquals('Yesterday', vc.rows[1].name);

        // Vol Contributions today: Sean 1 + appeal 2, Carmel 1 (only in the Total column)
        System.assertEquals(4, vc.rows[0].total);
        System.assertEquals(3, vc.rows[0].counts[sean]);
        System.assertEquals(0, vc.rows[0].counts[john]);

        // Claims today: Sean 1, John 1; yesterday Sean 1; the Deposit Refund claim is out
        System.assertEquals(2, claims.rows[0].total);
        System.assertEquals(1, claims.rows[0].counts[sean]);
        System.assertEquals(1, claims.rows[0].counts[john]);
        System.assertEquals(1, claims.rows[1].total);

        System.assertEquals(6, total.rows[0].total);
        System.assertEquals(4, total.rows[0].counts[sean]);
        System.assertEquals(1, total.rows[0].counts[john]);
        System.assertEquals(1, total.rows[1].total);
    }

    @IsTest
    static void periodWindows() {
        List<List<Date>> windows = XpAgentSalesController.periodWindows(Date.newInstance(2026, 11, 5));
        System.assertEquals(Date.newInstance(2026, 11, 4), windows[1][0]);
        System.assertEquals(Date.newInstance(2026, 10, 1), windows[5][0]);
        System.assertEquals(Date.newInstance(2026, 10, 31), windows[5][1]);
        System.assertEquals(Date.newInstance(2026, 10, 1), windows[6][0]);
        System.assertEquals(Date.newInstance(2026, 12, 31), windows[6][1]);
        System.assertEquals(Date.newInstance(2026, 7, 1), windows[7][0]);
        System.assertEquals(Date.newInstance(2026, 9, 30), windows[7][1]);
        System.assertEquals(windows[2][0].addDays(-7), windows[3][0], 'last week starts 7 days before this week');
        System.assertEquals(windows[2][0].addDays(-1), windows[3][1], 'last week ends the day before this week');
    }
}