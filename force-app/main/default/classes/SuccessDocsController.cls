public class SuccessDocsController {
    public static final String GET_RECEIPT_DOC_NAME = 'Next Step 2 - Get Receipt';
    public static final String PAY_HMRC_DOC_NAME = 'Next Step 1 - Pay HMRC';
    public static final String ANNUAL_SERVICE_DOC_NAME = 'Annual Service';
    public static final String PRIVATE_PENSION_DOC_NAME = 'Private Pensions';
    public static final String BANK_TRANSFER_DOC_NAME = 'Bank Transfer';

    @future(callout=true)
    public static void generateDocs(String recordId)  {
        List<Application__c> currentApps = [
            SELECT Name
            FROM Application__c
            WHERE Id = :recordId
        ];
        if (currentApps.isEmpty()) {
            return;
        }
        Application__c currentApp = currentApps[0];
        PageReference savepage ;
        savepage = Page.GetReceipt;
        savepage.getParameters().put('id', recordId);
        blob pdfBlob;
        if (!Test.isRunningTest()) {
            pdfBlob = savepage.getContent();
        } else {
            pdfBlob = Blob.valueOf('Test');
        }
        List<ContentDocumentLink> relatedDocs = Database.query(
            'SELECT ' +
                'ContentDocumentId, ' +
                'ContentDocument.Title, ' +
                'ContentDocument.LatestPublishedVersion.VersionData ' +
            'FROM ContentDocumentLink ' +
            'WHERE LinkedEntityId = :recordId ' +
            'AND (ContentDocument.Title LIKE \'%' + GET_RECEIPT_DOC_NAME + '%\' ' +
            'OR ContentDocument.Title LIKE \'%' + PAY_HMRC_DOC_NAME + '%\' ' +
            'OR ContentDocument.Title LIKE \'%' + BANK_TRANSFER_DOC_NAME + '%\' ' +
            'OR ContentDocument.Title LIKE \'%' + PRIVATE_PENSION_DOC_NAME + '%\' ' +
            'OR ContentDocument.Title LIKE \'%' + ANNUAL_SERVICE_DOC_NAME + '%\')'
        );
        Map<String, ContentVersion> newVersionOfDocs = new Map<String, ContentVersion>();
        if (!relatedDocs.isEmpty()) {
            for (ContentDocumentLink doc : relatedDocs) {
                if(doc.ContentDocument.Title.contains(GET_RECEIPT_DOC_NAME)) {
                    ContentVersion getReceiptDoc = new ContentVersion();
                    getReceiptDoc.ContentLocation = 'S';
                    getReceiptDoc.PathOnClient = currentApp.Name  + ' - ' + GET_RECEIPT_DOC_NAME + '.pdf';
                    getReceiptDoc.Title = currentApp.Name  + ' - ' + GET_RECEIPT_DOC_NAME;
                    getReceiptDoc.VersionData = pdfBlob;
                    getReceiptDoc.ContentDocumentId = doc.ContentDocumentId;
                    newVersionOfDocs.put(GET_RECEIPT_DOC_NAME, getReceiptDoc);
                } else if(doc.ContentDocument.Title.contains(PAY_HMRC_DOC_NAME)) {
                    ContentVersion payHMRC_Doc = new ContentVersion();
                    payHMRC_Doc.ContentLocation = 'S';
                    payHMRC_Doc.PathOnClient = currentApp.Name  + ' - ' + PAY_HMRC_DOC_NAME + '.pdf';
                    payHMRC_Doc.Title = currentApp.Name  + ' - ' + PAY_HMRC_DOC_NAME;
                    payHMRC_Doc.VersionData = doc.ContentDocument.LatestPublishedVersion.VersionData;
                    payHMRC_Doc.ContentDocumentId = doc.ContentDocumentId;
                    newVersionOfDocs.put(PAY_HMRC_DOC_NAME, payHMRC_Doc);
                } else if(doc.ContentDocument.Title.contains(ANNUAL_SERVICE_DOC_NAME)) {
                    ContentVersion annualService_Doc = new ContentVersion();
                    annualService_Doc.ContentLocation = 'S';
                    annualService_Doc.PathOnClient = currentApp.Name  + ' - ' + ANNUAL_SERVICE_DOC_NAME + '.pdf';
                    annualService_Doc.Title = currentApp.Name  + ' - ' + ANNUAL_SERVICE_DOC_NAME;
                    annualService_Doc.VersionData = doc.ContentDocument.LatestPublishedVersion.VersionData;
                    annualService_Doc.ContentDocumentId = doc.ContentDocumentId;
                    newVersionOfDocs.put(ANNUAL_SERVICE_DOC_NAME, annualService_Doc);
                } else if(doc.ContentDocument.Title.contains(BANK_TRANSFER_DOC_NAME)) {
                    ContentVersion bankTransfer_Doc = new ContentVersion();
                    bankTransfer_Doc.ContentLocation = 'S';
                    bankTransfer_Doc.PathOnClient = currentApp.Name  + ' - ' + BANK_TRANSFER_DOC_NAME + '.pdf';
                    bankTransfer_Doc.Title = currentApp.Name  + ' - ' + BANK_TRANSFER_DOC_NAME;
                    bankTransfer_Doc.VersionData = doc.ContentDocument.LatestPublishedVersion.VersionData;
                    bankTransfer_Doc.ContentDocumentId = doc.ContentDocumentId;
                    newVersionOfDocs.put(BANK_TRANSFER_DOC_NAME, bankTransfer_Doc);
                } else if(doc.ContentDocument.Title.contains(BANK_TRANSFER_DOC_NAME)) {
                    ContentVersion privatePensions_Doc = new ContentVersion();
                    privatePensions_Doc.ContentLocation = 'S';
                    privatePensions_Doc.PathOnClient = currentApp.Name  + ' - ' + PRIVATE_PENSION_DOC_NAME + '.pdf';
                    privatePensions_Doc.Title = currentApp.Name  + ' - ' + PRIVATE_PENSION_DOC_NAME;
                    privatePensions_Doc.VersionData = doc.ContentDocument.LatestPublishedVersion.VersionData;
                    privatePensions_Doc.ContentDocumentId = doc.ContentDocumentId;
                    newVersionOfDocs.put(PRIVATE_PENSION_DOC_NAME, privatePensions_Doc);
                }
            }
            if (!newVersionOfDocs.isEmpty()) {
                insert newVersionOfDocs.values();
            }
        }
        List<ContentDocumentLink> newLinks = new List<ContentDocumentLink>();
        if (newVersionOfDocs.get(GET_RECEIPT_DOC_NAME) == null) {
            ContentVersion conVer = new ContentVersion();
            conVer.ContentLocation = 'S';
            conVer.PathOnClient = currentApp.Name  + ' - ' + GET_RECEIPT_DOC_NAME + '.pdf';
            conVer.Title = currentApp.Name  + ' - ' + GET_RECEIPT_DOC_NAME;
            conVer.VersionData = pdfBlob;
            insert conVer;

            ContentVersion conDoc = [
                SELECT
                    ContentDocumentId,
                    ContentSize
                FROM ContentVersion
                WHERE Id =:conVer.Id][0];
            ContentDocumentLink conDocStep2Link = new ContentDocumentLink();
            conDocStep2Link.LinkedEntityId = recordId;
            conDocStep2Link.ContentDocumentId = conDoc.ContentDocumentId;
            conDocStep2Link.shareType = 'V';
            conDocStep2Link.Visibility = 'AllUsers';

            newLinks.add(conDocStep2Link);
        }
        List<ContentVersion> basicDocs =[
            SELECT
                Title,
                ContentDocumentId,
                VersionData
            FROM ContentVersion
            WHERE Title = :PAY_HMRC_DOC_NAME OR
                  Title = :ANNUAL_SERVICE_DOC_NAME OR
                  Title = :BANK_TRANSFER_DOC_NAME OR
                  Title = :PRIVATE_PENSION_DOC_NAME
        ];
        if (basicDocs.isEmpty()) {
            return;
        }
        Map<String, Blob> basicDocNameToVersionData = new Map<String, Blob>();
        for (ContentVersion version : basicDocs) {
            basicDocNameToVersionData.put(version.Title, version.VersionData);
        }
        if (newVersionOfDocs.get(PAY_HMRC_DOC_NAME) == null && basicDocNameToVersionData.get(PAY_HMRC_DOC_NAME) != null) {
            List<Object> listName = new List<Object>();
            ContentVersion newStep1Doc = new ContentVersion();
            newStep1Doc.Title  = currentApp.Name + ' - ' + PAY_HMRC_DOC_NAME;
            newStep1Doc.PathOnClient  = currentApp.Name + ' - ' + PAY_HMRC_DOC_NAME + '.pdf';
            newStep1Doc.VersionData = basicDocNameToVersionData.get(PAY_HMRC_DOC_NAME);
            insert newStep1Doc;

            ContentVersion step1Doc = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id =:newStep1Doc.Id][0];

            ContentDocumentLink conDocStep1Link = New ContentDocumentLink();
            conDocStep1Link.LinkedEntityId = recordId;
            conDocStep1Link.ContentDocumentId = step1Doc.ContentDocumentId;
            conDocStep1Link.shareType = 'V';
            conDocStep1Link.Visibility = 'AllUsers';

            newLinks.add(conDocStep1Link);
        }
        if (newVersionOfDocs.get(ANNUAL_SERVICE_DOC_NAME) == null && basicDocNameToVersionData.get(ANNUAL_SERVICE_DOC_NAME) != null) {
            ContentVersion newAnnualServiceDoc = new ContentVersion();
            newAnnualServiceDoc.Title  = currentApp.Name + ' - ' + ANNUAL_SERVICE_DOC_NAME;
            newAnnualServiceDoc.PathOnClient  = currentApp.Name + ' - ' + ANNUAL_SERVICE_DOC_NAME + '.pdf';
            newAnnualServiceDoc.VersionData = basicDocNameToVersionData.get(ANNUAL_SERVICE_DOC_NAME);
            insert newAnnualServiceDoc;

            ContentVersion annualServiceDoc = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id =:newAnnualServiceDoc.Id][0];

            ContentDocumentLink conDocAnnualServiceLink = New ContentDocumentLink();
            conDocAnnualServiceLink.LinkedEntityId = recordId;
            conDocAnnualServiceLink.ContentDocumentId = annualServiceDoc.ContentDocumentId;
            conDocAnnualServiceLink.shareType = 'V';
            conDocAnnualServiceLink.Visibility = 'AllUsers';

            newLinks.add(conDocAnnualServiceLink);
        }
        if (newVersionOfDocs.get(BANK_TRANSFER_DOC_NAME) == null && basicDocNameToVersionData.get(BANK_TRANSFER_DOC_NAME) != null) {
            ContentVersion newBankTransferDoc = new ContentVersion();
            newBankTransferDoc.Title  = currentApp.Name + ' - ' + BANK_TRANSFER_DOC_NAME;
            newBankTransferDoc.PathOnClient  = currentApp.Name + ' - ' + BANK_TRANSFER_DOC_NAME + '.pdf';
            newBankTransferDoc.VersionData = basicDocNameToVersionData.get(BANK_TRANSFER_DOC_NAME);
            insert newBankTransferDoc;

            ContentVersion annualServiceDoc = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id =:newBankTransferDoc.Id][0];

            ContentDocumentLink conDocBankTransferLink = new ContentDocumentLink();
            conDocBankTransferLink.LinkedEntityId = recordId;
            conDocBankTransferLink.ContentDocumentId = annualServiceDoc.ContentDocumentId;
            conDocBankTransferLink.shareType = 'V';
            conDocBankTransferLink.Visibility = 'AllUsers';

            newLinks.add(conDocBankTransferLink);
        }
        if (newVersionOfDocs.get(PRIVATE_PENSION_DOC_NAME) == null && basicDocNameToVersionData.get(PRIVATE_PENSION_DOC_NAME) != null) {
            List<Object> listName = new List<Object>();
            ContentVersion newStep1Doc = new ContentVersion();
            newStep1Doc.Title  = currentApp.Name + ' - ' + PRIVATE_PENSION_DOC_NAME;
            newStep1Doc.PathOnClient  = currentApp.Name + ' - ' + PRIVATE_PENSION_DOC_NAME + '.pdf';
            newStep1Doc.VersionData = basicDocNameToVersionData.get(PRIVATE_PENSION_DOC_NAME);
            insert newStep1Doc;

            ContentVersion step1Doc = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id =:newStep1Doc.Id][0];

            ContentDocumentLink conDocStep1Link = New ContentDocumentLink();
            conDocStep1Link.LinkedEntityId = recordId;
            conDocStep1Link.ContentDocumentId = step1Doc.ContentDocumentId;
            conDocStep1Link.shareType = 'V';
            conDocStep1Link.Visibility = 'AllUsers';

            newLinks.add(conDocStep1Link);
        }
        if (!newLinks.isEmpty()) {
            insert newLinks;
        }
    }
}