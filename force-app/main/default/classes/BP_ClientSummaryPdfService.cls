public with sharing class BP_ClientSummaryPdfService {

	@AuraEnabled
	public static Id generatePdf(Id basicId) {
		List<ContentDocumentLink> doc =[
			SELECT
				ContentDocumentId,
				ContentDocument.Title
			FROM ContentDocumentLink
			WHERE LinkedEntityId = :basicId AND
					ContentDocument.Title LIKE '%Summary%' AND
					(NOT ContentDocument.Title LIKE '%completed%')
			ORDER BY ContentDocument.CreatedDate DESC
		];

		PageReference pdfPage = Page.BP_Client_Summary;

		pdfPage.getParameters().put(
			'id',
			basicId
		);

		Blob pdfBlob;

		if (Test.isRunningTest()) {

			pdfBlob = Blob.valueOf('TEST PDF');

		} else {

			pdfBlob = pdfPage.getContentAsPDF();

		}
		if (doc.size() != 0) {
			ContentVersion cv = new ContentVersion(
				ContentDocumentId = doc[0].ContentDocumentId,
				PathOnClient = 'ClientSummary.pdf',
				VersionData = pdfBlob
			);
			BP_ContentVersionService.insertVersion(cv);

			return cv.ContentDocumentId;
		} else {

			ContentVersion cv = new ContentVersion(
				Title = 'Client Summary',
				PathOnClient = 'ClientSummary.pdf',
				VersionData = pdfBlob
			);

			insert cv;

			cv = [
				SELECT Id,
					ContentDocumentId
				FROM ContentVersion
				WHERE Id = :cv.Id
			];

			insert new ContentDocumentLink(
				LinkedEntityId = basicId,
				ContentDocumentId = cv.ContentDocumentId,
				ShareType = 'V',
				Visibility = 'AllUsers'
			);
			return cv.ContentDocumentId;
			
		}
	}

	@AuraEnabled
	public static Id generatePink(Id basicId) {

		Basic__c base = [
			SELECT Id, Name, First_Name__c, Last_Name__c, Current_Address_Abroad_Country__c, Current_Address_Abroad_Country_Name__c
			FROM Basic__c
			WHERE Id = :basicId
		];

		List<ContentDocumentLink> doc =[
			SELECT
				ContentDocumentId,
				ContentDocument.Title
			FROM ContentDocumentLink
			WHERE LinkedEntityId = :basicId AND
					ContentDocument.Title LIKE '%Pink%'
		];

		PageReference pdfPage = Page.BP_Pink;
		Boolean isIreland = base.Current_Address_Abroad_Country__c == 'IE'
			|| base.Current_Address_Abroad_Country_Name__c == 'Ireland';
		pdfPage.getParameters().put('country', isIreland ? 'IE' : 'OTHER');

		Blob pdfBlob;

		if (Test.isRunningTest()) {

			pdfBlob = Blob.valueOf('TEST PDF');

		} else {

			pdfBlob = pdfPage.getContentAsPDF();

		}

		if (doc.size() != 0) {
			ContentVersion cv = new ContentVersion(
				Title = base.First_Name__c + ' ' + base.Last_Name__c + '_' + base.Name + '_D2_Pink',
				ContentDocumentId = doc[0].ContentDocumentId,
				PathOnClient = base.First_Name__c + ' ' + base.Last_Name__c + '_' + base.Name + '_D2_Pink' + '.pdf',
				VersionData = pdfBlob
			);
			BP_ContentVersionService.insertVersion(cv);

			return cv.ContentDocumentId;
		} else {

			ContentVersion cv = new ContentVersion(
				Title = base.First_Name__c + ' ' + base.Last_Name__c + '_' + base.Name + '_D2_Pink',
				PathOnClient = base.First_Name__c + ' ' + base.Last_Name__c + '_' + base.Name + '_D2_Pink' + '.pdf',
				VersionData = pdfBlob
			);

			insert cv;

			cv = [
				SELECT Id,
					ContentDocumentId
				FROM ContentVersion
				WHERE Id = :cv.Id
			];

			insert new ContentDocumentLink(
				LinkedEntityId = basicId,
				ContentDocumentId = cv.ContentDocumentId,
				ShareType = 'V',
				Visibility = 'AllUsers'
			);

			return cv.ContentDocumentId;
		}
	}

	@AuraEnabled
	public static Id generateYellow(Id basicId) {

		Basic__c base = [SELECT Id, Name, First_Name__c, Last_Name__c FROM Basic__c WHERE Id = : basicId];

		List<ContentDocumentLink> doc =[
			SELECT
				ContentDocumentId,
				ContentDocument.Title
			FROM ContentDocumentLink
			WHERE LinkedEntityId = :basicId AND
					ContentDocument.Title LIKE '%Yellow%'
		];

		PageReference pdfPage = Page.BP_Yellow;

		pdfPage.getParameters().put(
			'id',
			basicId
		);


		Blob pdfBlob;

		if (Test.isRunningTest()) {

			pdfBlob = Blob.valueOf('TEST PDF');

		} else {

			pdfBlob = pdfPage.getContentAsPDF();

		}

		if (doc.size() != 0) {
			ContentVersion cv = new ContentVersion(
				Title = base.First_Name__c + ' ' + base.Last_Name__c + '_' + base.Name + '_D1_Yellow',
				ContentDocumentId = doc[0].ContentDocumentId,
				PathOnClient = base.First_Name__c + ' ' + base.Last_Name__c + '_' + base.Name + '_D1_Yellow' + '.pdf',
				VersionData = pdfBlob
			);
			BP_ContentVersionService.insertVersion(cv);

			return cv.ContentDocumentId;
		} else {

			ContentVersion cv = new ContentVersion(
				Title = base.First_Name__c + ' ' + base.Last_Name__c + '_' + base.Name + '_D1_Yellow',
				PathOnClient = base.First_Name__c + ' ' + base.Last_Name__c + '_' + base.Name + '_D1_Yellow' + '.pdf',
				VersionData = pdfBlob
			);

			insert cv;

			cv = [
				SELECT Id,
					ContentDocumentId
				FROM ContentVersion
				WHERE Id = :cv.Id
			];

			insert new ContentDocumentLink(
				LinkedEntityId = basicId,
				ContentDocumentId = cv.ContentDocumentId,
				ShareType = 'V',
				Visibility = 'AllUsers'
			);

			return cv.ContentDocumentId;
		}
	}

	@AuraEnabled
	public static Id generateNotes(Id basicId) {

		Basic__c base = [SELECT Id, Name, First_Name__c, Last_Name__c FROM Basic__c WHERE Id = : basicId];

		StaticResource resource = [
		SELECT Id, Name, Body
		FROM StaticResource
		WHERE Name = :'IPC_1394_Notes'
		LIMIT 1
	];

		List<ContentDocumentLink> doc =[
			SELECT
				ContentDocumentId,
				ContentDocument.Title
			FROM ContentDocumentLink
			WHERE LinkedEntityId = :basicId AND
					ContentDocument.Title LIKE '%PC1394_Payment_Notes%'
		];

		Blob pdfBlob;

		if (Test.isRunningTest()) {

			pdfBlob = Blob.valueOf('TEST PDF');

		} else {

			pdfBlob = resource.Body;

		}

		if (doc.size() != 0) {
			ContentVersion cv = new ContentVersion(
				Title = base.First_Name__c + ' ' + base.Last_Name__c + '_' + base.Name + '_D6_IPC1394_Payment_Notes',
				ContentDocumentId = doc[0].ContentDocumentId,
				PathOnClient = base.First_Name__c + ' ' + base.Last_Name__c + '_' + base.Name + '_D6_IPC1394_Payment_Notes' + '.pdf',
				VersionData = pdfBlob
			);
			BP_ContentVersionService.insertVersion(cv);

			return cv.ContentDocumentId;
		} else {

			ContentVersion cv = new ContentVersion(
				Title = base.First_Name__c + ' ' + base.Last_Name__c + '_' + base.Name + '_D6_IPC1394_Payment_Notes',
				PathOnClient = base.First_Name__c + ' ' + base.Last_Name__c + '_' + base.Name + '_D6_IPC1394_Payment_Notes' + '.pdf',
				VersionData = pdfBlob
			);

			insert cv;

			cv = [
				SELECT Id,
					ContentDocumentId
				FROM ContentVersion
				WHERE Id = :cv.Id
			];

			insert new ContentDocumentLink(
				LinkedEntityId = basicId,
				ContentDocumentId = cv.ContentDocumentId,
				ShareType = 'V',
				Visibility = 'AllUsers'
			);

			return cv.ContentDocumentId;
		}
	}

	@AuraEnabled
	public static Id generateDWP(Id basicId) {

		Basic__c base = [SELECT Id, Name, First_Name__c, Last_Name__c FROM Basic__c WHERE Id = : basicId];

		List<ContentDocumentLink> doc =[
			SELECT
				ContentDocumentId,
				ContentDocument.Title
			FROM ContentDocumentLink
			WHERE LinkedEntityId = :basicId AND
					ContentDocument.Title LIKE '%DWP_Authority%'
		];
		PageReference pdfPage = Page.BP_DWP;

		pdfPage.getParameters().put(
			'id',
			basicId
		);


		Blob pdfBlob;

		if (Test.isRunningTest()) {

			pdfBlob = Blob.valueOf('TEST PDF');

		} else {

			pdfBlob = pdfPage.getContentAsPDF();

		}

		if (doc.size() != 0) {
			ContentVersion cv = new ContentVersion(
				Title = base.First_Name__c + ' ' + base.Last_Name__c + '_' + base.Name + '_D3_DWP_Authority',
				ContentDocumentId = doc[0].ContentDocumentId,
				PathOnClient = base.First_Name__c + ' ' + base.Last_Name__c + '_' + base.Name + '_D3_DWP_Authority' + '.pdf',
				VersionData = pdfBlob
			);
			BP_ContentVersionService.insertVersion(cv);

			return cv.ContentDocumentId;
		} else {

			ContentVersion cv = new ContentVersion(
				Title = base.First_Name__c + ' ' + base.Last_Name__c + '_' + base.Name + '_D3_DWP_Authority',
				PathOnClient = base.First_Name__c + ' ' + base.Last_Name__c + '_' + base.Name + '_D3_DWP_Authority' + '.pdf',
				VersionData = pdfBlob
			);

			insert cv;

			cv = [
				SELECT Id,
					ContentDocumentId
				FROM ContentVersion
				WHERE Id = :cv.Id
			];

			insert new ContentDocumentLink(
				LinkedEntityId = basicId,
				ContentDocumentId = cv.ContentDocumentId,
				ShareType = 'V',
				Visibility = 'AllUsers'
			);

			return cv.ContentDocumentId;
		}
	}

	@AuraEnabled
	public static List<Id> generatePinkAndYellow(Id basicId) {
		List<Id> result = new List<Id>();
		result.add(generatePink(basicId));
		result.add(generateYellow(basicId));
		result.add(generateNotes(basicId));
		return result;

	}

}