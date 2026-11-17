/**
 * "Your welcome pack is in the post" (John and Megan on the 6 Nov 2026 call): when the printer's BIG ENV POSTED
 * e-mail marks the Stage 1 pack as posted, the client gets one e-mail saying what is in the pack and what to do
 * with it. The helper is always in CC (Fernando, 4 Nov 2026). Called from XtraPensionEmailServiceHandler; a second
 * BIG ENV POSTED for the same claim (a re-post) does not send it again.
 */
public with sharing class XpWelcomePackEmail {

    public static final String TEMPLATE = 'BP_Welcome_Pack_Posted';
    // Australian claims get the Sydney office in the footer, like the devs' BP_AU_Claim (CurrencyIsoCode AUD).
    public static final String TEMPLATE_AU = 'BP_Welcome_Pack_Posted_AU';
    // Canadian claims (CurrencyIsoCode CAD): the toll-free number, and no Garda in the list of who can stamp a copy.
    public static final String TEMPLATE_CA = 'BP_Welcome_Pack_Posted_CA';
    private static final String ORG_WIDE_EMAIL = 'clients@xtrapension.com';

    // E-mails built in this transaction (tests cannot see sendEmail, which they skip).
    @TestVisible
    private static Integer prepared = 0;

    /** True while the claim has no posted date yet: read before the handler writes today's date. */
    public static Boolean notPostedYet(Id claimId) {
        for (Basic__c b : [SELECT Big_Envelop_Posted_Date__c FROM Basic__c WHERE Id = :claimId]) {
            return b.Big_Envelop_Posted_Date__c == null;
        }
        return false;
    }

    /** Sends the e-mail; a failure is logged and never fails the printer's e-mail (the posting is already saved). */
    public static void send(Id claimId) {
        try {
            Basic__c claim = [SELECT Id, Email__c, Friend_Email__c, CurrencyIsoCode FROM Basic__c WHERE Id = :claimId];
            if (String.isBlank(claim.Email__c)) {
                logError(claimId, 'the claim has no e-mail');
                return;
            }
            String templateName = templateFor(claim.CurrencyIsoCode);
            List<EmailTemplate> template = [SELECT Id FROM EmailTemplate WHERE DeveloperName = :templateName LIMIT 1];
            if (template.isEmpty()) {
                logError(claimId, 'template ' + templateName + ' not found');
                return;
            }
            Id contactId = BP_PortalUtils.resolveEmailContactId(claimId, 'Welcome pack posted');
            if (contactId == null) {
                return;
            }

            Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
            message.setTargetObjectId(contactId);
            message.setTreatTargetObjectAsRecipient(false);
            message.setToAddresses(new String[] { claim.Email__c });
            String cc = helperCc(claim);
            if (cc != null) {
                message.setCcAddresses(new String[] { cc });
            }
            message.setTemplateId(template[0].Id);
            message.setWhatId(claimId);
            message.setUseSignature(false);
            message.setBccSender(false);
            message.setSaveAsActivity(true);
            for (OrgWideEmailAddress owa : [SELECT Id FROM OrgWideEmailAddress WHERE Address = :ORG_WIDE_EMAIL LIMIT 1]) {
                message.setOrgWideEmailAddressId(owa.Id);
            }
            prepared++;
            if (!Test.isRunningTest()) {
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage> { message });
            }
        } catch (Exception e) {
            logError(claimId, e.getMessage());
        }
    }

    /** The Australian template for AUD claims, the Canadian one for CAD, the Irish one for every other. */
    @TestVisible
    private static String templateFor(String currencyCode) {
        if (currencyCode == 'AUD') {
            return TEMPLATE_AU;
        }
        return currencyCode == 'CAD' ? TEMPLATE_CA : TEMPLATE;
    }

    /** The helper's e-mail for the CC: empty, or the same as the client's, stays out. */
    @TestVisible
    private static String helperCc(Basic__c claim) {
        String cc = claim.Friend_Email__c == null ? '' : claim.Friend_Email__c.trim();
        String to = claim.Email__c == null ? '' : claim.Email__c.trim();
        return cc != '' && !cc.equalsIgnoreCase(to) ? cc : null;
    }

    private static void logError(Id claimId, String why) {
        insert new Application_Form_Error__c(
            Error_Body__c = ('Welcome pack e-mail not sent for claim ' + claimId + ': ' + why).left(32000),
            Error_Date__c = Date.today()
        );
    }
}