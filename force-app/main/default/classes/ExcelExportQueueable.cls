public class ExcelExportQueueable implements Queueable, Database.AllowsCallouts {
	private Id exportRequestId;
	private static final Integer MAX_FILE_SIZE = 8400000;
	private static final Printing_House_SFTP__c PRINTING_HOUSE_SFTP = Printing_House_SFTP__c.getInstance();
	private static final String SFTP_CONNECTION_ENDPOINT = XtraPension_Data__c.getInstance().SFTP_Upload_File_Link__c;

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

	public ExcelExportQueueable(Id exportRequestId) {
		this.exportRequestId = exportRequestId;
	}

	public void execute(QueueableContext context) {
		try {
			doExecute();
		} catch (Exception e) {
			System.debug(LoggingLevel.ERROR,
				'ExcelExportQueueable failed: ' + e.getMessage() + '\n' + e.getStackTraceString());
			markRequest(exportRequestId, 'Error');
			throw e;
		}
	}

	private void doExecute() {
		PageReference excelPage = Page.ExcelExportPage;
		excelPage.getParameters().put('requestId', exportRequestId);

		Blob excelBlob;
		if (Test.isRunningTest()) {
			excelBlob = Blob.valueOf('Test Excel Content');
		} else {
			excelBlob = excelPage.getContent();
		}

		if (excelBlob == null || excelBlob.size() == 0) {
			System.debug(LoggingLevel.ERROR, 'Generated Excel blob is empty');
			markRequest(exportRequestId, 'Error');
			return;
		}
		if (excelBlob.size() > MAX_FILE_SIZE) {
			System.debug(LoggingLevel.ERROR,
				'Generated Excel exceeds MAX_FILE_SIZE: ' + excelBlob.size() + ' > ' + MAX_FILE_SIZE);
			markRequest(exportRequestId, 'Error');
			return;
		}

		String dateRange =
			DateTime.newInstance(Date.today().addDays(-7), Time.newInstance(0, 0, 0, 0)).format('dd-MM-yyyy') +
			' to ' +
			DateTime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0)).format('dd-MM-yyyy');
		String fileNameData = 'Week - ' + dateRange + ' - Addresses.xls';

		ContentVersion newFile = new ContentVersion();
		newFile.Title = fileNameData;
		newFile.PathOnClient = fileNameData;
		newFile.VersionData = excelBlob;
		newFile.IsMajorVersion = true;

		SFTPFile sftpFile = new SFTPFile();
		sftpFile.fileName = fileNameData;
		sftpFile.body     = EncodingUtil.base64Encode(excelBlob);

		SFTPWrapper sftpWrapper  = new SFTPWrapper();
		sftpWrapper.key          = PRINTING_HOUSE_SFTP.Key__c;
		sftpWrapper.sftpHost     = PRINTING_HOUSE_SFTP.Host__c;
		sftpWrapper.sftpPort     = PRINTING_HOUSE_SFTP.Port__c;
		sftpWrapper.sftpUserName = PRINTING_HOUSE_SFTP.UserName__c;
		sftpWrapper.sftpPassword = PRINTING_HOUSE_SFTP.Password__c;
		sftpWrapper.folderName   = PRINTING_HOUSE_SFTP.Pension_Keeper_Docs_Folder_Name__c;
		sftpWrapper.files        = new List<SFTPFile>{ sftpFile };

		HttpResponse response = uploadFileToSFTP(sftpWrapper);

		if (response != null && response.getStatusCode() == 200) {
			insert newFile;
			markRequest(exportRequestId, 'Success');
			System.debug('File uploaded successfully to SFTP.');
		} else {
			String status = response == null ? 'null response' : String.valueOf(response.getStatusCode());
			System.debug(LoggingLevel.ERROR, 'Failed to upload file to SFTP. Response Status: ' + status);
			markRequest(exportRequestId, 'Error');
		}
	}

	private static void markRequest(Id reqId, String status) {
		if (reqId == null) return;
		try {
			update new Export_Request__c(Id = reqId, Status__c = status);
		} catch (Exception e) {
			System.debug(LoggingLevel.ERROR, 'Failed to update Export_Request__c status: ' + e.getMessage());
		}
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
}