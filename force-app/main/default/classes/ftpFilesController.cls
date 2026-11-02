public class ftpFilesController {
    private static final Integer MAX_FILE_SIZE = 8400000;
    private static final Printing_House_SFTP__c PRINTING_HOUSE_SFTP = Printing_House_SFTP__c.getInstance();
    private static final String SFTP_CONNECTION_ENDPOINT = 'https://go.xtrapension.com/sftp/list-files';
    private static final String KEYWORD = '_Welcome_PK_Notification';

    public class SFTPWrapper {
        public String key;
        public String sftpHost;
        public String sftpPort;
        public String sftpUserName;
        public String sftpPassword;
        public String folderPath;
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getFiles() {
        List<String> results = new List<String>();
        SFTPWrapper sftpWrapper  = new SFTPWrapper();
        sftpWrapper.key          = PRINTING_HOUSE_SFTP.Key__c;
        sftpWrapper.sftpHost     = PRINTING_HOUSE_SFTP.Host__c;
        sftpWrapper.sftpPort     = PRINTING_HOUSE_SFTP.Port__c;
        sftpWrapper.sftpUserName = PRINTING_HOUSE_SFTP.UserName__c;
        sftpWrapper.sftpPassword = PRINTING_HOUSE_SFTP.Password__c;
        sftpWrapper.folderPath   = 'Pension Keeper';

        HttpResponse response = getFilesFromSFTP(sftpWrapper);
        if (response.getStatusCode() == 200) {
            FilesDataWrapper dataWrapper = (FilesDataWrapper) JSON.deserialize(response.getBody(), FilesDataWrapper.class);
            if (dataWrapper.status == 'Success') {
                System.debug('Files received from SFTP: ' + dataWrapper.files.size());
                for (FileWrapper file : dataWrapper.files) {
                    if (file.name.contains('Processed By WDM')) continue;
                    String applicationName = getApplicationName(file.name);
                    if (applicationName != null) {
                        results.add(applicationName.trim());
                        //System.debug(applicationName);
                    }
                }
                List<Application__c> currentApps = [
                    SELECT Name, Email__c
                    FROM Application__c
                    WHERE Name IN :results
                ];
                List<String> appIds = new List<String>();

                for (Application__c app : currentApps) {
                    appIds.add(app.Id);
                }

                PageReference excelPage = Page.ExcelExportPage;
                excelPage.getParameters().put('ids', String.join(appIds, ','));
                excelPage.setRedirect(false);
                //System.debug('ExcelDataBridge.recordsToExport.size() ==== ' + ExcelDataBridge.recordsToExport.size());
                // PageReference excelPage = Page.ExcelExportPage; 
                // excelPage.setRedirect(false); 
                Blob excelBlob;
                if (Test.isRunningTest()) {
                    excelBlob = Blob.valueOf('Test Excel Content'); // Fallback for Apex Unit Tests
                } else {
                    excelBlob = excelPage.getContent(); // Renders the page into a file
                }   
                ContentVersion newFile = new ContentVersion();
                newFile.Title = 'Welcome Email Report' + DateTime.now().format('yyyy-MM-dd') + '.xls';
                newFile.PathOnClient = 'WelcomeEmailReport.xls'; // Tells Windows/Mac to open with Excel
                newFile.VersionData = excelBlob; // The actual file body
                newFile.IsMajorVersion = true;
        
                insert newFile;             
            }
        }
        System.debug('Files received from SFTP: ' + results.size());

        return results;
    }

    public static HttpResponse getFilesFromSFTP(SFTPWrapper sftpWrapper) {

        HttpRequest request = new HttpRequest();
        request.setEndpoint(SFTP_CONNECTION_ENDPOINT);
        request.setHeader('Content-Type', 'application/json');
        request.setMethod('POST');
        request.setTimeout(110000);
        request.setBody(JSON.serialize(sftpWrapper));
        Http http = new Http();

        return http.send(request);
    }

    public class FilesDataWrapper {
        public String status{get; set;}
        public List<FileWrapper> files{get; set;}
    }
    
    public class FileWrapper {
        public String name{get; set;}
    }

    private static String getApplicationName(String fileName) {
        // Remove extension
        String nameWithoutExt = fileName.replace('.pdf', '');

        // Find keyword position
        Integer keywordIndex = nameWithoutExt.indexOf(KEYWORD);

        if (keywordIndex > 0) {
            // Get part before keyword
            String beforeKeyword = nameWithoutExt.substring(0, keywordIndex);

            // Split by underscore
            List<String> parts = beforeKeyword.split('_');

            // Last part is application name
            return parts[parts.size() - 1];
        }

        return null;
    }
}