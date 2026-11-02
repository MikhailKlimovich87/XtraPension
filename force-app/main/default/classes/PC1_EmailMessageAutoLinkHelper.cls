/**
 * PC1_EmailMessageAutoLinkHelper — after-insert EmailMessage → auto-link
 * matching Contacts via EmailMessageRelation so the Activity Timeline shows
 * proper contact avatars/names instead of raw email addresses.
 *
 * Scoped to EmailMessages related to a PC1_Application__c (RelatedToId
 * prefix). Other EmailMessages (Case, standard objects) are unaffected.
 */
public class PC1_EmailMessageAutoLinkHelper {

    // PC1_Application__c has KeyPrefix 'a1V' in this org (auto-numbered
    // Application ID PC00xxx). If the object is ever re-created the prefix
    // could change — we resolve it dynamically once at class load.
    private static final String PC1_APP_PREFIX = PC1_Application__c.SObjectType.getDescribe().getKeyPrefix();

    public static void linkContacts(List<EmailMessage> newRows) {
        // Only care about EmailMessages tied to PC1_Applications.
        List<EmailMessage> pc1Rows = new List<EmailMessage>();
        Set<String> addressBag = new Set<String>();
        for (EmailMessage em : newRows) {
            if (em.RelatedToId == null) continue;
            if (String.valueOf(em.RelatedToId).startsWith(PC1_APP_PREFIX)) {
                pc1Rows.add(em);
                if (String.isNotBlank(em.FromAddress)) addressBag.add(em.FromAddress.toLowerCase());
                if (String.isNotBlank(em.ToAddress)) {
                    for (String a : em.ToAddress.split(';')) {
                        String t = a.trim();
                        if (String.isNotBlank(t)) addressBag.add(t.toLowerCase());
                    }
                }
            }
        }
        if (pc1Rows.isEmpty()) return;

        // ── Stamp Is_PC1_Application__c=true on all PC1-linked rows so the
        //    "PC1 Applications" list view on the standard EmailMessage tab
        //    can filter cleanly (formula fields can't traverse the polymorphic
        //    RelatedToId, hence a trigger-populated checkbox).
        List<EmailMessage> stampable = new List<EmailMessage>();
        for (EmailMessage em : pc1Rows) {
            if (em.Is_PC1_Application__c != true) {
                stampable.add(new EmailMessage(Id = em.Id, Is_PC1_Application__c = true));
            }
        }
        if (!stampable.isEmpty()) {
            try { update stampable; }
            catch (DmlException e) {
                System.debug(LoggingLevel.WARN, 'Is_PC1_Application stamp failure: ' + e.getMessage());
            }
        }

        // ── Last Contact mirror on outbound emails. EmailMessage.Incoming=false
        //    means it was sent by an SF user (Send Email quick-action / list-
        //    email). Group by parent Application, keep the newest MessageDate,
        //    and patch Last_Contact_* with latest-wins gate.
        Map<Id, EmailMessage> bestByApp = new Map<Id, EmailMessage>();
        for (EmailMessage em : pc1Rows) {
            if (em.Incoming == true) continue;
            if (em.MessageDate == null) continue;
            Id appId = em.RelatedToId;
            EmailMessage prev = bestByApp.get(appId);
            if (prev == null || em.MessageDate > prev.MessageDate) bestByApp.put(appId, em);
        }
        // Preload SF User names for the CreatedBy of best outbound emails —
        // 2026-08-01 Fernando: Who should reflect the SF user who sent it.
        Set<Id> creatorIds = new Set<Id>();
        for (EmailMessage em : bestByApp.values()) if (em.CreatedById != null) creatorIds.add(em.CreatedById);
        Map<Id, String> userNames = new Map<Id, String>();
        if (!creatorIds.isEmpty()) {
            for (User u : [SELECT Id, Name FROM User WHERE Id IN :creatorIds]) userNames.put(u.Id, u.Name);
        }
        if (!bestByApp.isEmpty()) {
            Map<Id, PC1_Application__c> apps = new Map<Id, PC1_Application__c>(
                [SELECT Id, Last_Contact_At__c FROM PC1_Application__c WHERE Id IN :bestByApp.keySet()]
            );
            List<PC1_Application__c> lcPatch = new List<PC1_Application__c>();
            for (Id appId : bestByApp.keySet()) {
                PC1_Application__c app = apps.get(appId);
                if (app == null) continue;
                EmailMessage em = bestByApp.get(appId);
                if (app.Last_Contact_At__c != null && app.Last_Contact_At__c >= em.MessageDate) continue;
                lcPatch.add(new PC1_Application__c(
                    Id                    = appId,
                    Last_Contact_Type__c  = 'Email Sent',
                    Last_Contact_Who__c   = userNames.get(em.CreatedById),
                    Last_Contact_At__c    = em.MessageDate,
                    Last_Contact_Date__c  = em.MessageDate.date()
                ));
            }
            if (!lcPatch.isEmpty()) {
                try { update lcPatch; }
                catch (DmlException e) {
                    System.debug(LoggingLevel.WARN, 'Last-contact email bump failure: ' + e.getMessage());
                }
            }
        }

        if (addressBag.isEmpty()) return;

        // Find Contacts matching any of the bag addresses (SOQL is case-insensitive on Email).
        Map<String, Id> contactByEmail = new Map<String, Id>();
        for (Contact c : [SELECT Id, Email FROM Contact WHERE Email IN :addressBag]) {
            if (c.Email != null) contactByEmail.put(c.Email.toLowerCase(), c.Id);
        }
        if (contactByEmail.isEmpty()) return;

        // Skip EMRs that already exist (idempotent re-fires + fold-in with
        // whatever the platform / other triggers already inserted).
        Set<Id> emIds = new Set<Id>();
        for (EmailMessage em : pc1Rows) emIds.add(em.Id);
        Set<String> existingKeys = new Set<String>();
        for (EmailMessageRelation existing : [
            SELECT EmailMessageId, RelationId, RelationType
            FROM EmailMessageRelation
            WHERE EmailMessageId IN :emIds AND RelationId != null
        ]) {
            existingKeys.add(existing.EmailMessageId + '|' + existing.RelationId + '|' + existing.RelationType);
        }

        List<EmailMessageRelation> toInsert = new List<EmailMessageRelation>();
        for (EmailMessage em : pc1Rows) {
            if (String.isNotBlank(em.FromAddress)) {
                Id cid = contactByEmail.get(em.FromAddress.toLowerCase());
                if (cid != null) tryQueue(toInsert, existingKeys, em.Id, cid, 'FromAddress');
            }
            if (String.isNotBlank(em.ToAddress)) {
                for (String a : em.ToAddress.split(';')) {
                    String t = a.trim().toLowerCase();
                    if (String.isBlank(t)) continue;
                    Id cid = contactByEmail.get(t);
                    if (cid != null) tryQueue(toInsert, existingKeys, em.Id, cid, 'ToAddress');
                }
            }
        }
        if (!toInsert.isEmpty()) {
            try { insert toInsert; }
            catch (DmlException e) {
                System.debug(LoggingLevel.WARN, 'EMR auto-link partial failure: ' + e.getMessage());
            }
        }
    }

    private static void tryQueue(List<EmailMessageRelation> bucket, Set<String> existing, Id emId, Id contactId, String relType) {
        String k = emId + '|' + contactId + '|' + relType;
        if (existing.contains(k)) return;
        existing.add(k);
        bucket.add(new EmailMessageRelation(
            EmailMessageId = emId,
            RelationId     = contactId,
            RelationType   = relType
        ));
    }
}