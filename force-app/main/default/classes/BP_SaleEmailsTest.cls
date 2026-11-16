@IsTest
private class BP_SaleEmailsTest {
    private static XtraPension_Settings__mdt settings() {
        return [
            SELECT Admin_Email_Addresses__c, Sales_Agent_Name_By_Email__c
            FROM XtraPension_Settings__mdt
            WHERE DeveloperName = 'Configuration'
        ];
    }

    @IsTest
    static void saleEmailGoesToTheTeamWithTheDeposit() {
        Product2 deposit = new Product2(Name = 'Claim - Deposit', CurrencyIsoCode = 'EUR');
        insert deposit;
        Basic__c claim = new Basic__c(
            First_Name__c = 'Mary',
            Last_Name__c = 'Murphy',
            Status__c = 'Form In Progress',
            Agent_Making_Sale__c = 'Sean',
            Email__c = 'mary.murphy@example.com',
            Phone__c = '+353861234567',
            Current_Address_Abroad_Country_Name__c = 'Ireland',
            CurrencyIsoCode = 'EUR'
        );
        insert claim;
        insert new Basic_Payment__c(
            Basic__c = claim.Id,
            Product__c = deposit.Id,
            Amount__c = 600,
            Status__c = 'Paid',
            CurrencyIsoCode = 'EUR'
        );

        Test.startTest();
        Messaging.SingleEmailMessage message = BP_PortalUtils.saleEmail(claim.Id);
        BP_PortalUtils.sendSaleEmailToTeam(claim.Id);
        Test.stopTest();

        System.assertEquals('Claim - Ireland - Sean - (Mary Murphy) - € 600 sale', message.getSubject());
        List<String> team = (List<String>) JSON.deserialize(settings().Admin_Email_Addresses__c, List<String>.class);
        List<String> expected = new List<String>();
        for (String address : team) {
            if (address.toLowerCase() != 'patrick@xtrapension.com' && address.toLowerCase() != 'mary@xtrapension.com') {
                expected.add(address);
            }
        }
        System.assertEquals(expected, message.getToAddresses(), 'the Vol Contributions sale list without Patrick and MaryClaire');
        System.assert(message.getHtmlBody().contains('mary.murphy@example.com'));
    }

    @IsTest
    static void agentEmailComesFromTheSalesAgentMap() {
        Map<String, String> emailByAgent = (Map<String, String>) JSON.deserialize(
            settings().Sales_Agent_Name_By_Email__c, Map<String, String>.class
        );
        System.assertEquals(emailByAgent.get('Sean'), BP_PortalUtils.saleAgentEmail('Sean'));
        System.assertEquals(null, BP_PortalUtils.saleAgentEmail('Patrick'), 'Patrick only gets the Vol Contributions welcome BCC');
        System.assertEquals(null, BP_PortalUtils.saleAgentEmail('MaryClaire'), 'MaryClaire only gets the Vol Contributions welcome BCC');
        System.assertEquals(null, BP_PortalUtils.saleAgentEmail('Nobody'));
        System.assertEquals(null, BP_PortalUtils.saleAgentEmail(null));
    }
}