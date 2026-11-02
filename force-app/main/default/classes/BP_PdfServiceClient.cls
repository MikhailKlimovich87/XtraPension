/**
 * Single entry point for calls to the external PDF-filling service.
 * Applies a timeout and turns every failure (callout exception, non-2xx, empty endpoint)
 * into a Result that callers can report, instead of silently doing nothing.
 */
public with sharing class BP_PdfServiceClient {

    public static final Integer TIMEOUT_MS = 120000;
    public static final  XtraPension_Data__c xtraPensionData = XtraPension_Data__c.getOrgDefaults();

    public class Result {
        public Boolean success = false;
        public Integer statusCode;
        public String body;
        public String error;
    }

    public static Result post(String label, String endpoint, Object payload) {
        Result result = new Result();
        if (String.isBlank(endpoint)) {
            result.error = label + ': PDF service endpoint is not configured';
            return result;
        }
        try {
            HttpRequest request = new HttpRequest();
            request.setEndpoint(endpoint);
            request.setMethod('POST');
            request.setHeader('Content-Type', 'application/json;charset=UTF-8');
            request.setHeader('X-API-KEY', xtraPensionData.BR_X_Api_Key__c);
            request.setTimeout(TIMEOUT_MS);
            request.setBody(JSON.serialize(payload));

            HttpResponse response = new Http().send(request);
            result.statusCode = response.getStatusCode();
            result.body = response.getBody();
            result.success = result.statusCode >= 200 && result.statusCode < 300;
            if (!result.success) {
                String details = String.isBlank(result.body) ? '' : ' - ' + result.body.abbreviate(500);
                result.error = label + ': PDF service returned HTTP ' + result.statusCode + ' ' + response.getStatus() + details;
            }
        } catch (Exception ex) {
            result.error = label + ': ' + ex.getTypeName() + ' - ' + ex.getMessage();
        }
        return result;
    }

    public static String joinErrors(List<Result> results) {
        List<String> errors = new List<String>();
        for (Result item : results) {
            if (item != null && !item.success && String.isNotBlank(item.error)) {
                errors.add(item.error);
            }
        }
        return String.join(errors, '\n');
    }

    // For asynchronous contexts where nobody is waiting for an exception.
    // Must run after the last callout of the transaction (DML before a callout is not allowed).
    public static void logFailures(Id claimId, List<Result> results) {
        String errors = joinErrors(results);
        if (String.isBlank(errors)) {
            return;
        }
        try {
            insert new Application_Form_Error__c(
                Error_Body__c = 'PDF generation failed for claim ' + claimId + '\n' + errors,
                Error_Date__c = Date.today()
            );
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Could not log PDF service failure: ' + ex.getMessage() + ' / ' + errors);
        }
    }
}