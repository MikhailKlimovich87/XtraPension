/**
 * AA_ApplicationNeedsHumanNotifyTrigger — after-update companion to
 * AA_HandoffNotifyTrigger. Fires a Chatter FeedItem on the Application when
 * Stage__c transitions INTO 'Needs Human' from anything else — belt-and-
 * suspenders coverage for the Ops queue in case a caller flips Stage without
 * inserting a Handoff row (rare, but observed in phone-call fallbacks).
 *
 * Kept out of AA_ApplicationTrigger to preserve that trigger's single
 * responsibility (state-machine + defaults + phone normalisation).
 *
 * Also the after-update hook for the DWP decision messages (owner decision
 * 2026-10-02): Stage__c moving into 'Awarded' / 'Closed - Refused' sends
 * Application_Approved_by_DWP / Application_Rejected_by_DWP through
 * AA_MessageDispatcher.dispatchStageOutcomes (once per application; Do Not
 * Contact, SMS opt-out and the stage gates apply). It lives here because this
 * is the comms-owned stage-change trigger; it runs before the Needs Human
 * logic below, which returns early.
 */
trigger AA_ApplicationNeedsHumanNotifyTrigger on AA_Application__c (after update) {
    AA_MessageDispatcher.dispatchStageOutcomes(Trigger.new, Trigger.oldMap);

    Set<Id> transitioned = new Set<Id>();
    for (AA_Application__c app : Trigger.new) {
        AA_Application__c prev = Trigger.oldMap.get(app.Id);
        if (app.Stage__c == 'Needs Human' && prev.Stage__c != 'Needs Human') {
            transitioned.add(app.Id);
        }
    }
    if (transitioned.isEmpty()) return;

    // Dedup guard (re-audit F3): the flag_for_human flow inserts a
    // AA_Handoff__c (AA_HandoffNotifyTrigger posts "[Escalated] ...")
    // and then flips Stage to Needs Human moments later — before this guard
    // ops got TWO FeedItems for the same escalation. If a Handoff for this
    // Application was created in the last 2 minutes, the Handoff FeedItem
    // already covers it; skip ours. Stage flips WITHOUT a recent Handoff
    // (manual operator move, legacy fallbacks) still notify.
    Datetime cutoff = System.now().addSeconds(-120);
    Set<Id> recentlyEscalated = new Set<Id>();
    for (AA_Handoff__c h : [
        SELECT Application__c FROM AA_Handoff__c
        WHERE Application__c IN :transitioned AND CreatedDate >= :cutoff
    ]) {
        recentlyEscalated.add(h.Application__c);
    }

    List<FeedItem> feed = new List<FeedItem>();
    Set<Id> notify = new Set<Id>();
    for (Id appId : transitioned) {
        if (recentlyEscalated.contains(appId)) continue;
        notify.add(appId);
        feed.add(new FeedItem(
            ParentId = appId,
            Body     = '[Needs Human] Application flagged Needs Human - see latest Handoff for details.'
        ));
    }
    if (!feed.isEmpty()) {
        Database.DMLOptions opts = new Database.DMLOptions();
        opts.AllowFieldTruncation = true;
        Database.insert(feed, opts);
    }
    // Same reach problem as the handoff FeedItem (audit 2026-10-02 F75): also
    // email ops. Apps with a fresh handoff were already emailed by
    // AA_HandoffNotifyTrigger, so only the uncovered ones go here.
    AA_HandoffService.notifyNeedsHuman(notify);
}