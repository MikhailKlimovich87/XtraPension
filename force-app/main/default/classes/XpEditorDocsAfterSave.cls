/**
 * Called by the IPCBR1 and IPC1394 editors (screen flows) right after Save.
 *
 * Before the pack goes out for signature (Form completed to QC Approved) an edit regenerates the whole pack
 * (both forms, Client Summary, wet forms, DD mandate and the Stage 1 ZIP if it was not sent yet), so the client
 * never signs a Summary that disagrees with the forms. In any other status the editor regenerates only its own
 * form, as before; once signed, that also rebuilds the Stage 2 ZIP.
 */
public with sharing class XpEditorDocsAfterSave {

    public class Request {
        @InvocableVariable(required=true)
        public Id recordId;

        @InvocableVariable(required=true description='BR1 or IPC1394')
        public String form;
    }

    @InvocableMethod(label='Editor: regenerate documents after Save')
    public static void afterSave(List<Request> requests) {
        Set<Id> ids = new Set<Id>();
        for (Request request : requests) {
            ids.add(request.recordId);
        }
        Map<Id, Basic__c> claims = new Map<Id, Basic__c>([SELECT Id, Status__c FROM Basic__c WHERE Id IN :ids]);
        for (Request request : requests) {
            Basic__c claim = claims.get(request.recordId);
            if (claim != null && BasicTriggerHandler.PACK_EDIT_STATUSES.contains(claim.Status__c)
                && BasicTriggerHandler.queuePackRegeneration(claim.Id)) {
                continue;
            }
            if (request.form == 'IPC1394') {
                BP_GenerateApplication1394.getApplication_1394(request.recordId);
            } else {
                BP_GenerateApplication_BR1.getApplication_BR1(request.recordId);
            }
        }
    }
}