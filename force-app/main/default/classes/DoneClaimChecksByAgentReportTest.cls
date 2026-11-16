@IsTest
public class DoneClaimChecksByAgentReportTest {
    @TestSetup
    static void makeData() {
        Basic__c claim = new Basic__c(First_Name__c = 'Posted', Last_Name__c = 'Claim', Status__c = 'Posted to DWP');
        insert claim;
        insert new List<Claim_Check__c>{
            new Claim_Check__c(Basic__c = claim.Id, Check_Agents__c = 'Daniel', Check_Date__c = Date.today(), Not_Received__c = true),
            new Claim_Check__c(Basic__c = claim.Id, Check_Agents__c = 'Vince', Check_Date__c = Date.today(), Processing__c = true)
        };
    }

    @IsTest
    static void countsTodaysChecksPerAgent() {
        Test.startTest();
        DoneCheckRequestsByAgentReportController.AgentAppsWrapper result = DoneClaimChecksByAgentReportController.getClaimCheckAgentsData();
        Test.stopTest();

        System.assertEquals(8, result.dateData.size());
        Integer daniel = result.agentsName.indexOf('Daniel');
        Integer vince = result.agentsName.indexOf('Vince');
        for (DoneCheckRequestsByAgentReportController.DateDifferenceWrapper row : result.dateData) {
            if (row.name == 'Today' || row.name == 'This Week' || row.name == 'This Month' || row.name == 'This Qtr') {
                System.assertEquals(2, row.fullCount, row.name);
                System.assertEquals(1, row.countData[daniel], row.name);
                System.assertEquals(1, row.countData[vince], row.name);
            }
            if (row.name == 'Yesterday' || row.name == 'Last Week' || row.name == 'Last Month' || row.name == 'Last Qtr') {
                System.assertEquals(0, row.fullCount, row.name);
            }
        }
        System.assertEquals(0, result.amountByDay.size(), 'no chart on the Claims table');
    }
}