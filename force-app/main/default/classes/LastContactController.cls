/**
 * The WhatsApp panels on the Application and the Claim call this once a message is out: Contact = Wapp Sent,
 * Last Contact = whoever pressed Send, date = now. The four fields are read-only for everyone, admins included;
 * the save goes through LastContactService in system mode.
 */
public with sharing class LastContactController {

    /** The message has gone: a problem here is logged and never looks like a failed send. */
    public static void whatsAppSent(Id recordId) {
        LastContactService.ContactEvent e = new LastContactService.ContactEvent(
            recordId, LastContactService.WAPP_SENT, UserInfo.getName(), Datetime.now());
        e.manual = true;
        LastContactService.Result r = LastContactService.apply(new List<LastContactService.ContactEvent>{ e });
        if (!r.failures.isEmpty()) {
            System.debug(LoggingLevel.WARN, '[LastContact] WhatsApp sent on ' + recordId + ' not logged: ' + r.failures.get(recordId));
        }
    }
}