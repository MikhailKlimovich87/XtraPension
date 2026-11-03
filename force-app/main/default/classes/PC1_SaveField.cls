/**
 * PC1_SaveField — Mary tool: persist a single Q&A pair for the current client.
 *
 * Payload:  { application_id, field_id, value, source?, confidence? }
 * Response: { status: "ok", answer_id, progress_filled, progress_total }
 */
@RestResource(urlMapping='/pc1/save-field')
global with sharing class PC1_SaveField {
    @HttpPost
    global static void doPost() {
        Map<String, Object> body = PC1_RestUtil.parseBody();
        PC1_Application__c app = PC1_RestUtil.findApplication(body);
        if (app == null) { PC1_RestUtil.writeError(404, 'Application not found'); return; }

        String fieldId = PC1_RestUtil.str(body, 'field_id');
        String value   = PC1_RestUtil.str(body, 'value');
        String source  = PC1_RestUtil.str(body, 'source');
        if (String.isBlank(source)) source = 'mary';
        Object conf = body.get('confidence');

        if (String.isBlank(fieldId)) { PC1_RestUtil.writeError(400, 'field_id is required'); return; }

        // Upsert by (Application, Field_Id): existing row → update Value/Source;
        // else create.
        List<PC1_Answer__c> existing = [SELECT Id FROM PC1_Answer__c WHERE Application__c = :app.Id AND Field_Id__c = :fieldId LIMIT 1];
        PC1_Answer__c ans;
        if (!existing.isEmpty()) {
            ans = existing[0];
            ans.Value__c = value;
            ans.Source__c = source;
            if (conf != null) ans.Confidence__c = Double.valueOf(conf);
            update ans;
        } else {
            ans = new PC1_Answer__c(
                Application__c = app.Id,
                Field_Id__c    = fieldId,
                Value__c       = value,
                Source__c      = source,
                Confidence__c  = (conf == null ? null : Double.valueOf(conf))
            );
            insert ans;
        }

        PC1_MaryProgressCalculator.updateMaryProgress(app.Id);
        PC1_Application__c fresh = [SELECT Progress_Filled__c, Progress_Total__c FROM PC1_Application__c WHERE Id = :app.Id LIMIT 1];

        PC1_RestUtil.writeJson(new Map<String, Object>{
            'status' => 'ok',
            'answer_id' => ans.Id,
            'progress_filled' => fresh.Progress_Filled__c,
            'progress_total'  => fresh.Progress_Total__c
        });
    }
}