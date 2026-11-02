/**
 * PC1_FlagForHuman — Mary tool: create PC1_Handoff__c + move Application to
 * Needs Human.
 * Payload: { application_id, escalation_type, reason, last_field_id?,
 *            last_field_question?, client_verbatim?, attempted_value?,
 *            next_step_suggestion?, call_log_id? }
 */
@RestResource(urlMapping='/pc1/flag-for-human')
global with sharing class PC1_FlagForHuman {
    @HttpPost
    global static void doPost() {
        Map<String, Object> body = PC1_RestUtil.parseBody();
        PC1_Application__c app = PC1_RestUtil.findApplication(body);
        if (app == null) { PC1_RestUtil.writeError(404, 'Application not found'); return; }

        String escType = PC1_RestUtil.str(body, 'escalation_type');
        String reason  = PC1_RestUtil.str(body, 'reason');
        if (String.isBlank(escType)) escType = 'other';
        if (String.isBlank(reason))  reason  = 'unspecified';

        PC1_Handoff__c ho = new PC1_Handoff__c(
            Application__c        = app.Id,
            Escalation_Type__c    = escType,
            Reason__c             = reason,
            Last_Field_Id__c      = PC1_RestUtil.str(body, 'last_field_id'),
            Last_Field_Question__c= PC1_RestUtil.str(body, 'last_field_question'),
            Client_Verbatim__c    = PC1_RestUtil.str(body, 'client_verbatim'),
            Attempted_Value__c    = PC1_RestUtil.str(body, 'attempted_value'),
            Next_Step_Suggestion__c=PC1_RestUtil.str(body, 'next_step_suggestion'),
            Call_Log__c           = PC1_RestUtil.str(body, 'call_log_id'),
            Resolved__c           = false
        );
        insert ho;

        // Move Application → Needs Human (trigger blocks illegal transitions;
        // → Needs Human is universally allowed from any stage).
        try {
            update new PC1_Application__c(Id = app.Id, Stage__c = 'Needs Human');
        } catch (Exception e) {
            // If the stage machine rejects (shouldn't), log but keep the handoff.
        }

        PC1_RestUtil.writeJson(new Map<String, Object>{
            'status' => 'ok', 'handoff_id' => ho.Id, 'stage' => 'Needs Human'
        });
    }
}