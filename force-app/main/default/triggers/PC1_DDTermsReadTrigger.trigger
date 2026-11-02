/**
 * PC1_DDTermsReadTrigger — audit-stamps DD_Terms_Read_At__c / DD_Terms_Read_By__c
 * whenever DD_Terms_Read_By_Sales__c flips. Same shape as the retired
 * PC1_AccountHolderVerbalConfirmTrigger (before-update stamp on toggle),
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
trigger PC1_DDTermsReadTrigger on PC1_Application__c (before insert, before update) {
    Datetime now = Datetime.now();
    Id userId = UserInfo.getUserId();

    for (PC1_Application__c app : Trigger.new) {
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
            PC1_Application__c prev = Trigger.oldMap.get(app.Id);
            prevRead = prev.DD_Terms_Read_By_Sales__c == true;
        }
        if (nowRead == prevRead) continue; // no flip → no stamp

        if (nowRead) {
            app.DD_Terms_Read_At__c = now;
            app.DD_Terms_Read_By__c = userId;
        } else {
            app.DD_Terms_Read_At__c = null;
            app.DD_Terms_Read_By__c = null;
        }
    }
}