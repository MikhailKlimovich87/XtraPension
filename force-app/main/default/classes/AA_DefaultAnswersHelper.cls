/**
 * AA_DefaultAnswersHelper — seeds every new AA_Application__c with the
 * office-policy default answers so Mary never has to ask them.
 *
 * 2026-08-26 — AA field-id reconciliation. The PC1 clone seeded PC question
 * ids (q_language, q_formats, q_email_correct, q0_backdate_accept, start,
 * q_letters_address, q_email_confirm, q221) that DO NOT EXIST in the DWP
 * Attendance Allowance form. Rebuilt against config/aa-flow.json:
 *
 *   welsh-language-speak = english   ("What language do you want us to speak to you in?")
 *   welsh-language-write = english   ("What language do you want us to write to you in?")
 *   alternative-formats  = format-standard  ("Which format should we use to contact you?" -> Standard letter)
 *   best-time-to-call    = best-time-no-preference  ("When is the best time to call you?", page DWP added on 2026-10-22)
 *   email-submit         = yes       ("Should we send an email to confirm you have submitted an application?")
 *                          (= no when the application has no email, see seedDefaults)
 *
 * `alternative-formats` became a single-choice RADIO on 2026-10-08: DWP
 * reworded the page to "Which format should we use to contact you?", added
 * "Standard letter (12-point Arial text on white paper)" and dropped the
 * checkbox list's "None, these do not apply to me" and "Textphone". The plain
 * code is stored now; src/fill/adapter.js still upgrades the old JSON array
 * ("["format-none"]") for any row written before the change.
 *
 * Removed vs PC1 (no safe AA equivalent):
 *   - q_email_correct   — AA has no "is this email correct?" gate.
 *   - q_letters_address — AA has no claimant "where to send letters" field.
 *   - q0_backdate_accept— Attendance Allowance does NOT backdate (pay date =
 *                         decision date), so there is no backdate consent page.
 *   - start             — synthetic client-form gate (src/fill/flow.js), not a
 *                         DWP field; absent behaves identically to "yes".
 *
 * LEFT OUT — needs Fernando's policy decision (see report):
 *   - who-is-applying / applying-someone-else / best-describe: the PC1 default
 *     q221='charity' maps to AA best-describe='charity', but that only exists
 *     in the "applying for someone else" branch and encodes XP's filing model.
 *     Not defaulted here (it would silently commit the whole someone-else
 *     journey). Mary's POLICY_DEFAULT_FIELDS is kept in lockstep with THIS map.
 *   - consent (GP/healthcare information-sharing yes/no): substantive medical
 *     consent — not auto-defaulted.
 *
 * Source__c = 'default' so the dashboard editor can distinguish an
 * office-policy value from one Mary heard on the call or a human typed.
 * Idempotent: skips the insert if the (Application, Field_Id) pair already
 * exists — safe on re-fires or manual re-runs.
 */
public with sharing class AA_DefaultAnswersHelper {

    private static final Map<String, String> DEFAULTS = new Map<String, String>{
        'welsh-language-speak' => 'english',
        'welsh-language-write' => 'english',
        'alternative-formats'  => 'format-standard',
        'best-time-to-call'    => 'best-time-no-preference',
        'email-submit'         => 'yes'
    };

    /** email-submit when no email is on file. Twin of mary.js seedPolicyDefaults. */
    @TestVisible
    private static final String NO_EMAIL_SUBMIT = 'no';

    public static void seedDefaults(List<AA_Application__c> newList) {
        if (newList == null || newList.isEmpty()) return;

        Set<Id> appIds = new Set<Id>();
        // audit 2026-10-02 F27 + wave 3: email-submit=yes walks the client into
        // the required contact-by-email page, which nobody can answer when we
        // hold no email, so the application got stuck. Wave 2 skipped the
        // default in that case, but then email-submit stayed open on every
        // path except Mary's mark-complete backstop (mary.js
        // seedPolicyDefaults): the form and the record page never ask it
        // (it is a hidden policy default) and the flow walk stopped there.
        // Both sides now agree on the backstop's rule: no email on file ->
        // email-submit = "no" (DWP sends no confirmation email); otherwise
        // "yes". Source stays 'default', so an operator can still change it.
        Set<Id> noEmail = new Set<Id>();
        for (AA_Application__c a : newList) {
            if (a.Id == null) continue;
            appIds.add(a.Id);
            if (String.isBlank(a.Email__c)) noEmail.add(a.Id);
        }
        if (appIds.isEmpty()) return;

        // De-dupe against any answers that already exist for these apps
        // (paranoia — an after-insert normally sees a clean slate, but a
        // future upsert path could hit us again).
        Set<String> already = new Set<String>();
        for (AA_Answer__c a : [
            SELECT Application__c, Field_Id__c
            FROM AA_Answer__c
            WHERE Application__c IN :appIds AND Field_Id__c IN :DEFAULTS.keySet()
        ]) {
            already.add(a.Application__c + '|' + a.Field_Id__c);
        }

        List<AA_Answer__c> toInsert = new List<AA_Answer__c>();
        for (Id appId : appIds) {
            for (String fieldId : DEFAULTS.keySet()) {
                if (already.contains(appId + '|' + fieldId)) continue;
                String value = (fieldId == 'email-submit' && noEmail.contains(appId))
                    ? NO_EMAIL_SUBMIT
                    : DEFAULTS.get(fieldId);
                toInsert.add(new AA_Answer__c(
                    Application__c = appId,
                    Field_Id__c    = fieldId,
                    Value__c       = value,
                    Source__c      = 'default'
                ));
            }
        }
        if (!toInsert.isEmpty()) insert toInsert;
    }
}