/**
 * Tests for small PC1 helpers below the 75% deploy threshold on 2026-10-02:
 * PC1_ValAgentAssignHelper, PC1_ApplicationNeedsHumanNotifyTrigger,
 * PC1_MaryProgressCalculator, PC1_RestUtil and PC1_PhoneNormalizer.
 */
@IsTest
private class PC1_HelpersTest {

    private static PC1_Application__c makeApp(String stage) {
        PC1_Application__c a = new PC1_Application__c(First_Name__c = 'He', Last_Name__c = 'Lper', Stage__c = stage);
        insert a;
        return a;
    }

    // ── Val agent weighted round-robin ───────────────────────────────

    @IsTest static void val_agents_assigned_by_weight() {
        insert new List<PC1_Val_Agent__c>{
            new PC1_Val_Agent__c(Name = 'Fiona', Weight__c = 3, Active__c = true),
            new PC1_Val_Agent__c(Name = 'Sean Byrne', Weight__c = 1, Active__c = true),
            new PC1_Val_Agent__c(Name = 'Off', Weight__c = 5, Active__c = false)
        };
        List<PC1_Application__c> apps = new List<PC1_Application__c>();
        for (Integer i = 0; i < 8; i++) apps.add(new PC1_Application__c(First_Name__c = 'A' + i, Last_Name__c = 'B', Stage__c = 'New'));
        insert apps;
        Map<String, Integer> counts = new Map<String, Integer>();
        for (PC1_Application__c a : [SELECT Val_Agent__c FROM PC1_Application__c]) {
            counts.put(a.Val_Agent__c, (counts.containsKey(a.Val_Agent__c) ? counts.get(a.Val_Agent__c) : 0) + 1);
        }
        System.assertEquals(6, counts.get('Fiona'), '3:1 split over 8 apps');
        System.assertEquals(2, counts.get('Sean Byrne'));
        System.assert(!counts.containsKey('Off'), 'inactive agents never assigned');

        // Pre-set agent is kept.
        PC1_Application__c kept = new PC1_Application__c(First_Name__c = 'K', Last_Name__c = 'P', Stage__c = 'New', Val_Agent__c = 'Sean Byrne');
        insert kept;
        System.assertEquals('Sean Byrne', [SELECT Val_Agent__c FROM PC1_Application__c WHERE Id = :kept.Id].Val_Agent__c);
    }

    @IsTest static void no_active_agents_leaves_blank() {
        PC1_Application__c a = makeApp('New');
        System.assertEquals(null, [SELECT Val_Agent__c FROM PC1_Application__c WHERE Id = :a.Id].Val_Agent__c);
    }

    // ── Needs Human chatter post ─────────────────────────────────────

    private static Integer needsHumanPosts(Id appId) {
        Integer n = 0;
        for (FeedItem f : [SELECT Body FROM FeedItem WHERE ParentId = :appId]) {
            if (f.Body != null && f.Body.startsWith('[Needs Human]')) n++;
        }
        return n;
    }

    @IsTest static void needs_human_posts_once_unless_handoff_explains_it() {
        PC1_Application__c a = makeApp('Partial Data');
        PC1_Application__c b = makeApp('Partial Data');
        insert new PC1_Handoff__c(Application__c = b.Id, Escalation_Type__c = 'confused', Reason__c = 'x');
        update new List<PC1_Application__c>{
            new PC1_Application__c(Id = a.Id, Stage__c = 'Needs Human'),
            new PC1_Application__c(Id = b.Id, Stage__c = 'Needs Human')
        };
        System.assertEquals(1, needsHumanPosts(a.Id));
        System.assertEquals(0, needsHumanPosts(b.Id), 'the Handoff already explains it');
        update new PC1_Application__c(Id = a.Id, Notes__c = 'still needs human');
        System.assertEquals(1, needsHumanPosts(a.Id), 'no repeat while it stays there');
    }

    // ── Mary progress ────────────────────────────────────────────────

    @IsTest static void mary_progress_single_and_bulk() {
        PC1_Application__c a = makeApp('New');
        insert new List<PC1_Answer__c>{
            new PC1_Answer__c(Application__c = a.Id, Field_Id__c = 'q3', Value__c = 'He', Source__c = 'mary'),
            new PC1_Answer__c(Application__c = a.Id, Field_Id__c = 'decl', Value__c = 'yes', Source__c = 'human')
        };
        PC1_MaryProgressCalculator.updateMaryProgress(a.Id);
        Decimal single = [SELECT Mary_Progress_Filled__c FROM PC1_Application__c WHERE Id = :a.Id].Mary_Progress_Filled__c;
        PC1_MaryProgressCalculator.updateMaryProgressBulk(new Set<Id>{ a.Id });
        PC1_Application__c after = [SELECT Mary_Progress_Filled__c, Mary_Progress_Total__c, Mary_Progress_Complete__c FROM PC1_Application__c WHERE Id = :a.Id];
        System.assertEquals(single, after.Mary_Progress_Filled__c, 'both paths agree; declaration not counted');
        System.assertEquals(70, after.Mary_Progress_Total__c);
        System.assertEquals(false, after.Mary_Progress_Complete__c);
        PC1_MaryProgressCalculator.updateMaryProgressBulk(new Set<Id>());
    }

