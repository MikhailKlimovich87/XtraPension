public with sharing class ContentDocumentLinkTriggerHelper {

    public static void afterInsert(List<ContentDocumentLink> newList) {
        try {
            List<ContentDocumentLink> appDocLinksToInsert = new List<ContentDocumentLink>();
            Set<Id> linkIds = new Set<Id>();
            for(ContentDocumentLink link : newList) {
                Schema.SObjectType typeOfRecord = Id.valueOf(link.LinkedEntityId).getSobjectType();
                if(Schema.Application__c.SObjectType == typeOfRecord) {
                    linkIds.add(link.Id);
                }
            }
            if(!linkIds.isEmpty()){
                List<ContentDocumentLink> links = [
                    SELECT
                        Id, ContentDocument.Title,
                        ContentDocument.FileExtension,
                        ContentDocument.FileType,
                        LinkedEntityId
                    FROM ContentDocumentLink
                    WHERE Id IN: linkIds];
                Map<Id, ContentDocumentLink> linksByIdMap = new Map<Id, ContentDocumentLink>();
                Set<Id> applicationIds = new Set<Id>();
                List<String> appDocNames = new List<String>();
                List<ContentDocument> updateContDocs = new List<ContentDocument>();
                Set<Id> notesId = new Set<Id>();
                for(ContentDocumentLink link : links) {
                    ContentDocument doc = new ContentDocument();
                    String fileExtension = 'pdf';
                    doc.Id = link.ContentDocument.Id;
                    doc.Title = link.ContentDocument.Title.remove('.' + fileExtension);
                    updateContDocs.add(doc);
                    if(link.ContentDocument.FileExtension != null){
                        fileExtension = link.ContentDocument.FileExtension;
                    }
                    if(link.ContentDocument.Title != null
                        && link.ContentDocument.Title.containsIgnoreCase('_completed')) {
                        appDocNames.add(link.ContentDocument.Title.remove('_completed').remove('.' + fileExtension));
                        linksByIdMap.put(link.Id, link);
                        applicationIds.add(link.LinkedEntityId);
                    }
                }
                if (!updateContDocs.isEmpty()) {
                    update updateContDocs;
                }
                if(!appDocNames.isEmpty()) {
                    List<Application_Document__c> applicationDocuments = [SELECT Id, Status__c, Application__c, File_Name__c
                        FROM Application_Document__c
                        WHERE File_Name__c IN: appDocNames AND Application__c IN: applicationIds];
                    Map<Id, List<Application_Document__c>> appDocsByApplicationId = new Map<Id, List<Application_Document__c>>();
                    for (Application_Document__c appDoc : applicationDocuments){
                        if(appDoc.Application__c != null) {
                            appDocsByApplicationId.put(appDoc.Application__c, new List<Application_Document__c>());
                        }
                    }
                    for (Application_Document__c appDoc : applicationDocuments){
                        if(appDoc.Application__c != null) {
                            appDocsByApplicationId.get(appDoc.Application__c).add(appDoc);
                        }
                    }
                    //Get DocuSign file Names
                    Map<String, Id> appIdMapByEnvelopIds = new Map<String, Id>();
                    List<dfsle__EnvelopeStatus__c> envelopeStatuses = [SELECT Id, dfsle__DocuSignId__c, Application__c
                        FROM dfsle__EnvelopeStatus__c
                        WHERE Application__c IN: applicationIds];
                    for(dfsle__EnvelopeStatus__c envlStatus : envelopeStatuses){
                        if(envlStatus.dfsle__DocuSignId__c != null){
                            appIdMapByEnvelopIds.put(envlStatus.dfsle__DocuSignId__c, envlStatus.Application__c);
                        }
                    }
                    Map<String, Set<String>> docuSignFileNamesByApplicationId = new Map<String, Set<String>>();
                    if(!appIdMapByEnvelopIds.isEmpty()) {
                        List<dfsle__Envelope__c> dEnvelopes = [SELECT Id, dfsle__DocuSignId__c,
                            (SELECT Id, dfsle__FullName__c, dfsle__Extension__c, Name FROM dfsle__Documents__r WHERE dfsle__Type__c = 'ContentVersion')
                            FROM dfsle__Envelope__c
                            WHERE dfsle__DocuSignId__c IN: appIdMapByEnvelopIds.keySet()];
                        for(dfsle__Envelope__c env :dEnvelopes) {
                            if(appIdMapByEnvelopIds.containsKey(env.dfsle__DocuSignId__c)) {
                                Id applicationIdTMP = appIdMapByEnvelopIds.get(env.dfsle__DocuSignId__c);
                                if(applicationIdTMP != null) {
                                    for (dfsle__Document__c doc : env.dfsle__Documents__r) {
                                        if (docuSignFileNamesByApplicationId.containsKey(applicationIdTMP)) {
                                            docuSignFileNamesByApplicationId.get(applicationIdTMP).add(doc.dfsle__FullName__c.remove('.' + doc.dfsle__Extension__c));
                                        } else {
                                            docuSignFileNamesByApplicationId.put(applicationIdTMP, new Set<String>());
                                            docuSignFileNamesByApplicationId.get(applicationIdTMP).add(doc.dfsle__FullName__c.remove('.' + doc.dfsle__Extension__c));
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Map<Id,  Application_Document__c> appDocsToUpdateByIds = new Map<Id, Application_Document__c>();
                    Map<String, ContentDocumentLink> contLinkByNotFoudFileNames = new Map<String, ContentDocumentLink>();
                    for (ContentDocumentLink link : linksByIdMap.values()) {
                        Id applicationId = link.LinkedEntityId;
                        String fileExtension = 'pdf';
                        if(link.ContentDocument.FileExtension != null){
                            fileExtension = link.ContentDocument.FileExtension;
                        }
                        if(appDocsByApplicationId.containsKey(applicationId)){
                            for(Application_Document__c appDocTMP : appDocsByApplicationId.get(applicationId)) {
                                if(appDocTMP.File_Name__c != null && docuSignFileNamesByApplicationId.containsKey(applicationId)
                                        && docuSignFileNamesByApplicationId.get(applicationId).contains(appDocTMP.File_Name__c.remove('.' + fileExtension))
                                        && link.ContentDocument.Title.remove('_completed').remove('.' + fileExtension) == appDocTMP.File_Name__c.remove('.' + fileExtension)) {
                                    appDocTMP.Status__c = 'Signed';
                                    appDocsToUpdateByIds.put(appDocTMP.Id, appDocTMP);
                                    //Application Document Link
                                    ContentDocumentLink newLinkAD = link.clone(false, true);
                                    newLinkAD.LinkedEntityId = appDocTMP.Id;
                                    appDocLinksToInsert.add(newLinkAD);
                                    // Not Found File
                                    if(contLinkByNotFoudFileNames.containsKey(link.ContentDocument.Title)) {
                                        contLinkByNotFoudFileNames.remove(link.ContentDocument.Title);
                                    }
                                }else {
                                    contLinkByNotFoudFileNames.put(link.ContentDocument.Title, link);
                                }
                            }
                        }else {
                            contLinkByNotFoudFileNames.put(link.ContentDocument.Title, link);
                        }
                    }
                    Map<Id, Application_Document__c> appDocsToInsertByContDocId = new Map<Id, Application_Document__c>();
                    for(String fileName : contLinkByNotFoudFileNames.keySet()){
                        ContentDocumentLink link = contLinkByNotFoudFileNames.get(fileName);
                        String fileExtension = 'pdf';
                        if(link.ContentDocument.FileExtension != null){
                            fileExtension = link.ContentDocument.FileExtension;
                        }
                        if(docuSignFileNamesByApplicationId.containsKey(link.LinkedEntityId)
                                && docuSignFileNamesByApplicationId.get(link.LinkedEntityId).contains(link.ContentDocument.Title.remove('_completed').remove('.' + fileExtension))){
                            //Create Application Document
                            Application_Document__c appDoc = new Application_Document__c();
                            appDoc.Application__c = link.LinkedEntityId;
                            appDoc.Status__c = 'Signed';
                            appDoc.File_Name__c = link.ContentDocument.Title.remove('_completed').remove('.' + fileExtension);
                            appDocsToInsertByContDocId.put(link.ContentDocumentId, appDoc);
                        }
                    }
                    if(!appDocsToUpdateByIds.isEmpty()) update appDocsToUpdateByIds.values();
                    if(!appDocsToInsertByContDocId.isEmpty()){
                        insert appDocsToInsertByContDocId.values();
                        for (Id contDocId : appDocsToInsertByContDocId.keySet()){
                            Application_Document__c applicationDocTMP = appDocsToInsertByContDocId.get(contDocId);
                            ContentDocumentLink newLinkAD = new ContentDocumentLink();
                            newLinkAD.LinkedEntityId = applicationDocTMP.Id;
                            newLinkAD.ContentDocumentId = contDocId;
                            newLinkAD.shareType = 'V';
                            appDocLinksToInsert.add(newLinkAD);
                        }
                    }
                    if(!appDocLinksToInsert.isEmpty()) insert appDocLinksToInsert;
                }
            }
        }catch (Exception ex){
            System.debug('ERROR '+ ex.getMessage());
        }
    }
}