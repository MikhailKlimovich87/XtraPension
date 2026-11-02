public class SFTP_ListFileHelper {
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

    public static List<String> getFiles() {
        List<String> results = new List<String>();
    
        if (PRINTING_HOUSE_SFTP == null 
            || String.isBlank(PRINTING_HOUSE_SFTP.Host__c)
            || String.isBlank(PRINTING_HOUSE_SFTP.Key__c)) {
            System.debug(LoggingLevel.ERROR, 'SFTP custom setting not configured');
            return results;
        }

        SFTPWrapper sftpWrapper  = new SFTPWrapper();
        sftpWrapper.key          = PRINTING_HOUSE_SFTP.Key__c;
        sftpWrapper.sftpHost     = PRINTING_HOUSE_SFTP.Host__c;
        sftpWrapper.sftpPort     = PRINTING_HOUSE_SFTP.Port__c;
        sftpWrapper.sftpUserName = PRINTING_HOUSE_SFTP.UserName__c;
        sftpWrapper.sftpPassword = PRINTING_HOUSE_SFTP.Password__c;
        sftpWrapper.folderPath   = PRINTING_HOUSE_SFTP.Pension_Keeper_Docs_Folder_Name__c;

        HttpResponse response;
        try {
            response = getFilesFromSFTP(sftpWrapper);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'SFTP callout failed: ' + e.getMessage());
            return results;
        }
        if (response.getStatusCode() != 200) {
            System.debug(LoggingLevel.ERROR, 'SFTP returned ' + response.getStatusCode() + ': ' + response.getBody());
            return results;
        }
        if (response.getStatusCode() == 200) {
            FilesDataWrapper dataWrapper = (FilesDataWrapper) JSON.deserialize(response.getBody(), FilesDataWrapper.class);
            if (dataWrapper.status == 'Success') {
                for (FileWrapper file : dataWrapper.files) {
                    if (file.name.contains('Processed By WDM')) continue;
                    String applicationName = getApplicationName(file.name);
                    if (applicationName != null) {
                        results.add(applicationName.trim());
                    }
                }
                System.debug('results ==== ' + results.size());
                List<Application__c> currentApps = [
                    SELECT Id, Name, Email__c
                    FROM Application__c
                    WHERE Name IN :results
                ];

                Map<String, Application__c> appByName =
                    new Map<String, Application__c>();

                for (Application__c app : currentApps) {
                    appByName.put(app.Name, app);
                }

                List<String> appIds = new List<String>();

                // Preserve original SFTP order
                for (String appName : results) {
                    if (appByName.containsKey(appName)) {   
                        appIds.add(appByName.get(appName).Id);
                    }
                }
                Export_Request__c exportReq = new Export_Request__c(
                    Application_Ids__c = String.join(appIds, ',')
                );

                insert exportReq;

                System.enqueueJob(
                    new ExcelExportQueueable(exportReq.Id)
                );          
            }
        }
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
        String nameWithoutExt = fileName.replace('.pdf', '');

        Integer keywordIndex = nameWithoutExt.indexOf(KEYWORD);

        if (keywordIndex > 0) {
            String beforeKeyword = nameWithoutExt.substring(0, keywordIndex);

            List<String> parts = beforeKeyword.split('_');

            return parts[parts.size() - 1];
        }

        return null;
    }
}