/**
 * Processes GoCardless webhook events.
 * Runs as the Site Guest User when invoked from the REST webhook handler.
 * Marked `without sharing` because the Guest User typically cannot update
 * Basic__c / Basic_Payment__c records directly. Security is enforced at the
 * webhook handler (signature verification) not here.
 */
public without sharing class GoCardlessWebhookProcessor {

    private static final Map<String, Integer> STATUS_RANK = new Map<String, Integer>{
        'Schedule'     => 1,
        'Submitted'    => 2,
        'Confirmed'    => 3,
        'Paid'         => 4,
        'Fail'         => 5,
        'Cancel'       => 5,
        'Refund'       => 5
    };

    public static void process(List<Object> rawEvents) {
        if (rawEvents == null || rawEvents.isEmpty()) {
            return;
        }

        System.debug(LoggingLevel.INFO, 'Processing ' + rawEvents.size() + ' GoCardless webhook events.');

        // ---------- 1. Parse events (no SOQL/DML) ----------
        List<GoCardlessEvent> events = new List<GoCardlessEvent>();
        Set<String> paymentIds = new Set<String>();
        Set<String> mandateIds = new Set<String>();

        for (Object raw : rawEvents) {
            if (!(raw instanceof Map<String, Object>)) continue;
            Map<String, Object> evt = (Map<String, Object>) raw;

            GoCardlessEvent e = new GoCardlessEvent();
            e.id           = (String) evt.get('id');
            e.resourceType = (String) evt.get('resource_type');
            e.action       = (String) evt.get('action');
            e.createdAt    = (String) evt.get('created_at');

            Object linksObj = evt.get('links');
            if (linksObj instanceof Map<String, Object>) {
                Map<String, Object> links = (Map<String, Object>) linksObj;
                e.paymentId = (String) links.get('payment');
                e.mandateId = (String) links.get('mandate');
            }

            events.add(e);

            if (String.isNotBlank(e.paymentId)) paymentIds.add(e.paymentId);
            if (String.isNotBlank(e.mandateId)) mandateIds.add(e.mandateId);
        }

        // ---------- 2. Bulk queries ----------
        Map<String, Basic_Payment__c> paymentsByGcId = new Map<String, Basic_Payment__c>();
        if (!paymentIds.isEmpty()) {
            for (Basic_Payment__c p : [
                SELECT Id, GoCardless_Payment_Id__c, Status__c
                FROM Basic_Payment__c
                WHERE GoCardless_Payment_Id__c IN :paymentIds
            ]) {
                paymentsByGcId.put(p.GoCardless_Payment_Id__c, p);
            }
        }

        Map<String, Basic__c> claimsByMandateId = new Map<String, Basic__c>();
        if (!mandateIds.isEmpty()) {
            for (Basic__c c : [
                SELECT Id, GoCardless_Mandate_Id__c
                FROM Basic__c
                WHERE GoCardless_Mandate_Id__c IN :mandateIds
            ]) {
                claimsByMandateId.put(c.GoCardless_Mandate_Id__c, c);
            }
        }

        // ---------- 3. Build DML collections (no DML in loop) ----------
        List<Basic_Payment__c> paymentsToUpdate = new List<Basic_Payment__c>();

        for (GoCardlessEvent e : events) {
            if (e.resourceType == 'payments' && String.isNotBlank(e.paymentId)) {
                Basic_Payment__c p = paymentsByGcId.get(e.paymentId);
                if (p == null) {
                    System.debug(LoggingLevel.WARN,
                        'No Basic_Payment__c for GoCardless payment ' + e.paymentId);
                    continue;
                }

                String newStatus = mapActionToStatus(e.action);
                if (String.isBlank(newStatus)) continue;

                Integer currentRank = STATUS_RANK.get(p.Status__c);
                Integer newRank     = STATUS_RANK.get(newStatus);

                if (newRank != null &&
                    (currentRank == null || newRank > currentRank)) {
                    p.Status__c = newStatus;
                    paymentsToUpdate.add(p);
                }
            }
        }
        System.debug(LoggingLevel.INFO, 'Updating ' + paymentsToUpdate.size() + ' Basic_Payment__c records based on GoCardless webhook events.');
        // ---------- 4. Single DML ----------
        if (!paymentsToUpdate.isEmpty()) {
            Database.update(paymentsToUpdate, false);
        }
    }
    
    private static String mapActionToStatus(String action) {
        if (action == null)              return null;
        if (action == 'created')         return 'Schedule';
        if (action == 'submitted')       return 'Submitted';
        if (action == 'confirmed')       return 'Confirmed';
        if (action == 'paid_out')        return 'Paid';
        if (action == 'failed')          return 'Fail';
        if (action == 'cancelled')       return 'Cancel';
        if (action == 'charged_back')    return 'Refund';
        return null;
    }

    public class GoCardlessEvent {
        public String id;
        public String resourceType;
        public String action;
        public String createdAt;
        public String paymentId;
        public String mandateId;
    }
}