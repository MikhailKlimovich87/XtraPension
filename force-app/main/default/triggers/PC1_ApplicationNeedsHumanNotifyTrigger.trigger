/**
 * PC1_ApplicationNeedsHumanNotifyTrigger — after-update companion to
 * PC1_HandoffNotifyTrigger. Fires a Chatter FeedItem on the Application when
 * Stage__c transitions INTO 'Needs Human' from anything else — belt-and-
 * suspenders coverage for the Ops queue in case a caller flips Stage without
 * inserting a Handoff row (rare, but observed in phone-call fallbacks).
 *
 * Kept out of PC1_ApplicationTrigger to preserve that trigger's single
 * responsibility (state-machine + defaults + phone normalisation).
 */
trigger PC1_ApplicationNeedsHumanNotifyTrigger on PC1_Application__c (after update) {
    Set<Id> transitioned = new Set<Id>();
    for (PC1_Application__c app : Trigger.new) {
        PC1_Application__c prev = Trigger.oldMap.get(app.Id);
        if (app.Stage__c == 'Needs Human' && prev.Stage__c != 'Needs Human') {
            transitioned.add(app.Id);
        }
    }
    if (transitioned.isEmpty()) return;

    // Dedup guard (re-audit F3): the flag_for_human flow inserts a
    // PC1_Handoff__c (PC1_HandoffNotifyTrigger posts "[Escalated] ...")
    // and then flips Stage to Needs Human moments later — before this guard
    // ops got TWO FeedItems for the same escalation. If a Handoff for this
    // Application was created in the last 2 minutes, the Handoff FeedItem
    // already covers it; skip ours. Stage flips WITHOUT a recent Handoff
    // (manual operator move, legacy fallbacks) still notify.
    Datetime cutoff = System.now().addSeconds(-120);
    Set<Id> recentlyEscalated = new Set<Id>();
    for (PC1_Handoff__c h : [
        SELECT Application__c FROM PC1_Handoff__c
        WHERE Application__c IN :transitioned AND CreatedDate >= :cutoff
    ]) {
        recentlyEscalated.add(h.Application__c);
    }

    List<FeedItem> feed = new List<FeedItem>();
    for (Id appId : transitioned) {
        if (recentlyEscalated.contains(appId)) continue;
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
}