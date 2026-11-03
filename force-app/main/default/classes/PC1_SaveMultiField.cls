/**
 * PC1_SaveMultiField — Mary tool: save many field/value pairs in one call.
 * Payload: { application_id, answers: [ {field_id, value, source?, confidence?} ] }
 */
@RestResource(urlMapping='/pc1/save-multi-field')
global with sharing class PC1_SaveMultiField {
    @HttpPost
    global static void doPost() {
        Map<String, Object> body = PC1_RestUtil.parseBody();
        PC1_Application__c app = PC1_RestUtil.findApplication(body);
        if (app == null) { PC1_RestUtil.writeError(404, 'Application not found'); return; }

        List<Object> answersRaw = (List<Object>) body.get('answers');
        if (answersRaw == null) { PC1_RestUtil.writeError(400, 'answers array is required'); return; }

        // Preload existing for upsert-by-Field_Id semantics
        Set<String> fieldIds = new Set<String>();
        for (Object o : answersRaw) fieldIds.add(String.valueOf(((Map<String, Object>) o).get('field_id')));
        Map<String, PC1_Answer__c> existing = new Map<String, PC1_Answer__c>();
        for (PC1_Answer__c a : [SELECT Id, Field_Id__c FROM PC1_Answer__c WHERE Application__c = :app.Id AND Field_Id__c IN :fieldIds]) {
            existing.put(a.Field_Id__c, a);
        }

        List<PC1_Answer__c> toInsert = new List<PC1_Answer__c>();
        List<PC1_Answer__c> toUpdate = new List<PC1_Answer__c>();
        for (Object o : answersRaw) {
            Map<String, Object> row = (Map<String, Object>) o;
            String fid = String.valueOf(row.get('field_id'));
            String val = row.get('value') == null ? null : String.valueOf(row.get('value'));
            String src = row.get('source') == null ? 'mary' : String.valueOf(row.get('source'));
            Object conf = row.get('confidence');
            if (existing.containsKey(fid)) {
                PC1_Answer__c a = existing.get(fid);
                a.Value__c = val; a.Source__c = src;
                if (conf != null) a.Confidence__c = Double.valueOf(conf);
                toUpdate.add(a);
            } else {
                toInsert.add(new PC1_Answer__c(Application__c = app.Id, Field_Id__c = fid, Value__c = val, Source__c = src, Confidence__c = (conf == null ? null : Double.valueOf(conf))));
            }
        }
        if (!toInsert.isEmpty()) insert toInsert;
        if (!toUpdate.isEmpty()) update toUpdate;

        PC1_MaryProgressCalculator.updateMaryProgress(app.Id);
        PC1_Application__c fresh = [SELECT Progress_Filled__c, Progress_Total__c FROM PC1_Application__c WHERE Id = :app.Id LIMIT 1];

        PC1_RestUtil.writeJson(new Map<String, Object>{
            'status' => 'ok',
            'saved' => toInsert.size() + toUpdate.size(),
            'progress_filled' => fresh.Progress_Filled__c,
            'progress_total'  => fresh.Progress_Total__c
        });
    }
}