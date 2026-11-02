/**
 * PC1_DefaultAnswersHelper — seeds every new PC1_Application__c with the
 * office-policy default answers so Mary never has to ask them.
 *
 * Field mapping (kept in lockstep with config/pc1-flow.json's hidden+default
 * markers per Phase 1 of the boss brief 2026-08-18 — this Map is the SF-side
 * equivalent of the Node intake seeder's buildFlowDefaultRows()):
 *   q_language          = english      ("What language do you want us to speak to you in?")
 *   q_formats           = no           ("Do you need us to use any different formats?")
 *   q_email_correct     = yes          ("Is this email address correct?")
 *   q0_backdate_accept  = yes          (office policy: request the earliest permitted date)
 *   start               = yes          (Phase 1: sales pre-qualifies during intake)
 *   q_letters_address   = homeaddress  (Phase 1: home address for all correspondence)
 *   q_email_confirm     = yes          (Phase 1: always send submission confirmation)
 *
 * Source__c = 'default' so the dashboard editor can distinguish an
 * office-policy value from one Mary heard on the call or a human typed.
 * Idempotent: skips the insert if the (Application, Field_Id) pair already
 * exists — safe on re-fires or manual re-runs.
 */
public with sharing class PC1_DefaultAnswersHelper {

    private static final Map<String, String> DEFAULTS = new Map<String, String>{
        'q_language'          => 'english',
        'q_formats'           => 'no',
        'q_email_correct'     => 'yes',
        'q0_backdate_accept'  => 'yes',
        'start'               => 'yes',
        'q_letters_address'   => 'homeaddress',
        'q_email_confirm'     => 'yes',
        'q221'                => 'charity'
    };

    public static void seedDefaults(List<PC1_Application__c> newList) {
        if (newList == null || newList.isEmpty()) return;

        Set<Id> appIds = new Set<Id>();
        for (PC1_Application__c a : newList) if (a.Id != null) appIds.add(a.Id);
        if (appIds.isEmpty()) return;

        // De-dupe against any answers that already exist for these apps
        // (paranoia — an after-insert normally sees a clean slate, but a
        // future upsert path could hit us again).
        Set<String> already = new Set<String>();
        for (PC1_Answer__c a : [
            SELECT Application__c, Field_Id__c
            FROM PC1_Answer__c
            WHERE Application__c IN :appIds AND Field_Id__c IN :DEFAULTS.keySet()
        ]) {
            already.add(a.Application__c + '|' + a.Field_Id__c);
        }

        List<PC1_Answer__c> toInsert = new List<PC1_Answer__c>();
        for (Id appId : appIds) {
            for (String fieldId : DEFAULTS.keySet()) {
                if (already.contains(appId + '|' + fieldId)) continue;
                toInsert.add(new PC1_Answer__c(
                    Application__c = appId,
                    Field_Id__c    = fieldId,
                    Value__c       = DEFAULTS.get(fieldId),
                    Source__c      = 'default'
                ));
            }
        }
        if (!toInsert.isEmpty()) insert toInsert;
    }
}