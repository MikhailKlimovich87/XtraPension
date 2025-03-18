public class BlankeSMSFlowHelper {
    public class Request {
        @InvocableVariable(required = true)
        public String smsBody;

        @InvocableVariable(required = true)
        public Datetime receiveDate;
    }
    public class Response {
        @InvocableVariable(label = 'Result of execution' required = true)
        public String result;
    }

    @InvocableMethod
    public static List<Response> updateSmsBody(List<Request> requestData) {
        List<Response> responseWrapper = new List<Response>();
        Response response =  new Response();
        Request request = requestData[0];
        String updateLine = request.smsBody.replace('{ReceiveDate}', String.valueOf(request.receiveDate.format('EEE dd MMM yyyy')));
        response.result = updateLine;
        responseWrapper.add(response);
        return responseWrapper;
    }
}