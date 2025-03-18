public class ApplicationDocumentTriggerHandler {
    public Map<Id, Application_Document__c> newAppDocs;
    public Map<Id, Application_Document__c> oldAppDocs;

    public ApplicationDocumentTriggerHandler(Map<Id, Application_Document__c> newDocsRecords, Map<Id, Application_Document__c> oldDocsRecords) {
        this.newAppDocs = newDocsRecords;
        this.oldAppDocs = oldDocsRecords;
    }

    public void updateRelatedApplicationDocumentsName() {
        Set<Id> socialInsuranceApplicationIds = new Set<Id>();
        Set<Id> customLetterApplicationIds = new Set<Id>();
        for (Application_Document__c doc : newAppDocs.values()) {
            if (doc.Type__c == 'Statement of Social Insurance') {
                socialInsuranceApplicationIds.add(doc.Application__c);
            } else if (doc.Type__c == 'Custom Letter') {
                customLetterApplicationIds.add(doc.Application__c);
            }
        }
        if (!socialInsuranceApplicationIds.isEmpty()) {
            changeSocialInsuranceDocumentNames(socialInsuranceApplicationIds);
        }
        if (!customLetterApplicationIds.isEmpty()) {
            changeCustomerLetterDocumentNames(customLetterApplicationIds);
        }
    }

    public void changeSocialInsuranceDocumentNames (Set<Id> socialInsuranceApplicationIds) {
        Map<Id, Application__c> currentApplications = new Map<Id, Application__c>([
            SELECT
                (SELECT
                    ContentDocumentId,
                    ContentDocument.Title,
                    ContentDocument.CreatedDate,
                    LinkedEntityId
                 FROM ContentDocumentLinks
                 WHERE ContentDocument.Title LIKE '%CF083%'
                    OR ContentDocument.Title LIKE '%64-8%'
                 ORDER BY ContentDocument.CreatedDate DESC)
            FROM Application__c
            WHERE Id IN :socialInsuranceApplicationIds
        ]);
        Map<Id, List<ContentDocumentLink>> appIdByListContDocs = new Map<Id, List<ContentDocumentLink>>();
        for (Application__c app : currentApplications.values()) {
            if (app.ContentDocumentLinks.size() == 2) {
                return;
            } else if (app.ContentDocumentLinks.size() > 2) {
                appIdByListContDocs.put(app.Id, app.ContentDocumentLinks);
            }
        }
        List<Id> idContDocs = new List<Id>();
        for (List<ContentDocumentLink> links : appIdByListContDocs.values()) {
            for (ContentDocumentLink link : links) {
                idContDocs.add(link.ContentDocumentId);
            }
        }
        Map<Id, ContentDocument> currentContentDocuments = new Map<Id, ContentDocument>([
            SELECT
                Id,
                Title
            FROM ContentDocument
            WHERE Id IN: idContDocs
        ]);
        for (List<ContentDocumentLink> links : appIdByListContDocs.values()) {
            if (links.size() < 4) {
                continue;
            }
            for (Integer i = 0; i < links.size(); i++) {
                if (i == 0 || i == 1) {
                    continue;
                }
                if (links[i].ContentDocument.Title.contains('ForSignature')) {
                    Double numberOfVersion = links.size()/2 - i/2;
                    String newVersion = 'v' + numberOfVersion;
                    String title = links[i].ContentDocument.title.replace('ForSignature',newVersion);
                    currentContentDocuments.get(links[i].ContentDocumentId).Title = title;
                }
            }
        }
        update currentContentDocuments.values();

        List<Application_Document__c> currentApplicationDocuments = [
            SELECT
                Application__c,
                File_Name__c,
                For_Signature__c,
                (SELECT
                    ContentDocument.Title
                FROM ContentDocumentLinks)
            FROM Application_Document__c
            WHERE Application__c IN :socialInsuranceApplicationIds
        ];
        for (Application_Document__c document : currentApplicationDocuments) {
            if (!document.ContentDocumentLinks.isEmpty()) {
                document.File_Name__c = document.ContentDocumentLinks[0].ContentDocument.Title;
                document.For_Signature__c = false;
            }
        }
        update currentApplicationDocuments;
    }

    public void changeCustomerLetterDocumentNames(Set<Id> customLetterApplicationIds) {
        Map<Id, Application__c> currentApplications = new Map<Id, Application__c>([
            SELECT
                (SELECT
                    ContentDocumentId,
                    ContentDocument.Title,
                    ContentDocument.CreatedDate,
                    LinkedEntityId
                 FROM ContentDocumentLinks
                 WHERE ContentDocument.Title LIKE '%CustomLetter%'
                 ORDER BY ContentDocument.CreatedDate DESC)
            FROM Application__c
            WHERE Id IN :customLetterApplicationIds
        ]);
        Map<Id, List<ContentDocumentLink>> appIdByListContDocs = new Map<Id, List<ContentDocumentLink>>();
        for (Application__c app : currentApplications.values()) {
            if (app.ContentDocumentLinks.size() == 1) {
                return;
            } else if (app.ContentDocumentLinks.size() > 1) {
                appIdByListContDocs.put(app.Id, app.ContentDocumentLinks);
            }
        }
        List<Id> idContDocs = new List<Id>();
        for (List<ContentDocumentLink> links : appIdByListContDocs.values()) {
            for (ContentDocumentLink link : links) {
                idContDocs.add(link.ContentDocumentId);
            }
        }
        Map<Id, ContentDocument> currentContentDocuments = new Map<Id, ContentDocument>([
            SELECT
                Id,
                Title
            FROM ContentDocument
            WHERE Id IN: idContDocs
        ]);
        for (List<ContentDocumentLink> links : appIdByListContDocs.values()) {
            for (Integer i = 0; i < links.size(); i++) {
                if (i == 0 ) {
                    continue;
                }
                if (links[i].ContentDocument.Title.contains('ForSignature')) {
                    Double numberOfVersion = links.size() - i;
                    String newVersion = 'v' + numberOfVersion;
                    String title1 = links[i].ContentDocument.title.replace('ForSignature',newVersion);
                    currentContentDocuments.get(links[i].ContentDocumentId).Title = title1;
                }
            }
        }
        update currentContentDocuments.values();
        List<Application_Document__c> currentApplicationDocuments = [
            SELECT
                Application__c,
                File_Name__c,
                For_Signature__c,
                (SELECT
                    ContentDocument.Title
                FROM ContentDocumentLinks)
            FROM Application_Document__c
            WHERE Application__c IN :customLetterApplicationIds
        ];
        for (Application_Document__c document : currentApplicationDocuments) {
            if (!document.ContentDocumentLinks.isEmpty()) {
                document.File_Name__c = document.ContentDocumentLinks[0].ContentDocument.Title;
                document.For_Signature__c = false;
            }
        }
        update currentApplicationDocuments;
    }

    public void changedForSignatureAppDocument() {
        List<Application_Document__c> newDocs = newAppDocs.values();
        List<Application_Document__c> oldDocs = oldAppDocs.values();
        for (Integer i = 0; i < newDocs.size(); i++) {
            if (newDocs[i].Status__c != oldDocs[i].Status__c) {
                return;
            }
        }
        Set<Id> statementApplicationIds = new Set<Id>();
        Set<Id> customLetterApplicationIds = new Set<Id>();
        for (Application_Document__c doc : newAppDocs.values()) {
            if (doc.For_Signature__c != oldAppDocs.get(doc.Id).For_Signature__c &&
                doc.For_Signature__c == true &&
                doc.Type__c == 'Statement of Social Insurance') {
                statementApplicationIds.add(doc.Application__c);
            } else if (doc.For_Signature__c != oldAppDocs.get(doc.Id).For_Signature__c && 
                       doc.For_Signature__c == true &&
                       doc.Type__c == 'Custom Letter') {
                customLetterApplicationIds.add(doc.Application__c);
            }
        }
        if (!statementApplicationIds.isEmpty()) {
            changedForSignatureAppStatementDocument(statementApplicationIds);
        }
        if (!customLetterApplicationIds.isEmpty()) {
            changedForSignatureAppCustomLetterDocument(customLetterApplicationIds);
        }
    }

    public void changedForSignatureAppStatementDocument(Set<Id> statementApplicationIds) {
        Map<Id,Application_Document__c> currentApplications = new Map<Id,Application_Document__c>([
            SELECT
                Application__c,
                Application__r.First_Name__c,
                Application__r.Second_Name__c,
                Application__r.Name,
                File_Name__c,
                CreatedDate,
                For_Signature__c,
                (SELECT
                    ContentDocumentId,
                    ContentDocument.Title,
                    ContentDocument.CreatedDate,
                    LinkedEntityId
                FROM ContentDocumentLinks
                WHERE ContentDocument.Title LIKE '%CF083%'
                    OR ContentDocument.Title LIKE '%64-8%'
                ORDER BY ContentDocument.CreatedDate DESC)
            FROM Application_Document__c
            WHERE Application__c IN :statementApplicationIds
                AND (File_Name__c LIKE '%CF083%' OR File_Name__c LIKE '%64-8%')
            ORDER BY CreatedDate DESC
        ]);
        Map<Id, List<Application_Document__c>> appIdByListRelatedAppDocs = new Map<Id, List<Application_Document__c>>();
        for (Application_Document__c doc : currentApplications.values()) {
            if (appIdByListRelatedAppDocs.get(doc.Application__c) == null) {
                List<Application_Document__c> relatedDocs = new List<Application_Document__c>();
                relatedDocs.add(doc);
                appIdByListRelatedAppDocs.put(doc.Application__c, relatedDocs);
            } else {
                List<Application_Document__c> relatedDocs = appIdByListRelatedAppDocs.get(doc.Application__c);
                relatedDocs.add(doc);
                appIdByListRelatedAppDocs.put(doc.Application__c, relatedDocs);
            }
        }
        List<Application_Document__c> updateDocs = new List<Application_Document__c>();
        for (List<Application_Document__c> docs : appIdByListRelatedAppDocs.values()) {
            Application_Document__c currentDocs = new Application_Document__c();
            Boolean isCF083 = false;
            for (Application_Document__c doc : docs) {
                if (newAppDocs.get(doc.Id) != null) {
                    currentDocs = currentApplications.get(doc.Id);
                    if (doc.ContentDocumentLinks[0].ContentDocument.Title.contains('CF083')) {
                        currentDocs.File_Name__c = currentDocs.File_Name__c.substring(0,currentDocs.File_Name__c.indexOf('CF083_')+6) + 'ForSignature';
                        isCF083 = true;
                    } else if (doc.ContentDocumentLinks[0].ContentDocument.Title.contains('64-8')) {
                        currentDocs.File_Name__c = currentDocs.File_Name__c.substring(0,currentDocs.File_Name__c.indexOf('64-8_')+5) + 'ForSignature';
                    }
                    updateDocs.add(currentDocs);
                    break;
                }
            }
            Application_Document__c oldDoc = new Application_Document__c();
            for (Integer i = 0; i < docs.size(); i++) {
                if (newAppDocs.get(docs[i].Id) == null &&
                    docs[i].ContentDocumentLinks[0].ContentDocument.Title.contains('ForSignature') &&
                    ((isCF083 && docs[i].ContentDocumentLinks[0].ContentDocument.Title.contains('CF083')) ||
                      (!isCF083 && docs[i].ContentDocumentLinks[0].ContentDocument.Title.contains('64-8')))) {
                    oldDoc = currentApplications.get(docs[i].Id);
                    Double numberOfVersion = docs.size()/2 - i/2;
                    if (isCF083) {
                        oldDoc.File_Name__c = oldDoc.File_Name__c.replace('ForSignature', 'v' + numberOfVersion);
                        oldDoc.For_Signature__c = false;
                        updateDocs.add(oldDoc);
                    } else {
                        oldDoc.File_Name__c = oldDoc.File_Name__c.replace('ForSignature', 'v' + numberOfVersion);
                        oldDoc.For_Signature__c = false;
                        updateDocs.add(oldDoc);
                    }
                }
            }
        }

        if (ApplicationUtility.isFirstUpdate) {
            update updateDocs;
            ApplicationUtility.isFirstUpdate = false;
        }
        List<ContentDocument> updateContentDocument = new List<ContentDocument>();
        for (Application_Document__c document : currentApplications.values()) {
            ContentDocument relatedContentDocument =new ContentDocument(Id = document.ContentDocumentLinks[0].ContentDocumentId);
            if (document.Application__r.Name != document.ContentDocumentLinks[0].ContentDocument.Title) {
                relatedContentDocument.Title = document.File_Name__c;
                updateContentDocument.add(relatedContentDocument);
            }
        }
        update updateContentDocument;
    }

    public void changedForSignatureAppCustomLetterDocument(Set<Id> customLetterApplicationIds) {
        Map<Id,Application_Document__c> currentApplications = new Map<Id,Application_Document__c>([
            SELECT
                Application__c,
                Application__r.First_Name__c,
                Application__r.Second_Name__c,
                Application__r.Name,
                File_Name__c,
                CreatedDate,
                For_Signature__c,
                (SELECT
                    ContentDocumentId,
                    ContentDocument.Title,
                    ContentDocument.CreatedDate,
                    LinkedEntityId
                FROM ContentDocumentLinks
                WHERE ContentDocument.Title LIKE '%CustomLetter%'
                ORDER BY ContentDocument.CreatedDate DESC)
            FROM Application_Document__c
            WHERE Application__c IN :customLetterApplicationIds
                AND File_Name__c LIKE '%CustomLetter%'
            ORDER BY CreatedDate DESC
        ]);
        Map<Id, List<Application_Document__c>> appIdByListRelatedAppDocs = new Map<Id, List<Application_Document__c>>();
        for (Application_Document__c doc : currentApplications.values()) {
            if (appIdByListRelatedAppDocs.get(doc.Application__c) == null) {
                List<Application_Document__c> relatedDocs = new List<Application_Document__c>();
                relatedDocs.add(doc);
                appIdByListRelatedAppDocs.put(doc.Application__c, relatedDocs);
            } else {
                List<Application_Document__c> relatedDocs = appIdByListRelatedAppDocs.get(doc.Application__c);
                relatedDocs.add(doc);
                appIdByListRelatedAppDocs.put(doc.Application__c, relatedDocs);
            }
        }

        List<Application_Document__c> updateDocs = new List<Application_Document__c>();
        for (List<Application_Document__c> docs : appIdByListRelatedAppDocs.values()) {
            Application_Document__c currentDocs = new Application_Document__c();
            for (Application_Document__c doc : docs) {
                if (newAppDocs.get(doc.Id) != null) {
                    currentDocs = currentApplications.get(doc.Id);
                    currentDocs.File_Name__c = doc.Application__r.First_Name__c + '_' + doc.Application__r.Second_Name__c + '_' + doc.Application__r.Name + '_CustomLetter_ForSignature';
                    updateDocs.add(currentDocs);
                }
            }
            Application_Document__c oldDoc = new Application_Document__c();
            for (Integer i = 0; i < docs.size(); i++) {
                if (newAppDocs.get(docs[i].Id) == null &&
                    docs[i].ContentDocumentLinks[0].ContentDocument.Title.contains('ForSignature') &&
                    docs[i].ContentDocumentLinks[0].ContentDocument.Title.contains('CustomLetter')) {
                    oldDoc = currentApplications.get(docs[i].Id);
                    Double numberOfVersion = docs.size() - i;
                    oldDoc.File_Name__c = docs[i].Application__r.First_Name__c + '_' + docs[i].Application__r.Second_Name__c + '_' + docs[i].Application__r.Name + '_CustomLetter_v'+ numberOfVersion;
                    oldDoc.For_Signature__c = false;
                    updateDocs.add(oldDoc);
                }
            }
        }
        update updateDocs;
        List<ContentDocument> updateContentDocument = new List<ContentDocument>();
        for (Application_Document__c document : currentApplications.values()) {
            ContentDocument relatedContentDocument =new ContentDocument(Id = document.ContentDocumentLinks[0].ContentDocumentId);
            if (document.Application__r.Name != document.ContentDocumentLinks[0].ContentDocument.Title) {
                relatedContentDocument.Title = document.File_Name__c;
                updateContentDocument.add(relatedContentDocument);
            }
        }
        update updateContentDocument;
    }
}