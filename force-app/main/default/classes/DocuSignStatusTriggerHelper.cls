public with sharing class DocuSignStatusTriggerHelper {
    public static String EnvelopeTemplateName = 'Application';

    public static void afterInsert(List<dfsle__EnvelopeStatus__c> newList) {
        try {
            List<dfsle__EnvelopeStatus__c> currentEnvelopStatus = [
                SELECT
                    Id,
                    dfsle__SourceId__c,
                    dfsle__DocuSignId__c
                FROM dfsle__EnvelopeStatus__c
                WHERE Id IN :newList
                LIMIT 10000
            ];
            if (currentEnvelopStatus.isEmpty()) {
                return;
            }
            Map<String, dfsle__EnvelopeStatus__c> envelopStatusForApplication = new Map<String, dfsle__EnvelopeStatus__c>();
            for (dfsle__EnvelopeStatus__c docStatus : currentEnvelopStatus) {
                if (docStatus.dfsle__SourceId__c != null
                        && Schema.Application__c.SObjectType == Id.valueOf(docStatus.dfsle__SourceId__c).getSobjectType()) {
                    envelopStatusForApplication.put(docStatus.dfsle__DocuSignId__c, docStatus);
                    docStatus.Application__c = docStatus.dfsle__SourceId__c;
                }
            }
            update currentEnvelopStatus;
            if (envelopStatusForApplication.isEmpty()) {
                return;
            }
            List<dfsle__Envelope__c> relatedEnvelops = [
                SELECT
                    dfsle__DocuSignId__c,
                    (SELECT
                        dfsle__FullName__c,
                        dfsle__Envelope__c,
                        dfsle__SourceId__c,
                        DocuSign_Status__c
                    FROM dfsle__Documents__r
                    WHERE dfsle__FullName__c != :EnvelopeTemplateName)
                FROM dfsle__Envelope__c
                WHERE dfsle__DocuSignId__c IN : envelopStatusForApplication.keySet()
            ];
            List<dfsle__Document__c> updatedEnvelopDocuments = new List<dfsle__Document__c>();
            for (dfsle__Envelope__c envelop : relatedEnvelops) {
                dfsle__EnvelopeStatus__c envelopStatus = envelopStatusForApplication.get(envelop.dfsle__DocuSignId__c);
                if (envelopStatus == null) {
                    continue;
                }
                for (dfsle__Document__c document : envelop.dfsle__Documents__r) {
                    document.DocuSign_Status__c = envelopStatus.Id;
                    updatedEnvelopDocuments.add(document);
                }
            }
            if (!updatedEnvelopDocuments.isEmpty()) {
                update updatedEnvelopDocuments;
            }
        } catch (Exception ex){
            System.debug('ERROR '+ ex.getMessage());
        }
    }
}