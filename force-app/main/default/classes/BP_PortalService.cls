@RestResource(UrlMapping='/api/v4/*')
global with sharing class BP_PortalService {
    @HttpPost
    global static void postRouter() {
        RestRequest request = RestContext.request;
        String reqURI = request.requestURI;
        RestResponse response = RestContext.response;
        String requestBody = request.requestBody != null ? request.requestBody.toString() : null;
        Map <String, String> params = request.params;
        Map<String, Object> result = new Map<String, Object>();
   
        switch on reqURI {
            when '/api/v4/application/create' {
                result = BP_PortalApplicationHelper.createApplication(new BP_RequestWrappers.ApplicationCreateDataWrapper(requestBody));
            } when '/api/v4/application/details' {
                result = BP_PortalApplicationHelper.getApplicationDetail(new BP_RequestWrappers.ApplicationDetailsDataWrapper(requestBody));
            } when '/api/v4/application/details-update' {
                result = BP_PortalApplicationHelper.updateApplicationDetails(new BP_RequestWrappers.ApplicationDetailsDataWrapper(requestBody));
            } when '/api/v4/application/fill-signature' {
                result = BP_PortalApplicationHelper.getApplicationFill(new BP_RequestWrappers.ApplicationDetailsDataWrapper(requestBody));
            } when '/api/v4/application/fill-2-with-signature' {
                result = BP_PortalApplicationHelper.getApplicationFill(new BP_RequestWrappers.ApplicationDetailsDataWrapper(requestBody));
            } when '/api/v4/application/fill-2' {
                result = BP_PortalApplicationHelper.getApplicationFill(new BP_RequestWrappers.ApplicationDetailsDataWrapper(requestBody));
            } when '/api/v4/application/details-short' {
                result = BP_PortalApplicationHelper.getApplicationEnvelopeFill(new BP_RequestWrappers.ShortApplicationDataWrapper(requestBody));
            } when '/api/v4/application/details-short-update' {
                result = BP_PortalApplicationHelper.updateApplicationDetailsEnvelope(new BP_RequestWrappers.ShortApplicationDataWrapper(requestBody));
            } when '/api/v4/application/bank-validation' {
                result = BP_PortalApplicationHelper.validateBank(new BP_RequestWrappers.ApplicationDetailsDataWrapper(requestBody));
            } when else {
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