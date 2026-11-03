/**
 * PC1_CheckCurrentAnswers — Mary tool: get everything we already know about
 * this client so Mary can decide what to ask next.
 * Payload: { application_id | dwp_reference | phone }
 * Response: { status, client_summary, progress: {...}, answers: {...},
 *             missing_fields: [...] }
 */
@RestResource(urlMapping='/pc1/check-current-answers')
global with sharing class PC1_CheckCurrentAnswers {
    @HttpPost
    global static void doPost() {
        Map<String, Object> body = PC1_RestUtil.parseBody();
        PC1_Application__c app = PC1_RestUtil.findApplication(body);
        if (app == null) { PC1_RestUtil.writeError(404, 'Application not found'); return; }

        // Full record + related
        PC1_Application__c full = [
            SELECT Id, Name, First_Name__c, Last_Name__c, Full_Name__c, Email__c, Phone__c,
                   DOB__c, Address_Line1__c, City__c, Postcode__c, Notes__c, Stage__c,
                   Next_Call_At__c, Progress_Filled__c, Progress_Total__c, Progress_Percent__c,
                   Mary_Progress_Filled__c, Mary_Progress_Total__c
            FROM PC1_Application__c WHERE Id = :app.Id LIMIT 1
        ];
        Map<String, String> answers = new Map<String, String>();
        for (PC1_Answer__c a : [SELECT Field_Id__c, Value__c FROM PC1_Answer__c WHERE Application__c = :app.Id ORDER BY Field_Id__c]) {
            answers.put(a.Field_Id__c, a.Value__c);
        }

        // Minimal missing-fields heuristic: everything in a reference list not
        // already in answers. In production the Heroku worker will use the
        // real form snapshot — this is a mock for POC use.
        List<String> canonicalFields = new List<String>{
            'q_first_name', 'q_last_name', 'q_dob', 'q_address_line1', 'q_postcode',
            'q_ni_number', 'q_bank_name', 'q_bank_account', 'q_bank_sort_code',
            'q_partner', 'q_children', 'q_income_employment', 'q_income_pension',
            'q_income_benefits', 'q_savings_amount'
        };
        List<String> missing = new List<String>();
        for (String f : canonicalFields) if (!answers.containsKey(f)) missing.add(f);

        PC1_RestUtil.writeJson(new Map<String, Object>{
            'status' => 'ok',
            'client_summary' => new Map<String, Object>{
                'application_id' => full.Id,
                'name' => full.Full_Name__c,
                'stage' => full.Stage__c,
                'phone' => full.Phone__c,
                'notes' => full.Notes__c
            },
            'progress' => new Map<String, Object>{
                'filled' => full.Progress_Filled__c,
                'total'  => full.Progress_Total__c,
                'percent'=> full.Progress_Percent__c
            },
            'answers' => answers,
            'missing_fields' => missing
        });
    }
}