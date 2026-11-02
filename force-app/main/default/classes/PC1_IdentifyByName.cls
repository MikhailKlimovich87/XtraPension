/**
 * PC1_IdentifyByName — Mary tool: name-based fallback lookup when phone doesn't
 * match (unknown-caller flow, family member calling on behalf, etc).
 * Payload: { first_name, last_name?, dob? }
 */
@RestResource(urlMapping='/pc1/identify-by-name')
global with sharing class PC1_IdentifyByName {
    @HttpPost
    global static void doPost() {
        Map<String, Object> body = PC1_RestUtil.parseBody();
        String first = PC1_RestUtil.str(body, 'first_name');
        String last  = PC1_RestUtil.str(body, 'last_name');
        String dobStr= PC1_RestUtil.str(body, 'dob');
        if (String.isBlank(first)) { PC1_RestUtil.writeError(400, 'first_name is required'); return; }

        String soql = 'SELECT Id, Name, Full_Name__c, Stage__c, DOB__c FROM PC1_Application__c WHERE First_Name__c = :first';
        if (!String.isBlank(last)) soql += ' AND Last_Name__c = :last';
        if (!String.isBlank(dobStr)) {
            try {
                Date d = Date.valueOf(dobStr);
                soql += ' AND DOB__c = :d';
            } catch (Exception e) { /* ignore malformed DOB */ }
        }
        soql += ' LIMIT 5';

        List<PC1_Application__c> matches = Database.query(soql);
        if (matches.isEmpty()) { PC1_RestUtil.writeJson(new Map<String, Object>{ 'status' => 'not_found' }); return; }
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (PC1_Application__c a : matches) {
            out.add(new Map<String, Object>{
                'application_id' => a.Id, 'name' => a.Full_Name__c, 'stage' => a.Stage__c, 'dob' => a.DOB__c
            });
        }
        PC1_RestUtil.writeJson(new Map<String, Object>{ 'status' => 'ok', 'matches' => out });
    }
}