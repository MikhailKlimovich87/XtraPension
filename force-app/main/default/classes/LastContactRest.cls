/**
 * WhatsApp messages a person sent outside Salesforce (the Timelines inbox or its Chrome extension), reported by
 * the whatsapp-to-last-contact flow on the automations server. The four fields are read-only for everyone, so
 * the flow comes through here and LastContactService saves them in system mode, like calls and emails.
 *
 * POST /services/apexrest/xp/last-contact/whatsapp
 *   { "items": [ { "recordId": "...", "person": "Monica XtraPension", "sentAt": "2026-10-30T10:00:00Z" } ] }
 */
@RestResource(urlMapping='/xp/last-contact/whatsapp')
global without sharing class LastContactRest {

    global class Item {
        global Id recordId;
        global String person;
        global Datetime sentAt;
    }

    global class Answer {
        global Integer applied;
        global Integer older;
        global Integer failed;
    }

    @HttpPost
    global static Answer report(List<Item> items) {
        List<LastContactService.ContactEvent> events = new List<LastContactService.ContactEvent>();
        if (items != null) {
            for (Item i : items) {
                events.add(new LastContactService.ContactEvent(i.recordId, LastContactService.WAPP_SENT, i.person, i.sentAt));
            }
        }
        LastContactService.Result r = LastContactService.apply(events);
        Answer a = new Answer();
        a.applied = r.applied;
        a.older = r.older;
        a.failed = r.considered - r.applied - r.older;
        return a;
    }
}