    // ── REST helpers ─────────────────────────────────────────────────

    @IsTest static void rest_util() {
        PC1_Application__c a = makeApp('New');
        update new PC1_Application__c(Id = a.Id, Phone__c = '+447700900333', DWP_Reference__c = 'REF9');
        String name = [SELECT Name FROM PC1_Application__c WHERE Id = :a.Id].Name;

        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        System.assertEquals(0, PC1_RestUtil.parseBody().size());
        RestContext.request.requestBody = Blob.valueOf('not json');
        System.assert(PC1_RestUtil.parseBody().containsKey('_parseError'));
        RestContext.request.requestBody = Blob.valueOf('{"application_id":"' + a.Id + '"}');
        System.assertEquals(a.Id, PC1_RestUtil.findApplication(PC1_RestUtil.parseBody()).Id);

        System.assertEquals(a.Id, PC1_RestUtil.findApplication(new Map<String, Object>{ 'application_id' => name }).Id);
        System.assertEquals(a.Id, PC1_RestUtil.findApplication(new Map<String, Object>{ 'dwp_reference' => 'REF9' }).Id);
        System.assertEquals(a.Id, PC1_RestUtil.findApplication(new Map<String, Object>{ 'phone' => '+447700900333' }).Id);
        System.assertEquals(null, PC1_RestUtil.findApplication(new Map<String, Object>{ 'phone' => '+440000000000' }));

        PC1_RestUtil.writeError(400, 'bad');
        System.assertEquals(400, RestContext.response.statusCode);
        System.assert(RestContext.response.responseBody.toString().contains('bad'));
    }

    // ── Phone normalisation ──────────────────────────────────────────

    @IsTest static void phone_normaliser() {
        System.assertEquals('+447700900123', PC1_PhoneNormalizer.toE164('07700 900123'));
        System.assertEquals('+447700900123', PC1_PhoneNormalizer.toE164('0044 7700 900123'));
        System.assertEquals('+353861234567', PC1_PhoneNormalizer.toE164('086 123 4567', 'IE'));
        System.assertEquals('+353861234567', PC1_PhoneNormalizer.toE164('+353 86 123 4567'));
        System.assertEquals('+12025550123', PC1_PhoneNormalizer.toE164('1 202 555 0123'));
        System.assertEquals(null, PC1_PhoneNormalizer.toE164('123'));
        System.assertEquals(null, PC1_PhoneNormalizer.toE164('abc'));
        System.assertEquals(null, PC1_PhoneNormalizer.toE164(null));
        System.assertEquals('+4930123456', PC1_PhoneNormalizer.toE164('+49 30 123456'));
        PC1_PhoneNormalizer.normalize(null);
        PC1_Application__c a = new PC1_Application__c(First_Name__c = 'P', Last_Name__c = 'N', Stage__c = 'New',
            Phone__c = '07700 900123', Helper_Phone__c = '07700 900124');
        insert a;
        PC1_Application__c after = [SELECT Phone__c, Helper_Phone__c FROM PC1_Application__c WHERE Id = :a.Id];
        System.assertEquals('+447700900123', after.Phone__c);
        System.assertEquals('+447700900124', after.Helper_Phone__c);
    }

    // ── EmailMessage auto-link (contacts + last contact) ─────────────

    @IsTest static void outbound_email_links_contacts_and_bumps_last_contact() {
        PC1_Application__c a = makeApp('Awaiting First Call');
        Contact c = new Contact(LastName = 'Client', Email = 'client.link@example.org');
        insert c;
        Datetime sent = Datetime.now().addMinutes(-5);
        insert new EmailMessage(RelatedToId = a.Id, Incoming = false, Status = '3', Subject = 'Welcome',
            FromAddress = 'clients@xtrapension.com', ToAddress = 'client.link@example.org; other@example.org',
            MessageDate = sent);
        // An older email must not move Last Contact backwards.
        insert new EmailMessage(RelatedToId = a.Id, Incoming = false, Status = '3', Subject = 'Old',
            FromAddress = 'client.link@example.org', ToAddress = 'clients@xtrapension.com', MessageDate = sent.addDays(-3));

        PC1_Application__c after = [SELECT Last_Contact_Type__c, Last_Contact_At__c FROM PC1_Application__c WHERE Id = :a.Id];
        System.assertEquals('Email Sent', after.Last_Contact_Type__c);
        System.assertEquals(sent, after.Last_Contact_At__c);
        System.assert([SELECT COUNT() FROM EmailMessageRelation WHERE RelationId = :c.Id] >= 1, 'contact linked on the timeline');
        System.assertEquals(2, [SELECT COUNT() FROM EmailMessage WHERE RelatedToId = :a.Id AND Is_PC1_Application__c = true]);
    }
}