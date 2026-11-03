/**
 * PC1_MarkComplete — Mary tool: mark all Mary-collectable fields collected,
 * move Application → Data Complete.
 * Payload: { application_id, note? }
 */
@RestResource(urlMapping='/pc1/mark-complete')
global with sharing class PC1_MarkComplete {
    @HttpPost
    global static void doPost() {
        Map<String, Object> body = PC1_RestUtil.parseBody();
        PC1_Application__c app = PC1_RestUtil.findApplication(body);
        if (app == null) { PC1_RestUtil.writeError(404, 'Application not found'); return; }

        PC1_Application__c u = new PC1_Application__c(
            Id = app.Id,
            Mary_Progress_Complete__c = true
        );
        // Move to Data Complete (or Partial Data → Data Complete depending on
        // current stage — trigger's state machine handles the specifics).
        if (app.Stage__c == 'Call In Progress' || app.Stage__c == 'Partial Data' || app.Stage__c == 'Awaiting First Call') {
            u.Stage__c = 'Data Complete';
        }
        update u;

        String note = PC1_RestUtil.str(body, 'note');
        if (!String.isBlank(note)) {
            PC1_Application__c withNotes = [SELECT Notes__c FROM PC1_Application__c WHERE Id = :app.Id LIMIT 1];
            String merged = (withNotes.Notes__c == null ? '' : withNotes.Notes__c + '\n\n') + '[' + Datetime.now().format() + ' Mary] ' + note;
            update new PC1_Application__c(Id = app.Id, Notes__c = merged);
        }
        PC1_RestUtil.writeJson(new Map<String, Object>{ 'status' => 'ok', 'application_id' => app.Id });
    }
}