/**
 * PC1_ApplicationTrigger — three responsibilities:
 *   1. before insert/update: normalise phone, assign val agent, validate
 *      Stage state-machine + stamp Stage_Changed_At.
 *   2. after insert:  seed 4 DEFAULT_ANSWERS (Hostinger parity — every new
 *                     Application starts with q_language=english, q_formats=no,
 *                     q_email_correct=yes, q0_backdate_accept=yes so Mary
 *                     never has to ask policy defaults) + stamp signature.
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
 *
 * Real logic lives in helpers (StageTransitionHelper + DefaultAnswersHelper)
 * so both are unit-testable without DML noise here.
 */
trigger PC1_ApplicationTrigger on PC1_Application__c (before insert, before update, after insert, after update) {
    if (Trigger.isBefore) {
        // Normalise Phone__c to E.164 on every write so caller-id lookups are
        // one exact SOQL match (Hostinger POC parity — see docs/DWP-VALIDATION-QUIRKS.md).
        PC1_PhoneNormalizer.normalize(Trigger.new);
    }
    if (Trigger.isBefore && Trigger.isInsert) {
        // PC1 is a UK product in an org whose corporate currency is EUR. Records
        // created in the UI inherit the running user's currency (val team = EUR,
        // locale en_IE), which renders Award/Fee amounts as euros. Pin GBP here so
        // it holds for UI, API, Data Loader and any future insert path alike.
        PC1_CurrencyGuard.forceGbp(Trigger.new);
    }
    if (Trigger.isBefore && Trigger.isInsert) {
        // Weighted round-robin: fills Val_Agent__c on new rows using active
        // agents + weights from PC1_Val_Agent__c. Skips rows that already have
        // a value set (imports, manual overrides, admin re-assigns).
        PC1_ValAgentAssignHelper.assign(Trigger.new);
    }
    if (Trigger.isBefore && Trigger.isUpdate) {
        PC1_StageTransitionHelper.handleTransitions(Trigger.new, Trigger.oldMap);
        // Bank digits edited on the record: reset trust + park the mandate.
        PC1_ApplicationFieldSync.onParentBankChange(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isAfter && Trigger.isInsert) {
        PC1_DefaultAnswersHelper.seedDefaults(Trigger.new);
        // Populate Signature__c so Client_Form_URL__c formula bakes in ?t=<sig>.
        // Idempotent — PC1_UrlSigner.stampSignatures skips rows already stamped.
        PC1_UrlSigner.stampSignatures(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        // Record-page edits of name/address/bank → answers the DWP fill reads.
        PC1_ApplicationFieldSync.mirrorParentToAnswers(Trigger.new, Trigger.oldMap);
        // Welcome message pack (Email + SMS as configured on active
        // PC1_Message_Template__c rows with Trigger_Event__c = Intake_Created)
        // now fires when the Direct Debit mandate lands, NOT on intake insert.
        // Gate:
        //   - DD_Mandate_Id__c populated NOW (mandate created OK).
        //   - Was null BEFORE (fires exactly once — never on subsequent saves
        //     of an already-mandated record).
        //   - First name + email present (mail needs somewhere to go — same
        //     safety belt as the old intake gate).
        // Batched into one Queueable per trigger fire (governor-safe on bulk).
        Set<Id> ready = new Set<Id>();
        for (PC1_Application__c a : Trigger.new) {
            PC1_Application__c prev = Trigger.oldMap.get(a.Id);
            Boolean mandateJustCreated = String.isNotBlank(a.DD_Mandate_Id__c)
                && (prev == null || String.isBlank(prev.DD_Mandate_Id__c));
            if (!mandateJustCreated) continue;
            if (String.isBlank(a.First_Name__c) || String.isBlank(a.Email__c)) continue;
            ready.add(a.Id);
        }
        if (!ready.isEmpty()) {
            PC1_MessageDispatcher.dispatch(ready, 'Intake_Created');
        }
    }
}