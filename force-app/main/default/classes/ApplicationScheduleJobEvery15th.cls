public with sharing class ApplicationScheduleJobEvery15th {
    @InvocableMethod
    public static List<Response> createPaymentAfter72Hours(List<Sobject> applications) {
        return null;
    }

    public class Requests {
        @InvocableVariable(label='Current Application' required=true)
        public List<Sobject> applications;
    }
    public class Response {
        @InvocableVariable(label='Result of execution' required=true)
        public String schedulerJobId;
    }
}