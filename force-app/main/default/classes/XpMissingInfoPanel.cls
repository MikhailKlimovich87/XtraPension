/**
 * Entrada única do painel Missing Information (xpMissingInfo), no Application e no Claim.
 * Escolhe a classe pelo tipo do Id, como o XpCallHistoryController:
 *  - Application__c -> XpMissingInfo, sem mudança (o force é ignorado: o Sales não grava nada);
 *  - Basic__c       -> BP_MissingInfo (o force regrava Missing_Info__c, o antigo "Check Missing").
 * leaveOut: as linhas do agente que ele desmarcou no preview (call de 11/11/2026); null não tira nada.
 * O permission set XP_Missing_Info_Sales dá acesso a esta classe para o time todo.
 */
public with sharing class XpMissingInfoPanel {

    @AuraEnabled
    public static Map<String, Object> refresh(Id recordId, Boolean force) {
        return isClaim(recordId) ? BP_MissingInfo.refresh(recordId, force) : XpMissingInfo.refresh(recordId);
    }

    @AuraEnabled
    public static Map<String, Object> preview(Id recordId, String note, List<String> leaveOut) {
        return isClaim(recordId)
            ? BP_MissingInfo.previewLeavingOut(recordId, note, leaveOut)
            : XpMissingInfo.previewLeavingOut(recordId, note, leaveOut);
    }

    @AuraEnabled
    public static String sendEmail(Id recordId, String note, List<String> leaveOut) {
        return isClaim(recordId)
            ? BP_MissingInfo.sendLeavingOut(recordId, note, leaveOut)
            : XpMissingInfo.sendLeavingOut(recordId, note, leaveOut);
    }

    // Call of 11/11/2026 17h13: the validation agent's own questions for the client (one per line), on a claim only
    // ("Hi, I have to clarify some information on your application. I have some questions..."). On an application they
    // are ignored and the email is the Sales one.
    @AuraEnabled
    public static Map<String, Object> previewAsking(Id recordId, String note, List<String> leaveOut, String questions) {
        return isClaim(recordId)
            ? BP_MissingInfo.previewAsking(recordId, note, leaveOut, questions)
            : XpMissingInfo.previewLeavingOut(recordId, note, leaveOut);
    }

    @AuraEnabled
    public static String sendAsking(Id recordId, String note, List<String> leaveOut, String questions) {
        return isClaim(recordId)
            ? BP_MissingInfo.sendAsking(recordId, note, leaveOut, questions)
            : XpMissingInfo.sendLeavingOut(recordId, note, leaveOut);
    }

    // Claim ou Application; qualquer outro objeto é recusado.
    private static Boolean isClaim(Id recordId) {
        Schema.SObjectType t = recordId == null ? null : recordId.getSObjectType();
        if (t == Basic__c.SObjectType) return true;
        if (t == Application__c.SObjectType) return false;
        String message = 'Missing Information works only on an application or a claim.';
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        throw e;
    }
}