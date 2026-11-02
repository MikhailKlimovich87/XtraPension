public class GoCardlessWebhookQueueable implements Queueable {
    private List<GoCardless_Webhook_Event__c> events;

    public GoCardlessWebhookQueueable(List<GoCardless_Webhook_Event__c> events) {
        this.events = events;
    }

    public void execute(QueueableContext ctx) {
        List<Object> rawEvents = new List<Object>();

        for (GoCardless_Webhook_Event__c evt : events) {
            try {
                if (String.isBlank(evt.Payload__c)) {
                    evt.Processed__c = true;
                    continue;
                }

                Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(evt.Payload__c);
                rawEvents.add(payload);
                evt.Processed__c = true;
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Failed to process event: ' + evt.Event_Id__c + ' | ' + e.getMessage());
                evt.Processed__c = true;
            }
        }
        System.debug(rawEvents.size() + ' GoCardless webhook events to process.');
        if (!rawEvents.isEmpty()) {
            GoCardlessWebhookProcessor.process(rawEvents);
        }

        if (!events.isEmpty()) {
            update events;
        }
    }
}