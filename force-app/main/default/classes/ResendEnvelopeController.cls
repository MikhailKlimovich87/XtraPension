public with sharing class ResendEnvelopeController {
    private static final Integer MAX_FILE_SIZE = 8400000;
    private static final Printing_House_SFTP__c PRINTING_HOUSE_SFTP = Printing_House_SFTP__c.getInstance();
    private static final XtraPension_Data__c SFTP_CONNECTION_DATA = XtraPension_Data__c.getInstance();

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

    @AuraEnabled
    public static String resendEnvelope(Id recordId) {
        // ---- Early validation (before try/finally so no NPE in finally) ----
        if (recordId == null) {
            throw new AuraHandledException('Error: recordId is null.');
        }
        if (PRINTING_HOUSE_SFTP == null) {
            throw new AuraHandledException('Error: Printing House SFTP custom setting is not configured.');
        }
        if (SFTP_CONNECTION_DATA == null
            || String.isBlank(SFTP_CONNECTION_DATA.BP_SFTP_Upload_File_Link__c)
            || String.isBlank(SFTP_CONNECTION_DATA.BR_X_Api_Key__c)) {
            throw new AuraHandledException('Error: SFTP connection custom setting is not configured.');
        }

        Basic__c claim = null;

        try {
            // ---- Query claim + Stage 2 file ----
            List<Basic__c> claims = [
                SELECT
                    First_Name__c,
                    Last_Name__c,
                    Name,
                    Claim_Full_Form_ZIP_for_UPLOAD__c,
                    FTP_Claim_Full_Form_Created_Send_Date__c,
                    (
                        SELECT
                            ContentDocument.LatestPublishedVersion.VersionData,
                            ContentDocument.LatestPublishedVersion.Title,
                            ContentDocument.LatestPublishedVersion.FileExtension,
                            ContentDocument.LatestPublishedVersion.ContentSize
                        FROM ContentDocumentLinks
                        WHERE ContentDocument.Title LIKE '%Stage 2%'
                        LIMIT 1
                    )
                FROM Basic__c
                WHERE Id = :recordId
                LIMIT 1
            ];

            if (claims.isEmpty()) {
                throw new AuraHandledException('No claim found with the provided recordId.');
            }
            claim = claims[0];

            if (claim.ContentDocumentLinks.isEmpty()) {
                throw new AuraHandledException('No "Stage 2" ContentDocumentLink found for the claim.');
            }

            ContentVersion cv = claim.ContentDocumentLinks[0].ContentDocument.LatestPublishedVersion;

            // ---- Size check ----
            if (cv.ContentSize > MAX_FILE_SIZE) {
                claim.FTP_Claim_Full_Form_Error__c =
                    'File size (' + cv.ContentSize + ' bytes) exceeds max allowed (' + MAX_FILE_SIZE + ' bytes).';
                claim.Claim_Full_Form_ZIP_for_UPLOAD__c = false;
                // finally block will persist
                throw new AuraHandledException(
                    'File size exceeds the maximum allowed size of ' + MAX_FILE_SIZE + ' bytes.'
                );
            }

            // ---- Build SFTP payload ----
            SFTPFile sftpFile = new SFTPFile();
            sftpFile.fileName = cv.Title + '.' + cv.FileExtension;
            sftpFile.body     = EncodingUtil.base64Encode(cv.VersionData);

            SFTPWrapper sftpWrapper    = new SFTPWrapper();
            sftpWrapper.key            = PRINTING_HOUSE_SFTP.Key__c;
            sftpWrapper.sftpHost       = PRINTING_HOUSE_SFTP.Host__c;
            sftpWrapper.sftpPort       = PRINTING_HOUSE_SFTP.Port__c;
            sftpWrapper.sftpUserName   = PRINTING_HOUSE_SFTP.UserName__c;
            sftpWrapper.sftpPassword   = PRINTING_HOUSE_SFTP.Password__c;
            sftpWrapper.folderName     = PRINTING_HOUSE_SFTP.Claim_Stage_2_Folder__c;
            sftpWrapper.files          = new List<SFTPFile>{ sftpFile };

            // ---- Call middleware ----
            HttpResponse response;
            try {
                response = uploadFileToSFTP(sftpWrapper);
            } catch (CalloutException ce) {
                claim.FTP_Claim_Full_Form_Error__c = 'Callout failed: ' + truncate(ce.getMessage(), 255);
                claim.Claim_Full_Form_ZIP_for_UPLOAD__c = false;
                throw new AuraHandledException('Callout to SFTP middleware failed: ' + ce.getMessage());
            }

            Integer statusCode = response.getStatusCode();

            if (statusCode >= 200 && statusCode < 300) {
                claim.FTP_Claim_Full_Form_Created_Send_Date__c = Date.today();
                claim.FTP_Claim_Full_Form_Error__c = null; // clear prior error on success
                claim.Claim_Full_Form_ZIP_for_UPLOAD__c = false; // mark as processed
            } else {
                String errorBody = truncate(response.getBody(), 255);
                claim.FTP_Claim_Full_Form_Error__c = errorBody;
                claim.Claim_Full_Form_ZIP_for_UPLOAD__c = false;
                throw new AuraHandledException('Error: ' + errorBody);
            }

            return 'Success: Big Envelope resent to FTP.';

        } catch (AuraHandledException ahe) {
            // Re-throw as-is — do NOT wrap again (prevents "Error: Error:" prefix)
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException('Error: ' + e.getMessage());
        } finally {
            // Only persist if we actually loaded the claim
            if (claim != null && claim.Id != null) {
                try {
                    update claim;
                } catch (DmlException dmlEx) {
                    // Don't let a DML error mask the original failure message
                    System.debug(LoggingLevel.ERROR,
                        'Failed to persist FTP status on Basic__c ' + claim.Id + ': ' + dmlEx.getMessage());
                }
            }
        }
    }

    private static HttpResponse uploadFileToSFTP(SFTPWrapper sftpWrapper) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(SFTP_CONNECTION_DATA.BP_SFTP_Upload_File_Link__c);
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('X-API-KEY', SFTP_CONNECTION_DATA.BR_X_Api_Key__c);
        request.setMethod('POST');
        request.setTimeout(110000);
        request.setBody(JSON.serialize(sftpWrapper));

        Http http = new Http();
        return http.send(request);
    }

    private static String truncate(String s, Integer maxLen) {
        if (String.isBlank(s)) return '';
        return s.length() > maxLen ? s.substring(0, maxLen) : s;
    }
}