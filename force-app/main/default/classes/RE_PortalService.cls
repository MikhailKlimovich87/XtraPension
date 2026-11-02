@RestResource(UrlMapping='/api/v5/*')
global class RE_PortalService {
    @HttpPost
    global static void postRouter() {
        RestRequest request = RestContext.request;
        String reqURI = request.requestURI;
        RestResponse response = RestContext.response;
        String requestBody = request.requestBody != null ? request.requestBody.toString() : null;
        Map <String, String> params = request.params;
        Map<String, Object> result = new Map<String, Object>();
        
        switch on reqURI {
            when '/api/v5/find-reapply' {
                result = RE_DataHelper.findReapply(new RE_RequestWrapper.ReapplyDataWrapper(requestBody));
            }
            when '/api/v5/update-reapply' {
                result = RE_DataHelper.updateReapply(new RE_RequestWrapper.UpdateReapplyDataWrapper(requestBody));
            }
            when '/api/v5/get-application-payment-data' {
                result = RE_DataHelper.getPaymentData(new RE_RequestWrapper.ReapplyDataWrapper(requestBody));
            }
            when '/api/v5/save-payment' {
                result = RE_DataHelper.savePaymentData(new RE_RequestWrapper.PaymentDataWrapper(requestBody));
            }
            when '/api/v5/make-change' {
                result = RE_DataHelper.openEditPage(new RE_RequestWrapper.MakeChangeDataWrapper(requestBody));
            }
            when '/api/v5/create-reapply-application-records' {
                result = RE_DataHelper.createReapplyApplicationRecords(new RE_RequestWrapper.NewReapplyDataWrapper(requestBody));
            }
            when '/api/v5/get-reapply-questions' {
                result = RE_DataHelper.getReapplyQuestion(new RE_RequestWrapper.ReapplyDataWrapper(requestBody));
            }
            when '/api/v5/submit-reapply-questions' {
                result = RE_DataHelper.submitReapplyQuestions(new RE_RequestWrapper.UpdateReapplyDataWrapper(requestBody));
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