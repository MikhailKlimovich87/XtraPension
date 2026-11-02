public with sharing class PK_PortalUtils {
    public static final String ORG_WIDE_EMAIL_ADDRESS = 'keeper@xtrapension.com';
    public static final String PK_REGISTRATION_EMAIL_TEMPLATE_NAME = 'Welcome Pension Keeper Template';
    public static final String PK_COUPLES_SUPPORT_EMAIL_ADDRESS = 'pk-couples-aaaatak2cmlggloq2odzz4gy5m@xtrapensionworkspace.slack.com';
    public static final String PK_CHANGE_ADDRESS_EMAIL_ADDRESS = 'monica@xtrapension.com';

    public static List<Application__c> getActiveAppPortalUser(PK_RequestWrappers.ApplicationDataWrapper wrapper) {
        List<Application__c> activePortalApps = new List<Application__c>();
        if (wrapper.applicationNumber != null) {
            activePortalApps = [
                    SELECT Id
                    FROM Application__c
                    WHERE Name = :wrapper.applicationNumber AND
                          PK_Portal_User_Active__c = true AND
                          PK_Portal_User_PW__c != null
            ];
        }
        return activePortalApps;
    }

    public static List<Application__c> getExistingApplication(String email) {
        List<Application__c> existingApps = new List<Application__c>();
        if (email != null) {
            existingApps = [
                SELECT
                    Id,
                    Name
                FROM Application__c
                WHERE Email__c = :email 
            ];
        }
        return existingApps;
    }

    public static List<Application__c> getActiveAppPortalUser(PK_RequestWrappers.LoginDataWrapper wrapper) {
        List<Application__c> activePortalApps = new List<Application__c>();
        if (wrapper.password != null && wrapper.applicationNumber != null) {
            activePortalApps = [
                SELECT
                    Id,
                    Name,
                    Salutation__c,
                    PK_Portal_User_PW__c,
                    First_Name__c,
                    Second_Name__c,
                    Email__c,
                    Full_Maiden_Previous_Name__c,
                    Date_Of_Birth__c,
                    National_Insurance_Number__c,
                    Private_UK_Pension__c,
                    Current_Occupation__c,
                    Related_Contact_Phone__c,
                    Current_Address_Abroad__City__s,
                    Current_Address_Abroad__CountryCode__s,
                    toLabel(Current_Address_Abroad__CountryCode__s) CountryCode,
                    Current_Address_Abroad__PostalCode__s,
                    toLabel(Current_Address_Abroad__StateCode__s),
                    Current_Address_Abroad__Street__s
                FROM Application__c
                WHERE Name = :wrapper.applicationNumber AND
                      PK_Portal_User_Active__c = true AND
                      PK_Portal_User_PW__c = :wrapper.password
            ];
        }
        return activePortalApps;
    }

    public static List<Application__c> getApplication(String appId) {
        List<Application__c> appsData = new List<Application__c>();
        if (appId != null) {
            appsData = [
                SELECT
                    Id,
                    Salutation__c,
                    Name,
                    PK_Portal_User_PW__c,
                    First_Name__c,
                    Second_Name__c,
                    Email__c,
                    Full_Maiden_Previous_Name__c,
                    Date_Of_Birth__c,
                    National_Insurance_Number__c,
                    Private_UK_Pension__c,
                    Current_Occupation__c,
                    Current_Address_Abroad__City__s,
                    Current_Address_Abroad__CountryCode__s,
                    toLabel(Current_Address_Abroad__CountryCode__s) CountryCode,
                    Current_Address_Abroad__PostalCode__s,
                    toLabel(Current_Address_Abroad__StateCode__s),
                    Current_Address_Abroad__Street__s,
                    CurrencyIsoCode,
                    Pension_Age__c,
                    Years_Of_Work_In_The_UK__c,
                    Entitlement__c,
                    Tax_Year_Allocation__c,
                    Full_Entitlement__c,
                    Number_of_Tick_Task_Year__c,
                    PK_Extra_Years__c,
                    Years_To_Buy__c,
                    Projection__c,
                    PK_Registration_Date__c,
                    PK_Amount__c,
                    Stripe_Customer_Id__c,
                    Payment_Method__c,
                    Stripe_Transaction_Id__c,
                    Contact__c,
                    Related_Contact_Phone__c,
                    PK_Billing_Plan__c,
                    Current_Customer_Id__c
                FROM Application__c
                WHERE Id = :appId
            ];
        }
        return appsData;
    }

    public static String getReceipt(String paymentId) {
        String receiptBody;
        if (paymentId != null) {
            List<Payment__c> payments = [
                SELECT
                    Id,
                        (SELECT Id,
                            (SELECT HtmlBody
                             FROM Emails
                             LIMIT 1)
                         FROM Receipts__r
                         LIMIT 1)
                FROM Payment__c
                WHERE Id = :paymentId
            ];
            receiptBody = payments.size() > 0 && payments[0].Receipts__r.size() > 0 && payments[0].Receipts__r[0].Emails.size() > 0
                            ? payments[0].Receipts__r[0].Emails[0].HtmlBody
                            : '';
        }
        return receiptBody;
    }

    public static List<Payment__c> getPayment(String appId) {
        List<Payment__c> payments = new List<Payment__c>();
        if (appId != null) {
            payments = [
                SELECT
                    Id,
                    Payment_Date__c,
                    Amount__c,
                    CurrencyIsoCode
                FROM Payment__c
                WHERE Application__c = :appId AND Status__c = 'Paid'

            ];
        }
        return payments;
    }

    public static PK_Request_Check__c getRequestCheck(String appId) {
        PK_Request_Check__c requestsData;
        if (appId != null) {
            List<PK_Request_Check__c> requests = [
                SELECT
                    PK_Requested_Check_Date__c,
                    PK_Amount_Paid__c,
                    PK_Payment_Received__c
                FROM PK_Request_Check__c
                WHERE Application__c = :appId AND
                      PK_Payment_Received__c != null
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (requests.size() > 0) {
                requestsData = requests[0];
            }
        }
        return requestsData;
    }

    // Documents
    public static List<ContentDocument> getTemplateDocuments(PK_RequestWrappers.GetDocumentsDataWrapper wrapper) {
        List<Application__c> apps = [
            SELECT
                Send_to_Client_Changed_Date__c,
                Pension_Keeper_Changed_Date__c
            FROM Application__c
            WHERE Id = :wrapper.recordId
        ];
        String query =
            'SELECT Id, ' +
                  'ContentDocumentId, ' +
                  'LinkedEntityId ' +
            'FROM ContentDocumentLink ' +
            'WHERE LinkedEntityId = \'' + wrapper.recordId + '\' AND ' +
                   'ContentDocument.FileType != \'SNOTE\' AND ' +
                   '(ContentDocument.LatestPublishedVersion.Pension_Keeper__c = true OR ' +
                   'ContentDocument.Title LIKE \'%C2%\' OR ' +
                   'ContentDocument.Title LIKE \'%C3%\' OR ' +
                   'ContentDocument.Title LIKE \'%REPLY%\' OR ' +
                   'ContentDocument.Title LIKE \'%UPLOAD%\' OR ' +
                   'ContentDocument.Title LIKE \'%Next Step 1 - Pay HMRC%\' OR ' +
                   'ContentDocument.Title LIKE \'%Next Step 2 - Get Receipt%\' OR ' +
                   'ContentDocument.Title LIKE \'%Private Pensions%\' ';
            if (apps.size() > 0 && apps[0].Send_to_Client_Changed_Date__c != null) {
                query += 'OR ContentDocument.LatestPublishedVersion.CreatedDate >= ' + convertDateToString(apps[0].Send_to_Client_Changed_Date__c) + ' ';
            }
            if (apps.size() > 0 && apps[0].Pension_Keeper_Changed_Date__c != null) {
                query += 'OR ContentDocument.LatestPublishedVersion.CreatedDate >= ' + convertDateToString(apps[0].Pension_Keeper_Changed_Date__c) + ' ';
            }
        query += ') ';
        if (wrapper.docLimit != null) query += ' LIMIT ' + wrapper?.docLimit;
        List<ContentDocumentLink> contentDocumentLinks = Database.query(query);

        List<String> contentDocumentIds = new List<String>();
        for (ContentDocumentLink contentDocumentLink : contentDocumentLinks) {
            contentDocumentIds.add(contentDocumentLink.ContentDocumentId);
        }

        List<ContentDocument> returnList = new List<ContentDocument>();

        List<ContentDocument> files = [
                SELECT
                    Id,
                    Title,
                    FileType,
                    FileExtension,
                    LatestPublishedVersionId,
                    CreatedDate
                FROM ContentDocument
                WHERE Id IN :contentDocumentIds
                ORDER BY CreatedDate DESC
        ];

        returnList.addAll(files);

        return returnList;
    }

    public static List<DocumentWrapper> getDocumentWrappers(PK_RequestWrappers.GetDocumentsDataWrapper wrapper) {

        List<ContentDocument> contentDocuments = getTemplateDocuments(wrapper);
        List<String> docIds = new List<String>();

        for (ContentDocument contentDocument : contentDocuments) {
            docIds.add(contentDocument.Id);
        }

        List<ContentVersion> contentVersions = [
                SELECT
                    Id,
                    VersionData,
                    Title,
                    FileType,
                    ContentUrl,
                    ContentDocumentId,
                    ContentSize,
                    CreatedDate
                FROM ContentVersion
                WHERE ContentDocumentId IN :docIds AND
                      IsLatest = true
                ORDER BY CreatedDate DESC
        ];

        List<DocumentWrapper> documentWrappers = new List<DocumentWrapper>();

        for (ContentVersion contentVersion : contentVersions) {
            DocumentWrapper documentWrapper = new DocumentWrapper();

            documentWrapper.documentId = contentVersion.Id;
            documentWrapper.documentTitle = contentVersion.Title;
            documentWrapper.documentType = contentVersion.FileType;
            documentWrapper.documentSize = contentVersion.ContentSize;
            documentWrapper.createdDate = contentVersion.CreatedDate.format('dd/MM/yyyy');

            documentWrappers.add(documentWrapper);
        }

        return documentWrappers;
    }

    // Get Base64 Image
    public static String getImageBase64(String recordId, String title) {
        String imageBase64 = '';
        List<ContentDocumentLink> contentDocumentLinks = [
            SELECT
                Id,
                ContentDocumentId,
                ContentDocument.LatestPublishedVersionId,
                LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId AND
                  ContentDocument.Title = :title AND
                  (ContentDocument.LatestPublishedVersion.FileType = 'PNG' OR
                   ContentDocument.LatestPublishedVersion.FileType = 'JPEG' OR
                   ContentDocument.LatestPublishedVersion.FileType = 'JPG')
            ORDER BY ContentDocument.LatestPublishedVersion.CreatedDate DESC
            LIMIT 1
        ];

        Set<Id> contentDocumentIds = new Set<Id>();
        for (ContentDocumentLink contentDocumentLink : contentDocumentLinks) {
            contentDocumentIds.add(contentDocumentLink.ContentDocumentId);
        }

        List<ContentVersion> contentVersions = new List<ContentVersion>([
                SELECT
                    Id,
                    Title,
                    FileType,
                    ContentBodyId,
                    VersionData
                FROM ContentVersion
                WHERE ContentDocumentId IN :contentDocumentIds
                LIMIT 1
        ]);

        if (!contentVersions.isEmpty()) {
            if (contentVersions[0].FileType == 'PNG') {
                String base64Data = EncodingUtil.base64Encode(contentVersions[0].VersionData);
                imageBase64 = 'data:image/png;base64,' + base64Data;
            }
            if (contentVersions[0].FileType == 'JPEG') {
                String base64Data = EncodingUtil.base64Encode(contentVersions[0].VersionData);
                imageBase64 = 'data:image/jpeg;base64,' + base64Data;
            }
            if (contentVersions[0].FileType == 'JPG') {
                String base64Data = EncodingUtil.base64Encode(contentVersions[0].VersionData);
                imageBase64 = 'data:image/jpg;base64,' + base64Data;
            }
        }

        return imageBase64;
    }

    public class DocumentWrapper {
        public String documentId { get; set; }
        public String documentTitle { get; set; }
        public String documentType { get; set; }
        public Integer documentSize { get; set; }
        public String createdDate { get; set; }
    }

    public static DocumentWrapper getDocumentWrapper(String contentVersionId) {
        List<ContentVersion> contentVersions = [
                SELECT Id, Title, FileType, ContentSize, CreatedDate
                FROM ContentVersion
                WHERE Id = :contentVersionId
        ];

        DocumentWrapper documentWrapper = new DocumentWrapper();
        if (!contentVersions.isEmpty()) {
            documentWrapper.documentId = contentVersions[0].Id;
            documentWrapper.documentTitle = contentVersions[0].Title;
            documentWrapper.documentType = contentVersions[0].FileType;
            documentWrapper.documentSize = contentVersions[0].ContentSize;
            documentWrapper.createdDate = contentVersions[0].CreatedDate.format('dd/MM/yyyy');
        }

        return documentWrapper;
    }

    public static ContentVersion createContentVersion(String base64, String fileName, String fileType) {
        ContentVersion contentVersion = new ContentVersion();
        contentVersion.VersionData = EncodingUtil.base64Decode(base64);
        contentVersion.Title = fileName;
        contentVersion.PathOnClient = fileName + '.' + fileType;
        insert contentVersion;

        return contentVersion;
    }

    public static ContentDocumentLink createContentLink(String contentVersionId, String recordId) {
        if (contentVersionId == null || recordId == null) {
            return null;
        }
        ContentDocumentLink contentDocumentLink = new ContentDocumentLink();
        contentDocumentLink.ContentDocumentId = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id = :contentVersionId
        ].ContentDocumentId;
        contentDocumentLink.LinkedEntityId = recordId;
        contentDocumentLink.ShareType = 'V';

        insert contentDocumentLink;
        return contentDocumentLink;
    }

    public static List<EmailMessage> getEmailMessages(PK_RequestWrappers.ApplicationDetailsDataWrapper wrapper) {
        List<EmailMessage> emailMessages;
        if (wrapper != null) {
            List<Application__c> apps = [
                SELECT
                    Send_to_Client_Changed_Date__c,
                    Pension_Keeper_Changed_Date__c
                FROM Application__c
                WHERE Id = :wrapper.id
            ];
            String query =
                'SELECT ' +
                    'Subject, ' +
                    'HtmlBody, ' +
                    'FromAddress, ' +
                    'ToAddress, ' +
                    'CreatedDate ' +
                'FROM EmailMessage ' +
                'WHERE RelatedToId = \'' + wrapper?.id + '\' AND (Pension_Keeper__c = true ';
            if (apps.size() > 0 && apps[0].Send_to_Client_Changed_Date__c != null) {
                query += 'OR CreatedDate >= ' + convertDateToString(apps[0].Send_to_Client_Changed_Date__c) + ' ';
            }
            if (apps.size() > 0 && apps[0].Pension_Keeper_Changed_Date__c != null) {
                query += 'OR CreatedDate >= ' + convertDateToString(apps[0].Pension_Keeper_Changed_Date__c) + ' ';
            }
            query += ') ORDER BY CreatedDate DESC';
            if (wrapper?.commentsLimit != null) query += ' LIMIT ' + wrapper?.commentsLimit;
            emailMessages = Database.query(query);
        }
        return emailMessages;
    }

    public static EmailMessage getLatestComment(String messageId) {
        EmailMessage emailMessage;
        if (messageId != null) {
            List<EmailMessage> messages = [
                SELECT
                    Subject,
                    HtmlBody,
                    FromAddress,
                    ToAddress,
                    CreatedDate,
                    HasAttachment,
                    RelatedToId,
                    (SELECT
                        Id,
                        Name
                     FROM Attachments)
                FROM EmailMessage
                WHERE Id = :messageId
            ];
            emailMessage = messages.size() == 0 ? null : messages[0];
        }
        return emailMessage;
    }

    public static ContentVersion getAttachment(String attachmentId) {
        ContentVersion attachment;
        if (attachmentId != null) {
            List<ContentVersion> attachments = [
                SELECT
                    ContentDocumentId,
                    ContentDocument.Title,
                    ContentDocument.FileType,
                    ContentDocument.ContentSize,
                    VersionData,
                    CreatedDate
                FROM ContentVersion
                WHERE ContentDocumentId = :attachmentId AND
                      IsLatest = true
            ];
            attachment = attachments.size() == 0 ? null : attachments[0];
        }
        return attachment;
    }

    private static String convertDateToString(Date convertDate) {
        if (convertDate == null) {
            return '';
        }
        return DateTime.newInstance(convertDate.year(), convertDate.month(), convertDate.day()).format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    }

    public static List<Application__c> getApplicationOverview(Id appId) {
        List<Application__c> appsData = new List<Application__c>();
        if (appId != null) {
            appsData = [
                SELECT
                    PK_Date_Pension_Age_Reached__c,
                    Pension_Age__c,
                    Date_Of_Birth__c,
                    Tax_Year_Allocation__c
                FROM Application__c
                WHERE Id = :appId
            ];
        }
        return appsData;
    }

    public static Date calculatePensionDate(Date dateOfBirth) {
        if (dateOfBirth == null) {
            return null;
        }
        Date pensionDate;
        if (dateOfBirth >= Date.newInstance(1953, 12, 6) && dateOfBirth <= Date.newInstance(1954, 1, 5)) {
            pensionDate = Date.newInstance(2019, 3, 6);
        } else if (dateOfBirth >= Date.newInstance(1954, 1, 6) && dateOfBirth <= Date.newInstance(1954, 2, 5)) {
            pensionDate = Date.newInstance(2019, 5, 6);
        } else if (dateOfBirth >= Date.newInstance(1954, 2, 6) && dateOfBirth <= Date.newInstance(1954, 3, 5)) {
            pensionDate = Date.newInstance(2019, 7, 6);
        } else if (dateOfBirth >= Date.newInstance(1954, 3, 6) && dateOfBirth <= Date.newInstance(1954, 4, 5)) {
            pensionDate = Date.newInstance(2019, 9, 6);
        } else if (dateOfBirth >= Date.newInstance(1954, 4, 6) && dateOfBirth <= Date.newInstance(1954, 5, 5)) {
            pensionDate = Date.newInstance(2019, 11, 6);
        } else if (dateOfBirth >= Date.newInstance(1954, 5, 6) && dateOfBirth <= Date.newInstance(1954, 6, 5)) {
            pensionDate = Date.newInstance(2020, 1, 6);
        } else if (dateOfBirth >= Date.newInstance(1954, 6, 6) && dateOfBirth <= Date.newInstance(1954, 7, 5)) {
            pensionDate = Date.newInstance(2020, 3, 6);
        } else if (dateOfBirth >= Date.newInstance(1954, 7, 6) && dateOfBirth <= Date.newInstance(1954, 8, 5)) {
            pensionDate = Date.newInstance(2020, 5, 6);
        } else if (dateOfBirth >= Date.newInstance(1954, 8, 6) && dateOfBirth <= Date.newInstance(1954, 9, 5)) {
            pensionDate = Date.newInstance(2020, 7, 6);
        } else if (dateOfBirth >= Date.newInstance(1954, 9, 6) && dateOfBirth <= Date.newInstance(1954, 10, 5)) {
            pensionDate = Date.newInstance(2020, 9, 6);
        } else if (dateOfBirth >= Date.newInstance(1954, 10, 6) && dateOfBirth <= Date.newInstance(1960, 4, 5)) {
            pensionDate = dateOfBirth.addYears(66);
        } else if (dateOfBirth >= Date.newInstance(1960, 4, 6) && dateOfBirth <= Date.newInstance(1960, 5, 5)) {
            pensionDate = dateOfBirth.addMonths(1).addYears(66);
        } else if (dateOfBirth >= Date.newInstance(1960, 5, 6) && dateOfBirth <= Date.newInstance(1960, 6, 5)) {
            pensionDate = dateOfBirth.addMonths(2).addYears(66);
        } else if (dateOfBirth >= Date.newInstance(1960, 6, 6) && dateOfBirth <= Date.newInstance(1960, 7, 5)) {
            pensionDate = dateOfBirth.addMonths(3).addYears(66);
        } else if (dateOfBirth >= Date.newInstance(1960, 7, 6) && dateOfBirth <= Date.newInstance(1960, 8, 5)) {
            pensionDate = dateOfBirth.addMonths(4).addYears(66);
        } else if (dateOfBirth >= Date.newInstance(1960, 8, 6) && dateOfBirth <= Date.newInstance(1960, 9, 5)) {
            pensionDate = dateOfBirth.addMonths(5).addYears(66);
        } else if (dateOfBirth >= Date.newInstance(1960, 9, 6) && dateOfBirth <= Date.newInstance(1960, 10, 5)) {
            pensionDate = dateOfBirth.addMonths(6).addYears(66);
        } else if (dateOfBirth >= Date.newInstance(1960, 10, 6) && dateOfBirth <= Date.newInstance(1960, 11, 5)) {
            pensionDate = dateOfBirth.addMonths(7).addYears(66);
        } else if (dateOfBirth >= Date.newInstance(1960, 11, 6) && dateOfBirth <= Date.newInstance(1960, 12, 5)) {
            pensionDate = dateOfBirth.addMonths(8).addYears(66);
        } else if (dateOfBirth >= Date.newInstance(1960, 12, 6) && dateOfBirth <= Date.newInstance(1961, 1, 5)) {
            pensionDate = dateOfBirth.addMonths(9).addYears(66);
        } else if (dateOfBirth >= Date.newInstance(1961, 1, 6) && dateOfBirth <= Date.newInstance(1961, 2, 5)) {
            pensionDate = dateOfBirth.addMonths(10).addYears(66);
        } else if (dateOfBirth >= Date.newInstance(1961, 2, 6) && dateOfBirth <= Date.newInstance(1961, 3, 5)) {
            pensionDate = dateOfBirth.addMonths(11).addYears(66);
        } else if (dateOfBirth >= Date.newInstance(1961, 3, 6) && dateOfBirth <= Date.newInstance(1977, 4, 5)) {
            pensionDate = dateOfBirth.addYears(67);
        } else if (dateOfBirth >= Date.newInstance(1977, 4, 6) && dateOfBirth <= Date.newInstance(1977, 5, 5)) {
            pensionDate = Date.newInstance(2044, 5, 6);
        } else if (dateOfBirth >= Date.newInstance(1977, 5, 6) && dateOfBirth <= Date.newInstance(1977, 6, 5)) {
            pensionDate = Date.newInstance(2044, 7, 6);
        } else if (dateOfBirth >= Date.newInstance(1977, 6, 6) && dateOfBirth <= Date.newInstance(1977, 7, 5)) {
            pensionDate = Date.newInstance(2044, 9, 6);
        } else if (dateOfBirth >= Date.newInstance(1977, 7, 6) && dateOfBirth <= Date.newInstance(1977, 8, 5)) {
            pensionDate = Date.newInstance(2044, 11, 6);
        } else if (dateOfBirth >= Date.newInstance(1977, 8, 6) && dateOfBirth <= Date.newInstance(1977, 9, 5)) {
            pensionDate = Date.newInstance(2045, 1, 6);
        } else if (dateOfBirth >= Date.newInstance(1977, 9, 6) && dateOfBirth <= Date.newInstance(1977, 10, 5)) {
            pensionDate = Date.newInstance(2045, 3, 6);
        } else if (dateOfBirth >= Date.newInstance(1977, 10, 6) && dateOfBirth <= Date.newInstance(1977, 11, 5)) {
            pensionDate = Date.newInstance(2045, 5, 6);
        } else if (dateOfBirth >= Date.newInstance(1977, 11, 6) && dateOfBirth <= Date.newInstance(1977, 12, 5)) {
            pensionDate = Date.newInstance(2045, 7, 6);
        } else if (dateOfBirth >= Date.newInstance(1977, 12, 6) && dateOfBirth <= Date.newInstance(1978, 1, 5)) {
            pensionDate = Date.newInstance(2045, 9, 6);
        } else if (dateOfBirth >= Date.newInstance(1978, 1, 6) && dateOfBirth <= Date.newInstance(1978, 2, 5)) {
            pensionDate = Date.newInstance(2045, 11, 6);
        } else if (dateOfBirth >= Date.newInstance(1978, 2, 6) && dateOfBirth <= Date.newInstance(1978, 3, 5)) {
            pensionDate = Date.newInstance(2046, 1, 6);
        } else if (dateOfBirth >= Date.newInstance(1978, 3, 6) && dateOfBirth <= Date.newInstance(1978, 4, 5)) {
            pensionDate = Date.newInstance(2046, 3, 6);
        } else if (dateOfBirth >= Date.newInstance(1978, 4, 6)) {
            pensionDate = dateOfBirth.addYears(68);
        }
        return pensionDate;
    }

    public static String getYearsMonthsDaysBetween(Date startDate, Date endDate) {
        if (startDate == null || endDate == null) {
            return null;
        }

        Integer years = endDate.year() - startDate.year();
        Integer months = endDate.month() - startDate.month();
        Integer days = endDate.day() - startDate.day();

        // Adjust for negative days
        if (days < 0) {
            months--;
            // Get days in previous month
            Date lastDayOfMonth = Date.newInstance(endDate.year(), endDate.month(), 1).addDays(-1);
            days = days + lastDayOfMonth.day();
        }

        // Adjust for negative months
        if (months < 0) {
            years--;
            months = months + 12;
        }

        // Format the output string
        List<String> parts = new List<String>();
        if (years > 0) {
            parts.add(years + (years == 1 ? ' year' : ' years'));
        }
        if (months > 0) {
            parts.add(months + (months == 1 ? ' month' : ' months'));
        }
        if (days > 0) {
            parts.add(days + (days == 1 ? ' day' : ' days'));
        }

        if (parts.isEmpty()) {
            return '0 days';
        } else {
            return String.join(parts, ', ');
        }
    }

    public static List<Schema.PicklistEntry> getAllMultiSelectPicklistValues(String objectApiName, String fieldApiName) {
        List<Schema.PicklistEntry> picklistEntries = new List<Schema.PicklistEntry>();
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType == null) {
            return picklistEntries;
        }

        Schema.DescribeSObjectResult objectDescribe = objectType.getDescribe();
        Schema.SObjectField field = objectDescribe.fields.getMap().get(fieldApiName);

        if (field == null) {
            return picklistEntries;
        }

        Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
        picklistEntries = fieldDescribe.getPicklistValues();

        return picklistEntries;
    }

    public static void sendRegistrationEmail(Application__c app) {
        OrgWideEmailAddress[] owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :ORG_WIDE_EMAIL_ADDRESS
        ];
        List<EmailTemplate> registrationEmailTemplate = [
            SELECT
                Id
            FROM EmailTemplate
            WHERE Name = :PK_REGISTRATION_EMAIL_TEMPLATE_NAME
        ];
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setTargetObjectId(app.Contact__c);
        message.setUseSignature(false);
        message.setBccSender(false);
        message.setSaveAsActivity(true);
        message.setTreatTargetObjectAsRecipient(false);
        if (registrationEmailTemplate.size() > 0) {
            message.setTemplateID(registrationEmailTemplate[0].Id);
        }
        message.setWhatId(app.Id);
        if (owea.size() > 0) {
            message.setOrgWideEmailAddressId(owea.get(0).Id);
        }
        message.toAddresses = new String[] { app.Email__c };
        Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
        Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
    }

    public static void sendCouplesEmail(Application__c app) {
        OrgWideEmailAddress[] owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :ORG_WIDE_EMAIL_ADDRESS
        ];
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setUseSignature(false);
        message.setBccSender(false);
        message.setSaveAsActivity(true);
        message.setTreatTargetObjectAsRecipient(false);
        message.setSubject(app.Name + ' - ' + app.First_Name__c + ' ' + app.Second_Name__c + ' - COUPLE YES');
        message.setHtmlBody('<div></div>');
        message.setWhatId(app.Id);
        if (owea.size() > 0) {
            message.setOrgWideEmailAddressId(owea.get(0).Id);
        }
        message.toAddresses = new String[] { PK_COUPLES_SUPPORT_EMAIL_ADDRESS };
        Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
        Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
    }

    public static void sendChangeAddressEmail(Application__c app) {
        OrgWideEmailAddress[] owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :ORG_WIDE_EMAIL_ADDRESS
        ];
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setUseSignature(false);
        message.setBccSender(false);
        message.setSaveAsActivity(true);
        message.setTreatTargetObjectAsRecipient(false);
        message.setSubject('Tell HMRC re ' + app.Name + ' change of Address');
        message.setHtmlBody('<div></div>');
        message.setWhatId(app.Id);
        if (owea.size() > 0) {
            message.setOrgWideEmailAddressId(owea.get(0).Id);
        }
        message.toAddresses = new String[] { PK_CHANGE_ADDRESS_EMAIL_ADDRESS };
        Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
        Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
    }

    public static String getStateCodeByLabel(String countryLabel) {
        Map<String, String> mapLabelToCode = new Map<String, String>();

        Schema.DescribeFieldResult fieldResult = Application__c.Current_Address_Abroad__StateCode__s.getDescribe();
        List<Schema.PicklistEntry> values = fieldResult.getPicklistValues();

        for (Schema.PicklistEntry entry : values) {
            mapLabelToCode.put(entry.getLabel(), entry.getValue());
        }

        String stateCode = mapLabelToCode.get(countryLabel);

        if (stateCode != null) {
            return stateCode;
        } else {
            return null;
        }
    }

    public static String getContryStateName(String countryCode, String stateCode) {
        Map<String, String> statesCodeByValue = new Map<String, String>();
		List<Schema.PicklistEntry> values = Application__c.Current_Address_Abroad__StateCode__s
  					.getDescribe()
  					.getPickListValues();
		for (Schema.PicklistEntry v : values) {
    		statesCodeByValue.put(v.getValue(), v.getLabel());
		}
        String stateName = '';
        if (countryCode == 'IE') {
            stateName = CountryCodeHelper.getStateCodeByStateName(
                countryCode,
                stateCode.remove('County').trim());
        } else if(countryCode == 'AE' ||
                countryCode == 'MY' ||
                countryCode == 'ID') {
                stateName = CountryCodeHelper.getStateCodeByStateName(
                    countryCode,
                    stateCode);
        } else stateName = stateCode;
        String currentStateValue = statesCodeByValue.get(stateName);
		if (String.isBlank(currentStateValue) && String.isNotBlank(stateName)) {
		    stateName = '';
		}
        return stateName;
    }


}