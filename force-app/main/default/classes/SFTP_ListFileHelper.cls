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

		if (response == null || response.getStatusCode() != 200) {
			System.debug(LoggingLevel.ERROR,
				'SFTP returned ' + (response == null ? 'null response' : response.getStatusCode() + ': ' + response.getBody()));
			return results;
		}

		FilesDataWrapper dataWrapper;
		try {
			dataWrapper = (FilesDataWrapper) JSON.deserialize(response.getBody(), FilesDataWrapper.class);
		} catch (Exception e) {
			System.debug(LoggingLevel.ERROR, 'Failed to parse SFTP response: ' + e.getMessage());
			return results;
		}

		if (dataWrapper == null
			|| dataWrapper.status != 'Success'
			|| dataWrapper.files == null
			|| dataWrapper.files.isEmpty()) {
			System.debug(LoggingLevel.ERROR, 'SFTP response not successful or empty files list');
			return results;
		}

		for (FileWrapper file : dataWrapper.files) {
			if (file == null || String.isBlank(file.name)) continue;
			if (file.name.contains('Processed By WDM')) continue;
			String applicationName = getApplicationName(file.name);
			if (String.isNotBlank(applicationName)) {
				results.add(applicationName.trim());
			}
		}

		System.debug('results ==== ' + results.size());

		List<String> uniqueNames = new List<String>();
		Set<String> seen = new Set<String>();
		for (String name : results) {
			if (seen.add(name)) uniqueNames.add(name);
		}

		if (uniqueNames.isEmpty()) {
			System.debug(LoggingLevel.WARN, 'No matching application names found on SFTP');
			return results;
		}

		List<Application__c> currentApps = [
			SELECT Id, Name, Email__c
			FROM Application__c
			WHERE Name IN :uniqueNames
		];

		Map<String, Application__c> appByName = new Map<String, Application__c>();
		for (Application__c app : currentApps) {
			appByName.put(app.Name, app);
		}

		List<String> appIds = new List<String>();
		// Preserve original SFTP order
		for (String appName : uniqueNames) {
			if (appByName.containsKey(appName)) {
				appIds.add(appByName.get(appName).Id);
			}
		}

		if (appIds.isEmpty()) {
			System.debug(LoggingLevel.WARN, 'No matching Application__c records found; skipping export');
			return results;
		}

		Export_Request__c exportReq = new Export_Request__c(
			Application_Ids__c = String.join(appIds, ',')
		);
		insert exportReq;

		System.enqueueJob(new ExcelExportQueueable(exportReq.Id));

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
		public String status { get; set; }
		public List<FileWrapper> files { get; set; }
	}

	public class FileWrapper {
		public String name { get; set; }
	}

	private static String getApplicationName(String fileName) {
		if (String.isBlank(fileName)) return null;

		String nameWithoutExt = fileName;
		if (nameWithoutExt.toLowerCase().endsWith('.pdf')) {
			nameWithoutExt = nameWithoutExt.substring(0, nameWithoutExt.length() - 4);
		}

		Integer keywordIndex = nameWithoutExt.indexOf(KEYWORD);
		if (keywordIndex <= 0) return null;

		String beforeKeyword = nameWithoutExt.substring(0, keywordIndex);
		List<String> parts = beforeKeyword.split('_');
		if (parts.isEmpty()) return null;

		String candidate = parts[parts.size() - 1];
		return String.isBlank(candidate) ? null : candidate;
	}
}