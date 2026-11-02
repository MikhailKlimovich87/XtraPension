/**
 * PC1_IdentifyByCallerPhone — Mary tool: look up an Application by inbound
 * caller phone (E.164). Returns match or "not_found".
 * Payload: { phone }
 */
@RestResource(urlMapping='/pc1/identify-by-caller-phone')
global with sharing class PC1_IdentifyByCallerPhone {
    @HttpPost
    global static void doPost() {
        Map<String, Object> body = PC1_RestUtil.parseBody();
        String phone = PC1_RestUtil.str(body, 'phone');
        if (String.isBlank(phone)) { PC1_RestUtil.writeError(400, 'phone is required'); return; }

        List<PC1_Application__c> matches = [
            SELECT Id, Name, Full_Name__c, Stage__c FROM PC1_Application__c
            WHERE Phone__c = :phone LIMIT 5
        ];
        if (matches.isEmpty()) {
            PC1_RestUtil.writeJson(new Map<String, Object>{ 'status' => 'not_found' });
            return;
        }
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (PC1_Application__c a : matches) {
            out.add(new Map<String, Object>{
                'application_id' => a.Id, 'name' => a.Full_Name__c, 'stage' => a.Stage__c
            });
        }
        PC1_RestUtil.writeJson(new Map<String, Object>{ 'status' => 'ok', 'matches' => out });
    }
}