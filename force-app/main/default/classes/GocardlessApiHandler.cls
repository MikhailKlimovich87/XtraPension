public with sharing class GocardlessApiHandler {
    private static final String GOCARDLESS_API_ENDPOINT = 'callout:GoCardless_API';
    //private static final String GOCARDLESS_API_ENDPOINT = 'callout:GoCardless_API_PROD';
    
    /**
     * Main method to make API calls to GoCardless
     *
     * @param endpoint The API endpoint (e.g., 'billing_requests')
     * @param method HTTP method (GET, POST, PUT, DELETE)
     * @param params Parameters or request body
     * @param isJsonBody Whether to send body as JSON or form-urlencoded
     * @return GocardlessAPIResponseWrapper containing the response
     */
    public static GocardlessAPIResponseWrapper requestGocardlessApi(
        String endpoint,
        String method,
        Map<String, Object> params,
        Boolean isJsonBody
    ) {
        return requestGocardlessApi(endpoint, method, params, isJsonBody, null);
    }

    /**
     * Same as above; a non-blank idempotencyKey is sent as the Idempotency-Key header so that a retried
     * POST (e.g. after a timeout) returns the original resource instead of creating a duplicate.
     */
    public static GocardlessAPIResponseWrapper requestGocardlessApi(
        String endpoint,
        String method,
        Map<String, Object> params,
        Boolean isJsonBody,
        String idempotencyKey
    ) {
        HttpRequest httpRequest = new HttpRequest();
        
        // IMPORTANT: For named credentials, ensure the endpoint doesn't have double slashes
        // and correctly formats the URL
        String apiUrl = GOCARDLESS_API_ENDPOINT;
        
        // Remove any leading slash from the endpoint to avoid double slashes
        String cleanEndpoint = endpoint;
        if (cleanEndpoint != null && cleanEndpoint.startsWith('/')) {
            cleanEndpoint = cleanEndpoint.substring(1);
        }
        
        // Add the endpoint to the URL
        if (cleanEndpoint != null && !cleanEndpoint.equals('')) {
            if (!apiUrl.endsWith('/')) {
                apiUrl += '/';
            }
            apiUrl += cleanEndpoint;
        }
        
        System.debug('Full API URL: ' + apiUrl);
        
        // Handle GET parameters in query string
        if (method == 'GET' && params != null && !params.isEmpty()) {
            apiUrl += '?' + generateQueryString(params);
        }
        
        httpRequest.setEndpoint(apiUrl);
        httpRequest.setMethod(method);
        httpRequest.setHeader('Authorization', 'Bearer ' + '{!$Credential.Password}');
        
        // Always set GoCardless version header for ALL requests
        httpRequest.setHeader('GoCardless-Version', '2015-07-06');
        if (String.isNotBlank(idempotencyKey) && method == 'POST') {
            httpRequest.setHeader('Idempotency-Key', idempotencyKey);
        }
        
        // Handle request body for POST/PUT/PATCH
        if (method == 'POST' || method == 'PUT' || method == 'PATCH') {
            if (params != null && !params.isEmpty()) {
                String requestBody = '';
                if (isJsonBody) {
                    requestBody = JSON.serialize(params);
                    httpRequest.setHeader('Content-Type', 'application/json');
                } else {
                    requestBody = generateRequestBody(params);
                    httpRequest.setHeader('Content-Type', 'application/x-www-form-urlencoded');
                }
                httpRequest.setBody(requestBody);
                System.debug('Request Body: ' + requestBody);
            }
        }
        
        // Send request and handle response
        GocardlessAPIResponseWrapper resp = new GocardlessAPIResponseWrapper();
        Http http = new Http();
        
        try {
            HttpResponse httpResponse = http.send(httpRequest);
            resp.statusCode = httpResponse.getStatusCode();
            resp.responseBody = httpResponse.getBody();
            
            System.debug('Response Status Code: ' + resp.statusCode);
            System.debug('Response Body: ' + resp.responseBody);
            
            if (httpResponse.getStatusCode() >= 200 && httpResponse.getStatusCode() < 300) {
                resp.isSuccess = true;
            } else {
                resp.isSuccess = false;
                resp.errorMessage = parseErrorCodes(httpResponse.getBody());
                
                // Log the error details
                System.debug('API Error - Status: ' + resp.statusCode + ', Message: ' + resp.errorMessage);
            }
        } catch (Exception e) {
            resp.isSuccess = false;
            resp.errorMessage = 'Exception occurred: ' + e.getMessage();
            System.debug('Exception in API call: ' + e.getMessage());
        }
        
        return resp;
    }
    
    /**
     * Convenience method for creating a billing request
     *
     * @param scheme The payment scheme (e.g., 'bacs', 'sepa_core')
     * @param creditorId Optional creditor ID
     * @return GocardlessAPIResponseWrapper containing the response
     */
    public static GocardlessAPIResponseWrapper createBillingRequest(
        String scheme,
    String creditorId
    ) {
        Map<String, Object> requestBody = new Map<String, Object>();
        Map<String, Object> billingRequest = new Map<String, Object>();
        Map<String, Object> mandateRequest = new Map<String, Object>();
        
        mandateRequest.put('scheme', scheme);
        
        if (String.isNotBlank(creditorId)) {
            mandateRequest.put('creditor_id', creditorId);
        }
        
        billingRequest.put('mandate_request', mandateRequest);
        requestBody.put('billing_requests', billingRequest);
        
        return requestGocardlessApi(
            'billing_requests',
        'POST',
        requestBody,
        true // JSON body
            );
    }
    
    /**
     * Generates a query string for a GET request
     */
    private static String generateQueryString(Map<String, Object> params) {
        List<String> paramList = new List<String>();
        for (String key : params.keySet()) {
            paramList.add(key + '=' + EncodingUtil.urlEncode(String.valueOf(params.get(key)), 'UTF-8'));
        }
        return String.join(paramList, '&');
    }
    
    /**
     * Generates form-urlencoded request body
     */
    private static String generateRequestBody(Map<String, Object> params) {
        List<String> paramList = new List<String>();
        for (String key : params.keySet()) {
            paramList.add(key + '=' + EncodingUtil.urlEncode(String.valueOf(params.get(key)), 'UTF-8'));
        }
        return String.join(paramList, '&');
    }
    
    /**
     * Parses error response from GoCardless
     */
    public static String parseErrorCodes(String responseBody) {
        if (String.isBlank(responseBody)) {
            return 'Empty response body';
        }
        if (!responseBody.trim().startsWith('{')) {
            return responseBody;
        }
        try {
            Map<String, Object> responseData = (Map<String, Object>) JSON.deserializeUntyped(responseBody);

            // Check for error object
            if (responseData.containsKey('error')) {
                Map<String, Object> error = (Map<String, Object>) responseData.get('error');
                if (error.containsKey('message')) {
                    String message = String.valueOf(error.get('message'));
                    // Include error type if available
                    if (error.containsKey('type')) {
                        return String.valueOf(error.get('type')) + ': ' + message;
                    }
                    return message;
                }
            }
                                                    
            // Check for errors array
            if (responseData.containsKey('errors')) {
                List<Object> errors = (List<Object>) responseData.get('errors');
                if (!errors.isEmpty()) {
                    Map<String, Object> firstError = (Map<String, Object>) errors[0];
                    if (firstError.containsKey('message')) {
                        return String.valueOf(firstError.get('message'));
                    }
                }
            }
            return 'Unknown error occurred - Response: ' + responseBody;
        } catch (Exception e) {
            return 'Error parsing response: ' + e.getMessage() + ' - Raw: ' + responseBody;
        }
    }
                                            
    public class GocardlessAPIResponseWrapper {
        public String responseBody;
        public String errorMessage;
        public Boolean isSuccess;
        public Integer statusCode;
                                  
        public GocardlessAPIResponseWrapper() {
            this.isSuccess = false;
            this.statusCode = 0;
        }
    }
}