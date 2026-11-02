global class XtraPensionEmailServiceHandler implements Messaging.InboundEmailHandler {
	// Constants
	private static final String APPLICATION_ID_INDICATOR = 'AppID:';
	private static final String TRACKING_NUMBER_INDICATOR = 'Tracking No:';
	private static final String TRACKING_NUMBER_SEND_DATE_INDICATOR = 'Tracking No Rx\'d by Printer:';
	
	// Email template developer names
	private static final String APPEAL_TEMPLATE_NAME = 'Appeal_tracking_number_receive_message';
	private static final String REAPPLY_TEMPLATE_NAME = 'REAPPLY_Tracking_No_Email';
	private static final String CLAIM_TEMPLATE_NAME = 'BP_Submit_two_forms';
	private static final String CLAIM_POSTED_STATUS = 'Posted to DWP';
	
	// Org-wide email address
	private static final String ORG_WIDE_EMAIL = 'clients@xtrapension.com';
	
	// Cached resources
	private static OrgWideEmailAddress orgWideEmailAddress;
	private static EmailTemplate appealTemplate;
	private static EmailTemplate reapplyTemplate;
	private static EmailTemplate claimTemplate;
	
	// Inner class to hold parsed email data
	private class ParsedEmailData {
		public String applicationName;
		public String trackingNo;
		public String trackingNoSendDate;
		public String emailType;
		
		public ParsedEmailData(String applicationName, String trackingNo, String trackingNoSendDate, String emailType) {
			this.applicationName = applicationName;
			this.trackingNo = trackingNo;
			this.trackingNoSendDate = trackingNoSendDate;
			this.emailType = emailType;
		}
	}
	
	global Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {
		Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
		
		try {
			// Parse email content
			ParsedEmailData parsedData = parseEmailContent(email);
			if (parsedData == null) {
				result.success = false;
				result.message = 'Failed to parse email content';
				return result;
			}
			
			// Process based on email type
			if (parsedData.emailType == 'APPEAL') {
				return processAppealEmail(parsedData, email);
			} else if (parsedData.emailType == 'REAPPLY') {
				return processReapplyEmail(parsedData, email);
			} else if (parsedData.emailType == 'CLAIM') {
				return processClaimEmail(parsedData, email);
			} else if (parsedData.emailType == 'BIG ENVELOPE') {
				return processBigEnvelop(parsedData);
			} else if (parsedData.emailType == 'BIG ENV POSTED') {
				return processBigEnvPosted(parsedData);
			} else {
				return processStandardEmail(parsedData, email);
			}
			
		} catch (Exception e) {
			System.debug('Error processing email: ' + e.getMessage());
			result.success = false;
			result.message = 'Error processing email: ' + e.getMessage();
			return result;
		}
	}
	
	// Parse email content
	private ParsedEmailData parseEmailContent(Messaging.InboundEmail email) {
		String plainText = email.plainTextBody;
		if (String.isBlank(plainText)) {
			return null;
		}
		
		String applicationName = '';
		String trackingNo = '';
		String trackingNoSendDate = '';
		String emailType = 'STANDARD';
		
		// Parse lines
		System.debug(plainText);
		List<String> lines = plainText.split('\n');
		System.debug(lines);
		for (String line : lines) {
			if (line.contains(APPLICATION_ID_INDICATOR)) {
				applicationName = extractValue(line, APPLICATION_ID_INDICATOR);
				// Format application name
				applicationName = formatApplicationName(applicationName);
			}
			if (line.contains(TRACKING_NUMBER_INDICATOR)) {
				trackingNo = extractValue(line, TRACKING_NUMBER_INDICATOR);
			}
			if (line.contains(TRACKING_NUMBER_SEND_DATE_INDICATOR)) {
				trackingNoSendDate = extractValue(line, TRACKING_NUMBER_SEND_DATE_INDICATOR);
			}
		}
		
		// Validate application name
		if (String.isBlank(applicationName)) {
			return null;
		}
		
		// Determine email type. BIG ENVELOPE is checked before CLAIM because its subject can also carry the
		// claim number/word ("BIG ENVELOPE - CLAIM C00012") and must not be handled as a posted claim.
		String subject = email.subject;
		if (subject != null && subject.contains('APPEAL')) {
			emailType = 'APPEAL';
		} else if (subject != null && subject.contains('REAPPLY')) {
			emailType = 'REAPPLY';
		} else if (subject != null && subject.contains('BIG ENV POSTED')) {
			emailType = 'BIG ENV POSTED';
		} else if (subject != null && subject.toUpperCase().contains('BIG ENVELOPE')) {
			emailType = 'BIG ENVELOPE';
		} else if (subject != null && subject.contains('CLAIM')) {
			emailType = 'CLAIM';
		}
		
		return new ParsedEmailData(applicationName, trackingNo, trackingNoSendDate, emailType);
	}
	
	// Helper methods for parsing
	private String extractValue(String line, String indicator) {
		return line.substringAfter(indicator).trim();
	}
	
	private String formatApplicationName(String name) {
		String formatted = name.replaceAll('(\\s+)', '');
		return formatted.contains('A-00') ? formatted.replace('A-00', 'A0') : formatted;
	}
	
	// Process Appeal email
	private Messaging.InboundEmailResult processAppealEmail(ParsedEmailData data, Messaging.InboundEmail email) {
		Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
		
		List<HMRC_Appeal_Reply__c> appealReplies = [
			SELECT Id, Application__c, Application__r.Email__c, Application__r.Contact__c, Client_Attach_File_Ids__c
			FROM HMRC_Appeal_Reply__c
			WHERE Application__r.Name = :data.applicationName
			ORDER BY CreatedDate DESC
			LIMIT 1
		];
		
		if (appealReplies.isEmpty()) {
			result.success = false;
			result.message = 'Appeal application not found: ' + data.applicationName;
			return result;
		}
		
		HMRC_Appeal_Reply__c appealReply = appealReplies[0];
		appealReply.Sent_To_Client_Date__c = Date.today();
		appealReply.Status__c = 'Sent to Client';
		appealReply.Tracking_Number__c = data.trackingNo;
		update appealReply;
		
		// Send email to client
		sendClientEmail(
			appealReply.Application__r.Contact__c,
			appealReply.Application__r.Email__c,
			appealReply.Id,
			appealReply.Client_Attach_File_Ids__c,
			getAppealTemplate()
		);
		
		result.success = true;
		return result;
	}
	
	// Process Reapply email
	private Messaging.InboundEmailResult processReapplyEmail(ParsedEmailData data, Messaging.InboundEmail email) {
		Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
		
		List<Reapply__c> reapplies = [
			SELECT Name, Email__c, Application__r.Contact__c, Application__c
			FROM Reapply__c
			WHERE Name = :data.applicationName
			ORDER BY CreatedDate DESC
			LIMIT 1
		];
		
		if (reapplies.isEmpty()) {
			result.success = false;
			result.message = 'Reapply record not found: ' + data.applicationName;
			return result;
		}
		
		Reapply__c reapply = reapplies[0];
		reapply.Tracking_No_to_HMRC__c = data.trackingNo;
		reapply.Tracking_Number_Send_Date__c = Date.today();
		reapply.Tracking_No_Rx_d_by_XP__c = data.trackingNoSendDate;
		reapply.Status__c = 'Posted';
		update reapply;
		
		// Send email to client
		sendClientEmail(
			reapply.Application__r.Contact__c,
			reapply.Email__c,
			reapply.Id,
			null,
			getReapplyTemplate()
		);
		
		result.success = true;
		return result;
	}

	 // Process Claim email
	private Messaging.InboundEmailResult processClaimEmail(ParsedEmailData data, Messaging.InboundEmail email) {
		Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
		
		List<Basic__c> claims = [
			SELECT Id, Name, Email__c, Contact__c
			FROM Basic__c
			WHERE Name = :data.applicationName
			ORDER BY CreatedDate DESC
			LIMIT 1
		];

		if (claims.isEmpty()) {
			result.success = false;
			result.message = 'Claim record not found: ' + data.applicationName;
			return result;
		}

		// The posting itself is recorded first, whatever happens to the client e-mail afterwards
		Basic__c claim = new Basic__c(Id = claims[0].Id);
		if (String.isNotBlank(data.trackingNo)) {
			claim.Tracking_Number__c = data.trackingNo;
		}
		if (isStatusAvailable(CLAIM_POSTED_STATUS)) {
			claim.Status__c = CLAIM_POSTED_STATUS;
		}
		update claim;

		if(!Test.isRunningTest()) {
				Id jobId = System.enqueueJob(
					new BP_Process_ClaimEmailJob(claims[0].Contact__c,
					claims[0].Email__c,
					getClaimTemplate().Id,
					claims[0].Id)
			);
		}
		
		result.success = true;
		return result;
	}

	private Messaging.InboundEmailResult processBigEnvPosted(ParsedEmailData data) {
		Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
		List<Basic__c> claims = [
			SELECT Id
			FROM Basic__c
			WHERE Name = :data.applicationName
			ORDER BY CreatedDate DESC
			LIMIT 1
		];
		if (claims.isEmpty()) {
			result.success = false;
			result.message = 'Claim record not found: ' + data.applicationName;
			return result;
		}
		Basic__c currClaim = claims[0];
		update new Basic__c(
			Id = currClaim.Id,
			Big_Envelop_Posted_Date__c = Date.today(),
			Big_Envelop_Tracking_Number__c = data.trackingNo
		);
		result.success = true;
		return result;
	}

	private Messaging.InboundEmailResult processBigEnvelop(ParsedEmailData data) {
		Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
		List<Basic__c> claims = [
			SELECT Id
			FROM Basic__c
			WHERE Name = :data.applicationName
			ORDER BY CreatedDate DESC
			LIMIT 1
		];

		if (claims.isEmpty()) {
			result.success = false;
			result.message = 'Claim record not found: ' + data.applicationName;
			return result;
		}
		Basic__c currClaim = claims[0];
		update new Basic__c(
			Id = currClaim.Id,
			Claim_Full_Form_ZIP_for_UPLOAD__c = true
		);

		result.success = true;
		return result;
	}

	// Status__c may be a restricted picklist: only set a value that really exists
	private static Boolean isStatusAvailable(String value) {
		for (Schema.PicklistEntry entry : Basic__c.Status__c.getDescribe().getPicklistValues()) {
			if (entry.isActive() && entry.getValue() == value) {
				return true;
			}
		}
		return false;
	}
	
	// Process Standard email
	private Messaging.InboundEmailResult processStandardEmail(ParsedEmailData data, Messaging.InboundEmail email) {
		Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
		
		List<Application__c> applications = [
			SELECT Id, Name, Status__c, Amount_PH_Responses__c, Appeal_Application__c
			FROM Application__c
			WHERE Name = :data.applicationName
		];
		
		if (applications.isEmpty()) {
			result.success = false;
			result.message = 'Application not found: ' + data.applicationName;
			return result;
		}
		
		Application__c application = applications[0];
		updateApplicationWithTrackingInfo(application, data);
		
		// Create email message record
		EmailMessage emailMessage = createEmailMessage(email, application.Id);
		upsert emailMessage;
		
		result.success = true;
		return result;
	}
	
	// Update application with tracking information
	private void updateApplicationWithTrackingInfo(Application__c application, ParsedEmailData data) {
		Integer responseCount = application.Amount_PH_Responses__c != null ?
			Integer.valueOf(application.Amount_PH_Responses__c) : 0;
		
		application.Tracking_Number__c = data.trackingNo;
		application.Tracking_No_Rx_d_by_XP__c = data.trackingNoSendDate;
		
		// Set tracking date based on response count
		if (responseCount == 0) {
			application.Tracking_Number_Received_Date__c = DateTime.now();
		} else if (responseCount == 1) {
			application.Tracking_Number_Received_Date_2__c = DateTime.now();
		} else if (responseCount == 2) {
			application.Tracking_Number_Received_Date_3__c = DateTime.now();
		}
		
		// Increment response count
		application.Amount_PH_Responses__c = responseCount + 1;
		application.Status__c = 'Posted';
		
		update application;
	}
	
	// Create email message record
	private EmailMessage createEmailMessage(Messaging.InboundEmail email, Id applicationId) {
		EmailMessage emailMessage = new EmailMessage();
		emailMessage.status = '3';
		emailMessage.relatedToId = applicationId;
		emailMessage.Application__c = applicationId;
		emailMessage.fromAddress = email.fromAddress;
		emailMessage.fromName = email.fromName;
		emailMessage.Subject = email.subject;
		emailMessage.TextBody = email.plainTextBody;
		return emailMessage;
	}
	
	// Send email to client
	private void sendClientEmail(Id contactId, String emailAddress, Id whatId, String attachmentIds, EmailTemplate template) {
		if (template == null || contactId == null || String.isBlank(emailAddress)) {
			return;
		}
		
		Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
		message.setTargetObjectId(contactId);
		message.setWhatId(whatId);
		message.setTemplateId(template.Id);
		message.setUseSignature(false);
		message.setBccSender(false);
		message.setSaveAsActivity(true);
		message.setTreatTargetObjectAsRecipient(false);
		message.setToAddresses(new String[]{emailAddress});
		
		// Set org-wide email address if available
		OrgWideEmailAddress orgWide = getOrgWideEmailAddress();
		if (orgWide != null) {
			message.setOrgWideEmailAddressId(orgWide.Id);
		}
		
		// Add attachments if provided
		if (String.isNotBlank(attachmentIds)) {
			List<Id> attachmentIdList = (List<Id>)JSON.deserialize(attachmentIds, List<Id>.class);
			message.setEntityAttachments(attachmentIdList);
		}
		
		// Send email (skip during tests)
		if (!Test.isRunningTest()) {
			Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{message});
		}
	}

	// Get cached org-wide email address
	private OrgWideEmailAddress getOrgWideEmailAddress() {
		if (orgWideEmailAddress == null) {
			List<OrgWideEmailAddress> addresses = [
				SELECT Id
				FROM OrgWideEmailAddress
				WHERE Address = :ORG_WIDE_EMAIL
				WITH USER_MODE
				LIMIT 1
			];
			if (!addresses.isEmpty()) {
				orgWideEmailAddress = addresses[0];
			}
		}
		return orgWideEmailAddress;
	}
	
	// Get cached appeal template
	private EmailTemplate getAppealTemplate() {
		if (appealTemplate == null) {
			appealTemplate = getEmailTemplate(APPEAL_TEMPLATE_NAME);
		}
		return appealTemplate;
	}
	
	// Get cached reapply template
	private EmailTemplate getReapplyTemplate() {
		if (reapplyTemplate == null) {
			reapplyTemplate = getEmailTemplate(REAPPLY_TEMPLATE_NAME);
		}
		return reapplyTemplate;
	}

	// Get cached claim template
	private EmailTemplate getClaimTemplate() {
		if (claimTemplate == null) {
			claimTemplate = getEmailTemplate(CLAIM_TEMPLATE_NAME);
		}
		return claimTemplate;
	}
	
	// Get email template by developer name
	private EmailTemplate getEmailTemplate(String developerName) {
		List<EmailTemplate> templates = [
			SELECT Id
			FROM EmailTemplate
			WHERE DeveloperName = :developerName
			WITH USER_MODE
			LIMIT 1
		];
		return templates.isEmpty() ? null : templates[0];
	}
}