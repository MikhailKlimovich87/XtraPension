public class AgentAuthLetterPdfHandler {
    public Id appId{get; set;}
    private static final Integer MAX_FILE_SIZE = 8400000;
    private static final Printing_House_SFTP__c PRINTING_HOUSE_SFTP = Printing_House_SFTP__c.getInstance();
    private static final String SFTP_CONNECTION_ENDPOINT = XtraPension_Data__c.getInstance().SFTP_Upload_File_Link__c;

    public AgentAuthLetterPdfHandler(Id applicationId) {
        this.appId = applicationId;
    }

    @future(callout=true)
    public static void generateAgentAuthLetter(String appId) {
        if (appId == null) return;
        List<Application__c> apps = [
            SELECT
                Name,
                First_Name__c,
                Second_Name__c
            FROM Application__c
            WHERE Id = :appId
            LIMIT 1
        ];
        if (apps.size() == 0) {
            return;
        }
        Application__c currApp = apps[0];
        PageReference savepage ;
        savepage = Page.AgentAuthLetter;
        savepage.getParameters().put('id', appId);
        blob pdfBlob;
        if (!Test.isRunningTest()) {
            pdfBlob = savepage.getContent();
        } else {
            pdfBlob = Blob.valueOf('Test');
        }

		List<ContentDocumentLink> oldDocuments = [
            SELECT
                ContentDocument.Title,
                LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocument.Title LIKE '%AgentAuthLetter%' AND
                  LinkedEntityId = :appId
        ];
        String finalTitle = currApp.First_Name__c + '_' + currApp.Second_Name__c + '_' + currApp.Name +'_AgentAuthLetter';
        if (oldDocuments.size() != 0) {
            insert new ContentVersion (
                ContentDocumentId = oldDocuments[0].ContentDocumentId,
                VersionData = pdfBlob,
                PathOnClient = finalTitle + '.pdf'
            );
        } else {
            ContentVersion conVer = new ContentVersion();
            conVer.ContentLocation = 'S';
            conVer.PathOnClient = finalTitle + '.pdf';
            conVer.Title = finalTitle;
            conVer.VersionData = pdfBlob;
            insert conVer;

            ContentVersion conDoc = [SELECT ContentDocumentId, ContentSize FROM ContentVersion WHERE Id =:conVer.Id][0];

            ContentDocumentLink conDocLink = new ContentDocumentLink();
            conDocLink.LinkedEntityId = appId;
            conDocLink.ContentDocumentId = conDoc.ContentDocumentId;
            conDocLink.shareType = 'I';
            conDocLink.Visibility = 'AllUsers';
            insert conDocLink;
        }
    }

    @future(callout=true)
    public static void generateZipArchive(Id appId) {
        if (appId == null) {
            return;
        }
        List<ContentDocumentLink> cdls = [
            SELECT
                ContentDocumentId,
                ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :appId AND (
                  ContentDocument.Title LIKE '%64-8_ForSignature_completed' OR
                  ContentDocument.Title LIKE '%AgentAuthLetter'
                )
            ORDER BY ContentDocument.CreatedDate DESC
        ];
        Map<String, ContentDocumentLink> fileKeyWordByLink = new Map<String, ContentDocumentLink>();
        for (ContentDocumentLink link : cdls) {
            if (link.ContentDocument.Title.contains('64-8') && fileKeyWordByLink.get('64-8') == null) {
                fileKeyWordByLink.put('64-8', link);
            } else if (link.ContentDocument.Title.contains('AgentAuthLetter') && fileKeyWordByLink.get('AgentAuthLetter') == null) {
                fileKeyWordByLink.put('AgentAuthLetter', link);
            }
        }
        String errorMessage = '';
        if (fileKeyWordByLink.get('64-8') == null) {
            errorMessage += '64-8_ForSignature_completed.pdf file is missing. \n';
        }
        if (fileKeyWordByLink.get('AgentAuthLetter') == null) {
            errorMessage += 'AgentAuthLetter.pdf file is missing. \n';
        }

        if (String.isNotBlank(errorMessage)) {
            update new Application__c(
                Id = appId,
                X64_8_AgentLetter_FTP_Uploading_Error__c = errorMessage
            );
            return;
        }
        Compression.ZipWriter writer = new Compression.ZipWriter();

        Set<Id> contentDocumentIds = new Set<Id>();
        contentDocumentIds.add(fileKeyWordByLink.get('AgentAuthLetter').ContentDocumentId);
        contentDocumentIds.add(fileKeyWordByLink.get('64-8').ContentDocumentId);

        Map<String, Id> currVers = new Map<String, Id>();
        for ( ContentVersion cv : [SELECT PathOnClient, Versiondata, ContentDocument.Title, ContentDocument.FileExtension
                                   FROM ContentVersion
                                   WHERE ContentDocumentId IN :contentDocumentIds
                                   ORDER BY CreatedDate DESC]) {
            String docName = cv.ContentDocument.Title + '.' + cv.ContentDocument.FileExtension;
            if(currVers.get(docName) == null) {
                writer.addEntry(docName, cv.versiondata);
                currVers.put(docName, cv.Id);
            }
        }

        blob zipAttachment = writer.getArchive();

        List<ContentDocumentLink> zipDoc =[
            SELECT
                ContentDocumentId,
                ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :appId AND
                  ContentDocument.Title LIKE '%64-8_AgentAuth'
        ];

        List<Application__c> apps = [
            SELECT
                First_Name__c,
                Second_Name__c,
                Name
            FROM Application__c
            WHERE Id = :appId
            LIMIT 1
        ];
        if(apps.size() == 0) return;
        Application__c currentApplication = apps[0];
        String finalTitle = currentApplication.First_Name__c + '_' + currentApplication.Second_Name__c + '_' +
        currentApplication.Name + '_64-8_AgentAuth';
        if (zipDoc.size() != 0) {
            insert new ContentVersion (
                ContentDocumentId = zipDoc[0].ContentDocumentId,
                VersionData = zipAttachment,
                PathOnClient = finalTitle + '.zip'
            );
        } else {

            ContentVersion conVer = new ContentVersion();
            conVer.ContentLocation = 'S';
            conVer.PathOnClient = finalTitle + '.zip';
            conVer.Title = finalTitle;
            conVer.VersionData = zipAttachment;
            insert conVer;

            ContentVersion conDoc = [SELECT ContentDocumentId, ContentSize FROM ContentVersion WHERE Id =:conVer.Id][0];

            ContentDocumentLink conDocLink = new ContentDocumentLink();
            conDocLink.LinkedEntityId = appId;
            conDocLink.ContentDocumentId = conDoc.ContentDocumentId;
            conDocLink.shareType = 'I';
            conDocLink.Visibility = 'AllUsers';
            insert conDocLink;
        }
    }

    @future(callout=true)
    public static void sendAgentAuthZipfileToFtp(String appId) {
        if (appId == null) {
            return;
        }
        List<Application__c> apps = [
            SELECT
                First_Name__c,
                Second_Name__c,
                Name,
            (
                SELECT
                    ContentDocument.LatestPublishedVersion.VersionData,
                    ContentDocument.LatestPublishedVersion.Title,
                    ContentDocument.LatestPublishedVersion.FileExtension,
                    ContentDocument.LatestPublishedVersion.ContentSize
                FROM ContentDocumentLinks
                WHERE ContentDocument.Title LIKE '%64-8_AgentAuth'
                LIMIT 1
            )
            FROM Application__c
            WHERE Id = :appId
        ];
        if (apps.size() == 0) {
            return;
        }
        Application__c currApp = apps[0];
        if (currApp.ContentDocumentLinks.size() == 0) {
            return;
        }
        ContentVersion cv = currApp.ContentDocumentLinks[0].ContentDocument.LatestPublishedVersion;

        SFTPFile sftpFile = new SFTPFile();
        sftpFile.fileName = cv.Title + '.' + cv.FileExtension;
        sftpFile.body     = EncodingUtil.base64Encode(cv.VersionData);

        SFTPWrapper sftpWrapper  = new SFTPWrapper();
        sftpWrapper.key          = PRINTING_HOUSE_SFTP.Key__c;
        sftpWrapper.sftpHost     = PRINTING_HOUSE_SFTP.Host__c;
        sftpWrapper.sftpPort     = PRINTING_HOUSE_SFTP.Port__c;
        sftpWrapper.sftpUserName = PRINTING_HOUSE_SFTP.UserName__c;
        sftpWrapper.sftpPassword = PRINTING_HOUSE_SFTP.Password__c;
        sftpWrapper.folderName   = PRINTING_HOUSE_SFTP.X64_8_Letter_Folder__c;
        sftpWrapper.files        = new List<SFTPFile>{sftpFile};

        HttpResponse response = uploadFileToSFTP(sftpWrapper);

        if (response.getStatusCode() == 200) {
            currApp.X64_8_AgentLetter_FTP_Send_Date__c = Date.today();
        } else {
            currApp.X64_8_AgentLetter_FTP_Uploading_Error__c = response.getBody();
        }
        update currApp;
    }

    public static HttpResponse uploadFileToSFTP(SFTPWrapper sftpWrapper) {

        HttpRequest request = new HttpRequest();
        request.setEndpoint(SFTP_CONNECTION_ENDPOINT);
        request.setHeader('Content-Type', 'application/json');
        request.setMethod('POST');
        request.setTimeout(110000);
        request.setBody(JSON.serialize(sftpWrapper));
        Http http = new Http();

        return http.send(request);
    }

    public class SFTPWrapper {
        public String key;
        public String sftpHost;
        public String sftpPort;
        public String sftpUserName;
        public String sftpPassword;
        public String folderName;
        public List<SFTPFile> files;
    }

    public class SFTPFile {
        public String fileName;
        public String body;
    }
}