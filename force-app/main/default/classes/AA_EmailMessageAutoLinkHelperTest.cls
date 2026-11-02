/**
 * Tests for AA_EmailMessageAutoLinkHelper / AA_EmailMessageAutoLinkTrigger
 * (audit 2026-10-02 F80/F157: no test class; the trigger could sit at 0%,
 * which blocks a production deploy outright).
 *
 * Pins the two F82 fixes: automated (Draft-inserted) mirrors no longer bump
 * Last_Contact_*, and To lists joined with ", " (the dispatcher's format)
 * are split like ";"-joined ones.
 */
@IsTest
private class AA_EmailMessageAutoLinkHelperTest {

    private static AA_Application__c makeApp() {
        AA_Application__c a = new AA_Application__c(
            First_Name__c = 'Em', Last_Name__c = 'Link', Stage__c = 'New', Email__c = 'em.link@example.test');
        insert a;
        return a;
    }

    @IsTest static void a_human_sent_email_stamps_the_flag_and_last_contact() {
        AA_Application__c app = makeApp();
        Datetime sentAt = Datetime.now().addMinutes(-5);
        EmailMessage em = new EmailMessage(RelatedToId = app.Id, Subject = 'Hello', Status = '3',
            Incoming = false, MessageDate = sentAt, ToAddress = 'em.link@example.test', TextBody = 'x');
        Test.startTest();
        insert em;
        Test.stopTest();

        System.assertEquals(true, [SELECT Is_AA_Application__c FROM EmailMessage WHERE Id = :em.Id].Is_AA_Application__c);
        AA_Application__c after = [SELECT Last_Contact_Type__c, Last_Contact_At__c, Last_Contact_Who__c FROM AA_Application__c WHERE Id = :app.Id];
        System.assertEquals('Email Sent', after.Last_Contact_Type__c);
        System.assertEquals(sentAt, after.Last_Contact_At__c);
        System.assertEquals(UserInfo.getName(), after.Last_Contact_Who__c);
    }

    // AA_MessageDispatcher inserts its mirrors as Draft ('5'): an automated
    // email is not a human contact and must not overwrite Last Contact.
    @IsTest static void an_automated_draft_mirror_does_not_bump_last_contact() {
        AA_Application__c app = makeApp();
        insert new EmailMessage(RelatedToId = app.Id, Subject = 'Advance notice', Status = '5',
            Incoming = false, MessageDate = Datetime.now(), ToAddress = 'em.link@example.test', TextBody = 'x');
        AA_Application__c after = [SELECT Last_Contact_Type__c, Last_Contact_At__c FROM AA_Application__c WHERE Id = :app.Id];
        System.assertEquals(null, after.Last_Contact_At__c, 'a dispatcher mirror must not count as a contact');
        System.assertEquals(null, after.Last_Contact_Type__c);
    }

    @IsTest static void contacts_are_linked_from_comma_and_semicolon_lists() {
        AA_Application__c app = makeApp();
        Contact c1 = new Contact(LastName = 'One', Email = 'one@example.test');
        Contact c2 = new Contact(LastName = 'Two', Email = 'two@example.test');
        insert new List<Contact>{ c1, c2 };
        EmailMessage a = new EmailMessage(RelatedToId = app.Id, Subject = 'a', Status = '3', Incoming = false,
            MessageDate = Datetime.now(), ToAddress = 'one@example.test, two@example.test', TextBody = 'x');
        EmailMessage b = new EmailMessage(RelatedToId = app.Id, Subject = 'b', Status = '3', Incoming = false,
            MessageDate = Datetime.now(), ToAddress = 'one@example.test;two@example.test', TextBody = 'x');
        insert new List<EmailMessage>{ a, b };

        for (EmailMessage em : new List<EmailMessage>{ a, b }) {
            Set<Id> related = new Set<Id>();
            for (EmailMessageRelation r : [SELECT RelationId FROM EmailMessageRelation
                                            WHERE EmailMessageId = :em.Id AND RelationType = 'ToAddress' AND RelationId != null]) {
                related.add(r.RelationId);
            }
            System.assert(related.contains(c1.Id) && related.contains(c2.Id),
                'both recipients must be linked for "' + em.Subject + '": ' + related);
        }
    }

    @IsTest static void emails_not_on_an_application_are_ignored() {
        insert new EmailMessage(Subject = 'loose', Status = '3', Incoming = false,
            MessageDate = Datetime.now(), ToAddress = 'x@example.test', TextBody = 'x');
        System.assertEquals(0, [SELECT COUNT() FROM EmailMessage WHERE Is_AA_Application__c = true]);
    }
}