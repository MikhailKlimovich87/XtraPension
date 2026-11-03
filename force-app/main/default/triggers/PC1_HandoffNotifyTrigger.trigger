/**
 * PC1_HandoffNotifyTrigger — after-insert on PC1_Handoff__c posts a Chatter
 * FeedItem on the parent Application so ops sees escalations in the
 * "Recent Activity" feed / bell notifications without extra tooling.
 *
 * Sibling to PC1_NeedsHumanNotifyTrigger which fires when the Application
 * transitions into Stage='Needs Human'. Kept in the trigger (not a Flow)
 * because Flow authorship via Metadata API is verbose and we already own
 * the trigger fleet on this object family.
 */
trigger PC1_HandoffNotifyTrigger on PC1_Handoff__c (before insert, after insert) {
    // PC1 is always GBP even though the org's corporate currency is EUR; pin it
    // before the row is written so UI-created handoffs don't land in euros.
    if (Trigger.isBefore) {
        PC1_CurrencyGuard.forceGbp(Trigger.new);
        return;
    }

    List<FeedItem> feed = new List<FeedItem>();
    for (PC1_Handoff__c h : Trigger.new) {
        if (h.Application__c == null) continue;
        String etype  = h.Escalation_Type__c != null ? h.Escalation_Type__c : 'unknown';
        String reason = h.Reason__c != null ? h.Reason__c : '(no reason)';
        FeedItem fi = new FeedItem(
            ParentId = h.Application__c,
            Body     = '[Escalated] ' + etype + ': ' + reason
        );
        feed.add(fi);
    }
    if (!feed.isEmpty()) {
        // allowFieldTruncation lets Chatter clip Body at 10k rather than error
        Database.DMLOptions opts = new Database.DMLOptions();
        opts.AllowFieldTruncation = true;
        Database.insert(feed, opts);
    }
}