/**
 * AA_ApplicationTrigger — three responsibilities:
 *   1. before insert/update: normalise phone, pin CurrencyIsoCode='GBP'
 *      (insert only), assign val agent, validate Stage state-machine +
 *      stamp Stage_Changed_At.
 *   2. after insert:  seed the 4 AA DEFAULT_ANSWERS (Hostinger parity — every
 *                     new Application starts with welsh-language-speak=english,
 *                     welsh-language-write=english, alternative-formats=
 *                     ["format-none"], email-submit=yes so Mary never has to ask
 *                     policy defaults) + stamp signature. See
 *                     AA_DefaultAnswersHelper for why the PC1 defaults
 *                     (q_language / q_formats / q_email_correct /
 *                     q0_backdate_accept) were dropped — AA has no backdate and
 *                     the other ids don't exist in the DWP AA form.
 *   3. after update:  fire the Intake_Created welcome message pack (Welcome
 *                     email + Service Agreement PDF + SMS) the moment the
 *                     GoCardless mandate is created — i.e. DD_Mandate_Id__c
 *                     transitions null → non-null. This shifts the trigger
 *                     point from the old "insert" location so the welcome
 *                     email can reference the live mandate details in-body,
 *                     giving the client a full paper trail in one message.
 *                     If the mandate is never created (bank verify never
 *                     passes, DD terms never read, or the callout fails)
 *                     the welcome will NOT fire — val team follows up
 *                     manually via the DD_Mandate_Failure_Reason__c field.
 *                     Also cancels Pending AA_Call_Schedule__c rows when the
 *                     app leaves the dialable stages or turns Do Not Contact
 *                     (AA_StageTransitionHelper.cancelPendingSchedulesOnExit).
 *                     And books Mary's first call (next UK business day,
 *                     10:00, async) when a bank-deferred app moves from
 *                     Awaiting Bank Details to a first-call stage
 *                     (AA_StageTransitionHelper.bookFirstCallAfterBankDetails).
 *
 * Real logic lives in helpers (StageTransitionHelper + DefaultAnswersHelper)
 * so both are unit-testable without DML noise here.
 */
trigger AA_ApplicationTrigger on AA_Application__c (before insert, before update, after insert, after update) {
    if (Trigger.isBefore) {
        // Normalise Phone__c to E.164 on every write so caller-id lookups are
        // one exact SOQL match (Hostinger POC parity — see docs/DWP-VALIDATION-QUIRKS.md).
        AA_PhoneNormalizer.normalize(Trigger.new);
    }
    if (Trigger.isBefore && Trigger.isInsert) {
        // AA is a UK product in an org whose corporate currency is EUR. Records
        // created in the UI inherit the running user's currency (val team = EUR,
        // locale en_IE), which renders Award/Fee amounts as euros. Pin GBP here so
        // it holds for UI, API, Data Loader and any future insert path alike.
        AA_CurrencyGuard.forceGbp(Trigger.new);
    }
    if (Trigger.isBefore && Trigger.isInsert) {
        // Weighted round-robin: fills Val_Agent__c on new rows using active
        // agents + weights from AA_Val_Agent__c. Skips rows that already have
        // a value set (imports, manual overrides, admin re-assigns).
        AA_ValAgentAssignHelper.assign(Trigger.new);
    }
    if (Trigger.isBefore && Trigger.isUpdate) {
        AA_StageTransitionHelper.handleTransitions(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isAfter && Trigger.isInsert) {
        AA_DefaultAnswersHelper.seedDefaults(Trigger.new);
        // Populate Signature__c so Client_Form_URL__c formula bakes in ?t=<sig>.
        // Idempotent — AA_UrlSigner.stampSignatures skips rows already stamped.
        AA_UrlSigner.stampSignatures(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        // Cancel Pending call slots once the app leaves the dialable stages or
        // is marked Do Not Contact (audit 2026-10-02 F84), so no reminder SMS,
        // stale Next_Call_At__c or phantom miss follows a slot that is never
        // dialled.
        AA_StageTransitionHelper.cancelPendingSchedulesOnExit(Trigger.new, Trigger.oldMap);

        // Owner decision 2026-10-02: once a bank-deferred application moves
        // to Awaiting First Call (bank details in), book Mary's first call for
        // the next UK business day at 10:00 (async, bulk-safe).
        AA_StageTransitionHelper.bookFirstCallAfterBankDetails(Trigger.new, Trigger.oldMap);

        // Welcome message pack (Email + SMS as configured on active
        // AA_Message_Template__c rows with Trigger_Event__c = Intake_Created)
        // now fires when the Direct Debit mandate lands, NOT on intake insert.
        // Gate:
        //   - DD_Mandate_Id__c populated NOW (mandate created OK).
        //   - Was null BEFORE (fires exactly once — never on subsequent saves
        //     of an already-mandated record).
        //   - First name + email present (mail needs somewhere to go — same
        //     safety belt as the old intake gate).
        // Batched into one Queueable per trigger fire (governor-safe on bulk).
        Set<Id> ready = new Set<Id>();
        for (AA_Application__c a : Trigger.new) {
            AA_Application__c prev = Trigger.oldMap.get(a.Id);
            Boolean mandateJustCreated = String.isNotBlank(a.DD_Mandate_Id__c)
                && (prev == null || String.isBlank(prev.DD_Mandate_Id__c));
            if (!mandateJustCreated) continue;
            if (String.isBlank(a.First_Name__c) || String.isBlank(a.Email__c)) continue;
            ready.add(a.Id);
        }
        if (!ready.isEmpty()) {
            AA_MessageDispatcher.dispatch(ready, 'Intake_Created');
        }
    }
}