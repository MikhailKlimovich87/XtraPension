@IsTest
private class XpMissingInfoPanelTest {

    @TestSetup
    static void makeData() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Id contactId = [SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1].Id;
        TestDataFactory.createApplication(contactId, true);
        TestDataFactory.createXtraPensionDataCustomSetting(true);
        Contact c = new Contact(LastName = 'Snow', Email = 'john.snow@example.com');
        insert c;
        Basic__c b = BP_TestDataFactory.createBasic(c.Id, false);
        b.Bank_BIC__c = null;
        insert b;
    }

    // Application: a resposta do Sales como ela é (sem as chaves do Claim).
    @IsTest
    static void applicationGetsTheSalesAnswerAsItIs() {
        Application__c a = [SELECT Id FROM Application__c LIMIT 1];
        a.National_Insurance_Number__c = null;
        update a;
        Map<String, Object> viaPanel = XpMissingInfoPanel.refresh(a.Id, true);
        Map<String, Object> direct = XpMissingInfo.refresh(a.Id);
        System.assertEquals(direct.keySet(), viaPanel.keySet());
        for (String k : new List<String>{ 'missing', 'optional', 'checks', 'clientCount', 'hasEmail', 'inStage', 'step', 'lastAsked' }) {
            System.assertEquals(direct.get(k), viaPanel.get(k), k);
        }
        System.assert(!viaPanel.containsKey('name') && !viaPanel.containsKey('blocking'), viaPanel.keySet());
        Map<String, Object> p = XpMissingInfoPanel.preview(a.Id, 'Following our call today,', null);
        Map<String, Object> q = XpMissingInfo.preview(a.Id, 'Following our call today,');
        System.assertEquals(q.get('subject'), p.get('subject'));
        System.assertEquals(q.get('whatsapp'), p.get('whatsapp'));
        System.assert(!p.containsKey('cc'), 'no copy row on Sales');
        Test.startTest();
        String result = XpMissingInfoPanel.sendEmail(a.Id, null, null);
        Test.stopTest();
        System.assert(result.startsWith('Sent to'), result);
    }

    // Claim: BP_MissingInfo, com as chaves do Sales, o WhatsApp e a cópia para o helper.
    @IsTest
    static void claimGetsTheClaimsAnswer() {
        Basic__c b = [SELECT Id, Name FROM Basic__c LIMIT 1];
        Map<String, Object> view = XpMissingInfoPanel.refresh(b.Id, true);
        System.assertEquals(b.Name, view.get('name'));
        System.assert((Integer) view.get('missing') > 0, view);
        System.assertEquals(true, view.get('inStage'));
        System.assertEquals('The client is on step 1 of 9, "Helper".', view.get('step'));
        System.assert([SELECT Missing_Info__c FROM Basic__c WHERE Id = :b.Id].Missing_Info__c.contains('Bank: BIC'), 'force writes Missing_Info__c');
        Map<String, Object> p = XpMissingInfoPanel.preview(b.Id, null, null);
        System.assert(p.containsKey('cc'));
        System.assert(((String) p.get('whatsapp')).contains('*Your bank account*'), p.get('whatsapp'));
        Test.startTest();
        String result = XpMissingInfoPanel.sendEmail(b.Id, null, null);
        Test.stopTest();
        System.assert(result.startsWith('Sent to'), result);
    }

    // Os itens desmarcados no preview (call de 11/11/2026) chegam à classe de cada objeto.
    @IsTest
    static void untickedItemsArePassedOn() {
        Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];
        Application__c a = [SELECT Id FROM Application__c LIMIT 1];
        a.National_Insurance_Number__c = null;
        update a;
        Map<Id, String> firstLine = new Map<Id, String>{
            b.Id => BP_MissingInfo.clientItems(BP_MissingInfo.check(BP_MissingInfo.load(b.Id)))[0].agentText,
            a.Id => XpMissingInfo.clientItems(XpMissingInfo.check(XpMissingInfo.load(a.Id), XpMissingInfo.fileTitles(a.Id)))[0].agentText
        };
        for (Id recordId : firstLine.keySet()) {
            Map<String, Object> all = XpMissingInfoPanel.preview(recordId, null, null);
            Map<String, Object> fewer = XpMissingInfoPanel.preview(recordId, null, new List<String>{ firstLine.get(recordId) });
            System.assertEquals((Integer) all.get('count') - 1, (Integer) fewer.get('count'), recordId + ': ' + firstLine.get(recordId));
        }
    }

    @IsTest
    static void otherRecordsAreRefused() {
        Id accountId = [SELECT Id FROM Account LIMIT 1].Id;
        for (Id recordId : new List<Id>{ accountId, null }) {
            Integer refused = 0;
            try { XpMissingInfoPanel.refresh(recordId, false); } catch (AuraHandledException e) { refused++; System.assert(e.getMessage().contains('application or a claim'), e.getMessage()); }
            try { XpMissingInfoPanel.preview(recordId, null, null); } catch (AuraHandledException e) { refused++; }
            try { XpMissingInfoPanel.sendEmail(recordId, null, null); } catch (AuraHandledException e) { refused++; }
            System.assertEquals(3, refused, 'refused for ' + recordId);
        }
    }

    // Call of 11/11/2026 17h13: the validation agent's questions go in the claim's email; an application ignores them
    @IsTest
    static void questionsOnlyOnAClaim() {
        Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];
        Map<String, Object> claimMail = XpMissingInfoPanel.previewAsking(b.Id, null, null, 'When did you leave the UK?');
        System.assert(((String) claimMail.get('html')).contains('When did you leave the UK?'), claimMail.get('html'));
        System.assertEquals(1, claimMail.get('questions'));

        Application__c a = [SELECT Id FROM Application__c LIMIT 1];
        a.National_Insurance_Number__c = null;
        update a;
        Map<String, Object> appMail = XpMissingInfoPanel.previewAsking(a.Id, null, null, 'When did you leave the UK?');
        System.assert(!((String) appMail.get('html')).contains('When did you leave the UK?'), 'Sales email unchanged');
        System.assertEquals(XpMissingInfo.preview(a.Id, null).get('html'), appMail.get('html'));

        Test.startTest();
        String claimSent = XpMissingInfoPanel.sendAsking(b.Id, null, null, 'When did you leave the UK?');
        String appSent = XpMissingInfoPanel.sendAsking(a.Id, null, null, 'ignored');
        Test.stopTest();
        System.assert(claimSent.startsWith('Sent to') && appSent.startsWith('Sent to'), claimSent + ' / ' + appSent);
    }
}