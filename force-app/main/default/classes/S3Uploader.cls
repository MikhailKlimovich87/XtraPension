public class S3Uploader {

	// Store securely in Protected Custom Metadata in real projects
	private static final String REGION = 'eu-west-2';
	private static final String SERVICE = 's3';
	//private static final String BUCKET = 'amzn-s3-xtrapension';
	private static final String BUCKET = 'xtrapension-sandbox-app-files';

	@Future(callout=true)
	public static void uploadFileToS3(Id contentVersionId, String s3FileName) {
		try {
			// 1. Fetch file content and explicit MIME Type from Salesforce
			ContentVersion cv = [
				SELECT VersionData, FileType, ContentSize
				FROM ContentVersion
				WHERE Id = :contentVersionId
				LIMIT 1
			];
		
			// Prevent processing if file is empty
			if (cv.VersionData == null) {
				System.debug('Upload cancelled: ContentVersion has no body.');
				return;
			}
		
			// 2. Initialize the HTTP Request
			HttpRequest req = new HttpRequest();
			req.setMethod('PUT');
		
			// Reference Named Credential. Ensure S3 file name is URL-encoded if it contains spaces
			String encodedFileName = EncodingUtil.urlEncode(s3FileName, 'UTF-8').replace('+', '%20');
			req.setEndpoint('callout:AWS_S3/' + encodedFileName);
		
			// Match the Content-Type to prevent AWS from marking it as a generic binary blob
			req.setHeader('Content-Type', getContentTypeByFileType(cv.FileType));
		
			// Pass the binary blob natively
			req.setBodyAsBlob(cv.VersionData);
		
			// 3. Dispatch the callout
			Http http = new Http();
			HttpResponse res = http.send(req);
		
			// 4. Handle Response (S3 returns 200 OK for successful PUT requests)
			if (res.getStatusCode() == 200) {
				System.debug('Success! File uploaded safely to Amazon S3.');
			} else {
				// Log full details to diagnose ACL or permission policy errors
				System.debug('S3 Upload Failed. Status Code: ' + res.getStatusCode() + ' | Status: ' + res.getStatus());
				System.debug('Error Response Body: ' + res.getBody());
			}
		
		} catch (Exception ex) {
			System.debug('An error occurred during S3 file upload: ' + ex.getMessage() + ' at line: ' + ex.getLineNumber());
		}
	}


	// Helper method to safely assign common content types based on ContentVersion FileType
	private static String getContentTypeByFileType(String fileType) {
		switch on fileType.toUpperCase() {
			when 'PDF' { return 'application/pdf'; }
			when 'PNG' { return 'image/png'; }
			when 'JPG', 'JPEG' { return 'image/jpeg'; }
			when 'CSV' { return 'text/csv'; }
			when 'XML' { return 'application/xml'; }
			when else { return 'application/octet-stream'; }
		}
	}
}