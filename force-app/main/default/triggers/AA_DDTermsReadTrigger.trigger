/**
 * AA_DDTermsReadTrigger — audit-stamps DD_Terms_Read_At__c / DD_Terms_Read_By__c
 * whenever DD_Terms_Read_By_Sales__c flips. Same shape as the retired
 * AA_AccountHolderVerbalConfirmTrigger (before-update stamp on toggle),
 * scoped to the GoCardless paperless Direct Debit intake step so we can
 * later prove which agent read the DD Guarantee to the client and when.
 *
 * On flip false → true : stamp Datetime.now() + UserInfo.getUserId().
 * On flip true  → false : null both stamps.
 * Same-value updates are ignored (no unnecessary field churn).
 *
 * Before-update so the stamps land in the same DML as the checkbox — no
 * recursion, no second SOQL, no async race with downstream automations
 * that read the trail.
 */
trigger AA_DDTermsReadTrigger on AA_Application__c (before insert, before update) {
    Datetime now = Datetime.now();
    Id userId = UserInfo.getUserId();

    for (AA_Application__c app : Trigger.new) {
        Boolean nowRead  = app.DD_Terms_Read_By_Sales__c == true;
        // On INSERT the previous state is "not read". Intake now writes
        // DD_Terms_Read_By_Sales__c=true directly on insert (the DD auth
        // tick section on the intake form) — this branch stamps the audit
        // fields in the SAME DML so DD_Terms_Read_At__c isn't null when
        // downstream automations look it up.
        Boolean prevRead;
        if (Trigger.isInsert) {
            prevRead = false;
        } else {
            AA_Application__c prev = Trigger.oldMap.get(app.Id);
            prevRead = prev.DD_Terms_Read_By_Sales__c == true;
        }
        if (nowRead == prevRead) continue; // no flip → no stamp

        if (nowRead) {
            app.DD_Terms_Read_At__c = now;
            // audit 2026-10-02 F118: intake writes through the single Heroku
            // integration user, so UserInfo names that user, not the agent who
            // read the Direct Debit terms. When the caller sets
            // DD_Terms_Read_By__c in the same DML (e.g. intake mapping the
            // signed-in agent to their User), keep it; otherwise stamp the
            // current user as before.
            Id supplied = app.DD_Terms_Read_By__c;
            Id prior = Trigger.isInsert ? null : Trigger.oldMap.get(app.Id).DD_Terms_Read_By__c;
            if (supplied == null || supplied == prior) {
                app.DD_Terms_Read_By__c = userId;
            }
        } else {
            app.DD_Terms_Read_At__c = null;
            app.DD_Terms_Read_By__c = null;
        }
    }
}