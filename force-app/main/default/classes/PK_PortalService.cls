@RestResource(UrlMapping='/api/v3/*')
global with sharing class PK_PortalService {

    @HttpPost
    global static void postRouter() {
        RestRequest request = RestContext.request;
        String reqURI = request.requestURI;
        RestResponse response = RestContext.response;
        String requestBody = request.requestBody != null ? request.requestBody.toString() : null;
        Map <String, String> params = request.params;
        Map<String, Object> result = new Map<String, Object>();

        switch on reqURI {
            when '/api/v3/find-application' {
                result = PK_PortalSignUpHelper.findApplication(new PK_RequestWrappers.ApplicationDataWrapper(requestBody));
            }
            // Auth
            when '/api/v3/auth/login' {
                result = PK_PortalAuthHelper.login(new PK_RequestWrappers.LoginDataWrapper(requestBody));
            }
            when '/api/v3/auth/forgot-password' {
                result = PK_PortalAuthHelper.forgotPassword(new PK_RequestWrappers.ApplicationDataWrapper(requestBody));
            }
            // Documents
            when '/api/v3/documents/get-documents' {
                result = PK_PortalDocumentHelper.getDocumentsFromRecord(new PK_RequestWrappers.GetDocumentsDataWrapper(requestBody));
            }
            when '/api/v3/documents/upload-document' {
                result = PK_PortalDocumentHelper.uploadFileToRecord(new PK_RequestWrappers.UploadDocumentDataWrapper(requestBody));
            }
            when '/api/v3/documents/delete-document' {
                result = PK_PortalDocumentHelper.deleteFileFromRecord(new PK_RequestWrappers.GetDocumentDataWrapper(requestBody));
            }
            when '/api/v3/documents/view-document' {
                result = PK_PortalDocumentHelper.getFileBase64(new PK_RequestWrappers.GetDocumentDataWrapper(requestBody));
            }
            //Application
            when '/api/v3/create-application' {
                result = PK_PortalApplicationHelper.createApplication(new PK_RequestWrappers.ApplicationDetailsDataWrapper(requestBody));
            }
            when '/api/v3/application/create-pk-payment' {
                result = PK_PortalApplicationHelper.createRegistrationPayment(new PK_RequestWrappers.PaymentDataWrapper(requestBody));
            }
            when '/api/v3/application/update-payment-method-after-registration' {
                result = PK_PortalApplicationHelper.updatePaymentMethodAfterReqistration(new PK_RequestWrappers.PaymentDataWrapper(requestBody));
            }
            when '/api/v3/application/update-payment-method-billing-page' {
                result = PK_PortalApplicationHelper.updatePaymentMethod(new PK_RequestWrappers.PaymentDataWrapper(requestBody));
            }
            when '/api/v3/application/details' {
                result = PK_PortalApplicationHelper.getApplicationDetail(new PK_RequestWrappers.ApplicationDetailsDataWrapper(requestBody));
            }
            when '/api/v3/application/details-update' {
                result = PK_PortalApplicationHelper.updateApplicationDetails(new PK_RequestWrappers.PortalApplicationDetailsDataWrapper(requestBody));
            }
            //FAQ
            when '/api/v3/application/faq' {
                result = PK_PortalFaqHelper.getFaq();
            }
            when '/api/v3/application/latest-comments' {
                result = PK_PortalApplicationHelper.getLatestComments(new PK_RequestWrappers.ApplicationDetailsDataWrapper(requestBody));
            }
            when '/api/v3/application/get-latest-comment' {
                result = PK_PortalApplicationHelper.getEmailMessage(new PK_RequestWrappers.EmailMessageDataWrapper(requestBody));
            }
            when '/api/v3/documents/get-attachment' {
                result = PK_PortalApplicationHelper.getAttachment(new PK_RequestWrappers.AttachmentDataWrapper(requestBody));
            }
            when '/api/v3/application/overview' {
                result = PK_PortalApplicationHelper.getApplicationOverview(new PK_RequestWrappers.ApplicationDetailsDataWrapper(requestBody));
            }
            when '/api/v3/application/create-notes' {
                result = PK_PortalApplicationHelper.createContentNotes(new PK_RequestWrappers.CreateNotesDataWrapper(requestBody));
            }
            when '/api/v3/application/init-check-your-entitlement' {
                result = PK_PortalCheckYourEntitlementHelper.getCheckYourEntitlementData(new PK_RequestWrappers.ApplicationDetailsDataWrapper(requestBody));
            }
            when '/api/v3/application/save-tax-year-allocation' {
                result = PK_PortalCheckYourEntitlementHelper.saveTaxYearAllocations(new PK_RequestWrappers.SaveTaxYearWrapper(requestBody));
            }
            when '/api/v3/application/save-request-check' {
                result = PK_PortalCheckYourEntitlementHelper.saveRequestCheck(new PK_RequestWrappers.RequestCheckWrapper(requestBody));
            }
            when '/api/v3/application/get-request-check' {
                result = PK_PortalCheckYourEntitlementHelper.getRequestCheck(new PK_RequestWrappers.RequestCheckWrapper(requestBody));
            }
            when '/api/v3/application/edit-extra-years' {
                result = PK_PortalCheckYourEntitlementHelper.editExtraYears(new PK_RequestWrappers.EditExtraYearsWrapper(requestBody));
            }
            when '/api/v3/application/get-receipt' {
                result = PK_PortalBillingHelper.getReceipt(new PK_RequestWrappers.RecordDataWrapper(requestBody));
            }
            when '/api/v3/application/billing-info' {
                result = PK_PortalBillingHelper.getBillingInfo(new PK_RequestWrappers.RecordDataWrapper(requestBody));
            }
            when '/api/v3/application/tick-last-entitlement-option' {
                result = PK_PortalCheckYourEntitlementHelper.tickEntitlementOption(new PK_RequestWrappers.RecordDataWrapper(requestBody));
            }
            when '/api/v3/application/get-pk-application' {
                result = PK_PortalApplicationHelper.getPkApplication(new PK_RequestWrappers.RecordDataWrapper(requestBody));
            }
            when '/api/v3/application/check-application-before-payment' {
                result = PK_PortalApplicationHelper.checkExistingApplication(new PK_RequestWrappers.ExistApplicationDataWrapper(requestBody));
            }
            when '/api/v3/application/save-pk-application' {
                Map<String, Object> wrapper = (Map<String, Object>) JSON.deserializeUntyped(requestBody.replaceAll('""', 'null'));
                result = PK_PortalApplicationHelper.updatePkApplication(new PK_RequestWrappers.PensionKeeperApplicationDataWrapper(JSON.serializePretty(wrapper.get('application'))));
                if (result.get('status') == 'success') {
                    result = PK_PortalApplicationHelper.savePkUploadedFile(new PK_RequestWrappers.UploadDocumentDataWrapper(JSON.serializePretty(wrapper.get('document'))));
                }
            }
            when else {
                result.put('status', 'error');
                result.put('message', 'Invalid endpoint');
            }
        }

        if (result.get('status') == 'success') {
            response.statusCode = 200;
        } else {
            response.statusCode = 400;
        }

        response.responseBody = Blob.valueOf(JSON.serialize(result));
    }

}