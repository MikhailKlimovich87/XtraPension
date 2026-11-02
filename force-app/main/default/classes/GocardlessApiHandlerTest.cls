@IsTest
public class GocardlessApiHandlerTest {
    private class ResponseMock implements HttpCalloutMock {
        Integer statusCode = 200;
        String body = '{"ok":true}';
        HttpRequest lastRequest;

        public HttpResponse respond(HttpRequest request) {
            lastRequest = request;
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody(body);
            return response;
        }
    }

    @IsTest
    static void sendsJsonRequestToNormalizedEndpoint() {
        ResponseMock mock = new ResponseMock();
        mock.statusCode = 201;
        mock.body = '{"created":true}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        GocardlessApiHandler.GocardlessAPIResponseWrapper result =
            GocardlessApiHandler.requestGocardlessApi(
                '/customers',
                'POST',
                new Map<String, Object>{ 'customers' => new Map<String, Object>{ 'given_name' => 'John' } },
                true
            );
        Test.stopTest();

        System.assertEquals(true, result.isSuccess);
        System.assertEquals(201, result.statusCode);
        System.assertEquals('{"created":true}', result.responseBody);
        System.assertEquals('callout:GoCardless_API/customers', mock.lastRequest.getEndpoint());
        System.assertEquals('POST', mock.lastRequest.getMethod());
        System.assertEquals('Bearer {!$Credential.Password}', mock.lastRequest.getHeader('Authorization'));
        System.assertEquals('2015-07-06', mock.lastRequest.getHeader('GoCardless-Version'));
        System.assertEquals('application/json', mock.lastRequest.getHeader('Content-Type'));
        Map<String, Object> requestBody =
            (Map<String, Object>) JSON.deserializeUntyped(mock.lastRequest.getBody());
        Map<String, Object> customers = (Map<String, Object>) requestBody.get('customers');
        System.assertEquals('John', customers.get('given_name'));
    }

    @IsTest
    static void encodesFormBodiesAndGetQueryParameters() {
        ResponseMock mock = new ResponseMock();
        Test.setMock(HttpCalloutMock.class, mock);
        Map<String, Object> formParams = new Map<String, Object>{ 'description' => 'John Snow' };

        Test.startTest();
        GocardlessApiHandler.GocardlessAPIResponseWrapper formResult =
            GocardlessApiHandler.requestGocardlessApi('payments', 'POST', formParams, false);
        System.assertEquals(true, formResult.isSuccess);
        System.assertEquals('application/x-www-form-urlencoded', mock.lastRequest.getHeader('Content-Type'));
        System.assertEquals(
            'description=' + EncodingUtil.urlEncode('John Snow', 'UTF-8'),
            mock.lastRequest.getBody()
        );

        GocardlessApiHandler.GocardlessAPIResponseWrapper getResult =
            GocardlessApiHandler.requestGocardlessApi(
                '/mandates',
                'GET',
                new Map<String, Object>{ 'status' => 'active mandate' },
                false
            );
        Test.stopTest();

        System.assertEquals(true, getResult.isSuccess);
        System.assertEquals('callout:GoCardless_API/mandates?status=' + EncodingUtil.urlEncode('active mandate', 'UTF-8'), mock.lastRequest.getEndpoint());
        System.assertEquals('GET', mock.lastRequest.getMethod());
        System.assertEquals('', mock.lastRequest.getBody());
    }

    @IsTest
    static void createsBillingRequestWithOptionalCreditor() {
        ResponseMock mock = new ResponseMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        GocardlessApiHandler.GocardlessAPIResponseWrapper withCreditor =
            GocardlessApiHandler.createBillingRequest('sepa_core', 'CR-TEST');
        System.assertEquals(true, withCreditor.isSuccess);
        Map<String, Object> bodyWithCreditor =
            (Map<String, Object>) JSON.deserializeUntyped(mock.lastRequest.getBody());
        Map<String, Object> requestWithCreditor = (Map<String, Object>) bodyWithCreditor.get('billing_requests');
        Map<String, Object> mandateWithCreditor = (Map<String, Object>) requestWithCreditor.get('mandate_request');
        System.assertEquals('sepa_core', mandateWithCreditor.get('scheme'));
        System.assertEquals('CR-TEST', mandateWithCreditor.get('creditor_id'));

        GocardlessApiHandler.createBillingRequest('bacs', ' ');
        Map<String, Object> bodyWithoutCreditor =
            (Map<String, Object>) JSON.deserializeUntyped(mock.lastRequest.getBody());
        Map<String, Object> requestWithoutCreditor = (Map<String, Object>) bodyWithoutCreditor.get('billing_requests');
        Map<String, Object> mandateWithoutCreditor = (Map<String, Object>) requestWithoutCreditor.get('mandate_request');
        Test.stopTest();

        System.assertEquals('bacs', mandateWithoutCreditor.get('scheme'));
        System.assertEquals(false, mandateWithoutCreditor.containsKey('creditor_id'));
    }

    @IsTest
    static void returnsParsedApiFailure() {
        ResponseMock mock = new ResponseMock();
        mock.statusCode = 422;
        mock.body = '{"error":{"type":"invalid_api_usage","message":"Bad request"}}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        GocardlessApiHandler.GocardlessAPIResponseWrapper result =
            GocardlessApiHandler.requestGocardlessApi('customers', 'GET', null, true);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess);
        System.assertEquals(422, result.statusCode);
        System.assertEquals('invalid_api_usage: Bad request', result.errorMessage);
    }

    @IsTest
    static void parsesSupportedErrorBodyShapes() {
        System.assertEquals('Empty response body', GocardlessApiHandler.parseErrorCodes(' '));
        System.assertEquals('service unavailable', GocardlessApiHandler.parseErrorCodes('service unavailable'));
        System.assertEquals(
            'First error',
            GocardlessApiHandler.parseErrorCodes('{"errors":[{"message":"First error"}]}')
        );
        System.assertEquals(
            'Unknown error occurred - Response: {"ok":false}',
            GocardlessApiHandler.parseErrorCodes('{"ok":false}')
        );
    }
}