/**
 * PC1_VerifyClient — Mary tool: KBA-style verification for unknown callers.
 * Checks that a claimed dob/postcode combo matches the application on file.
 * Payload: { application_id, dob?, postcode?, last_name? }
 * Response: { status: "verified" | "mismatch" | "insufficient" }
 */
@RestResource(urlMapping='/pc1/verify-client')
global with sharing class PC1_VerifyClient {
    @HttpPost
    global static void doPost() {
        Map<String, Object> body = PC1_RestUtil.parseBody();
        PC1_Application__c app = PC1_RestUtil.findApplication(body);
        if (app == null) { PC1_RestUtil.writeError(404, 'Application not found'); return; }

        PC1_Application__c full = [SELECT DOB__c, Postcode__c, Last_Name__c FROM PC1_Application__c WHERE Id = :app.Id LIMIT 1];
        Integer checks = 0, hits = 0;
        String dob = PC1_RestUtil.str(body, 'dob');
        String pc  = PC1_RestUtil.str(body, 'postcode');
        String ln  = PC1_RestUtil.str(body, 'last_name');
        if (!String.isBlank(dob)) {
            checks++;
            try { if (Date.valueOf(dob) == full.DOB__c) hits++; } catch (Exception e) { /* ignore */ }
        }
        if (!String.isBlank(pc)) {
            checks++;
            if (full.Postcode__c != null && pc.toUpperCase().replaceAll('\\s+','') == full.Postcode__c.toUpperCase().replaceAll('\\s+','')) hits++;
        }
        if (!String.isBlank(ln)) {
            checks++;
            if (full.Last_Name__c != null && ln.equalsIgnoreCase(full.Last_Name__c)) hits++;
        }

        if (checks < 2) { PC1_RestUtil.writeJson(new Map<String, Object>{ 'status' => 'insufficient', 'need' => 'at least 2 of: dob, postcode, last_name' }); return; }
        PC1_RestUtil.writeJson(new Map<String, Object>{ 'status' => (hits == checks ? 'verified' : 'mismatch'), 'checks' => checks, 'hits' => hits });
    }
}