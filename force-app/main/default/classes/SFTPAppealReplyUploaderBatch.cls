public class SFTPAppealReplyUploaderBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {
    // Callout heap is 6MB sync / 12MB async. Base64 inflates ~33%, and the
    // JSON envelope adds overhead. Keep raw limit well below the callout cap.
    private static final Integer MAX_FILE_SIZE = 3000000; // ~3MB raw (~4MB base64)

    private static final Printing_House_SFTP__c PRINTING_HOUSE_SFTP =
        Printing_House_SFTP__c.getInstance();
    private static final String SFTP_CONNECTION_ENDPOINT =
        XtraPension_Data__c.getInstance().SFTP_Upload_File_Link__c;

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

    public class SFTPUploadException extends Exception {}

    // ---------------------------------------------------------------------
    // start(): only query lightweight fields. NO VersionData, NO children
    // with blobs. This keeps the QueryLocator cursor tiny.
    // ---------------------------------------------------------------------
    public Database.QueryLocator start(Database.BatchableContext BC) {
        return Database.getQueryLocator([
            SELECT Id
            FROM HMRC_Appeal_Reply__c
            WHERE Status__c = 'New'
              AND Sent_To_HMRC_Date__c = NULL
              AND Application__r.Status__c = 'HMRC Appeal'
            LIMIT 1
        ]);
    }

    // ---------------------------------------------------------------------
    // execute(): re-query the single reply with children metadata only
    // (no VersionData). VersionData is fetched per file inside sendFile().
    // ---------------------------------------------------------------------
    public void execute(Database.BatchableContext BC, List<HMRC_Appeal_Reply__c> scope) {
        if (scope.isEmpty()) {
            return;
        }

        Id replyId = scope[0].Id;

        HMRC_Appeal_Reply__c currReply = [
            SELECT Id,
                   Status__c,
                   Error_Message__c,
                   Application__r.First_Name__c,
                   Application__r.Second_Name__c,
                   Application__r.Name,
                   (
                       SELECT Id,
                              ContentDocumentId,
                              ContentDocument.LatestPublishedVersionId,
                              ContentDocument.LatestPublishedVersion.Title,
                              ContentDocument.LatestPublishedVersion.FileExtension,
                              ContentDocument.LatestPublishedVersion.ContentSize
                       FROM ContentDocumentLinks
                   )
            FROM HMRC_Appeal_Reply__c
            WHERE Id = :replyId
            LIMIT 1
        ];

        if (currReply.ContentDocumentLinks.isEmpty()) {
            return;
        }

        // Map used to track which link got which REPLY number.
        Map<String, Id> replyTypeByLinkId = new Map<String, Id>();
        Set<Id> usedLinkIds = new Set<Id>();

        // -------- First pass: find the "REPLY1" candidate --------
        for (ContentDocumentLink link : currReply.ContentDocumentLinks) {
            ContentVersion cv = link.ContentDocument.LatestPublishedVersion;
            String title = cv.Title == null ? '' : cv.Title;

            if (title.contains('REPLY')
                && !title.contains('UPLOAD')
                && (
                    title.contains('EU_Residency_Letter')
                    || title.contains('Reply_to_EU_C2_C3_Rejection')
                    || title.contains('Class_3_Appeal_Despite_3_Years')
                    || title.contains('Bad_Error_In_C2_Decision')
                    || title.contains('No_Shortfall_Table_Provided')
                    || title.contains('FurtherInformation')
                    || (title.contains('Missing_Correspondence')
                        && title.contains('CF83_NOT_Received_letter_again'))
                    || title.contains('Late_Payment_Appeal')
                    || title.contains('Higher_Level_Stage2_Appeal_Statutory_Review')
                    || title.contains('DWP/HMRC_C2_Rejection')
                )
            ) {
                String fileName = buildFileName(currReply, 'REPLY1', cv.FileExtension);

                try {
                    HttpResponse response = sendFile(fileName, cv.Id);
                    if (response.getStatusCode() != 200) {
                        currReply.Error_Message__c = truncate(response.getBody());
                        currReply.Status__c = 'Failed';
                    } else {
                        replyTypeByLinkId.put('REPLY1', link.Id);
                        usedLinkIds.add(link.Id);
                    }
                } catch (Exception e) {
                    currReply.Error_Message__c = truncate(e.getMessage());
                    currReply.Status__c = 'Failed';
                }
                break; // only one REPLY1
            }
        }

        if (currReply.Status__c == 'Failed') {
            update currReply;
            return;
        }

        // -------- Second pass: upload the remaining files as REPLY2, REPLY3, ... --------
        for (ContentDocumentLink link : currReply.ContentDocumentLinks) {
            if (usedLinkIds.contains(link.Id)) {
                continue;
            }

            ContentVersion cv = link.ContentDocument.LatestPublishedVersion;
            Integer numberOfReplies = replyTypeByLinkId.size() + 1;
            String fileName = buildFileName(
                currReply,
                'REPLY' + numberOfReplies,
                cv.FileExtension
            );

            try {
                HttpResponse response = sendFile(fileName, cv.Id);
                if (response.getStatusCode() != 200) {
                    currReply.Error_Message__c = truncate(response.getBody());
                    currReply.Status__c = 'Failed';
                    break;
                }
                replyTypeByLinkId.put('REPLY' + numberOfReplies, link.Id);
                usedLinkIds.add(link.Id);
            } catch (Exception e) {
                currReply.Error_Message__c = truncate(e.getMessage());
                currReply.Status__c = 'Failed';
                break;
            }
        }

        if (currReply.Status__c != 'Failed') {
            currReply.Sent_To_HMRC_Date__c = Date.today();
            currReply.Status__c = 'Sent to HMRC';
        }
        update currReply;
    }

    public void finish(Database.BatchableContext BC) {
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    private static String buildFileName(
        HMRC_Appeal_Reply__c reply,
        String replyLabel,
        String extension
    ) {
        String ext = String.isBlank(extension) ? 'pdf' : extension;
        return reply.Application__r.First_Name__c + '_'
            + reply.Application__r.Second_Name__c + '_'
            + reply.Application__r.Name + '_'
            + replyLabel + '.' + ext;
    }

    /**
     * Fetches VersionData for a single ContentVersion and uploads it.
     * Only one file's blob is in heap at any given time.
     */
    private static HttpResponse sendFile(String name, Id contentVersionId) {
        ContentVersion cv = [
            SELECT Id, VersionData, ContentSize
            FROM ContentVersion
            WHERE Id = :contentVersionId
            LIMIT 1
        ];

        if (cv.ContentSize != null && cv.ContentSize > MAX_FILE_SIZE) {
            throw new SFTPUploadException(
                'File "' + name + '" is ' + cv.ContentSize
                + ' bytes, exceeding max of ' + MAX_FILE_SIZE + ' bytes.'
            );
        }

        SFTPFile sftpFile = new SFTPFile();
        sftpFile.fileName = name;
        sftpFile.body     = EncodingUtil.base64Encode(cv.VersionData);

        SFTPWrapper sftpWrapper  = new SFTPWrapper();
        sftpWrapper.key          = PRINTING_HOUSE_SFTP.Key__c;
        sftpWrapper.sftpHost     = PRINTING_HOUSE_SFTP.Host__c;
        sftpWrapper.sftpPort     = PRINTING_HOUSE_SFTP.Port__c;
        sftpWrapper.sftpUserName = PRINTING_HOUSE_SFTP.UserName__c;
        sftpWrapper.sftpPassword = PRINTING_HOUSE_SFTP.Password__c;
        sftpWrapper.folderName   = PRINTING_HOUSE_SFTP.HMRC_Appeal_Reply_Folder__c;
        sftpWrapper.files        = new List<SFTPFile>{ sftpFile };

        return uploadFileToSFTP(sftpWrapper);
    }

    private static HttpResponse uploadFileToSFTP(SFTPWrapper sftpWrapper) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(SFTP_CONNECTION_ENDPOINT);
        request.setHeader('Content-Type', 'application/json');
        request.setMethod('POST');
        request.setTimeout(110000);
        request.setBody(JSON.serialize(sftpWrapper));

        Http http = new Http();
        return http.send(request);
    }

    /**
     * Error_Message__c is likely a text field with a size limit.
     * Truncate to avoid another DML error on the update.
     */
    private static String truncate(String s) {
        if (String.isBlank(s)) return s;
        Integer maxLen = 32768; // adjust to actual field length
        return s.length() > maxLen ? s.substring(0, maxLen) : s;
    }
}