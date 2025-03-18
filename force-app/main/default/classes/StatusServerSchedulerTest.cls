@isTest
public class StatusServerSchedulerTest {
    @IsTest(SeeAllData=true)
    static void checkStatusSuccesResultTest(){
        Datetime currentTime = Datetime.now();
        String scheduleHours = String.valueOf(currentTime.hour() + 1);
        String scheduleTime = '0 0 ' + scheduleHours + ' * * ?';
        Test.setMock(HttpCalloutMock.class, new StatusServerSuccessHttpCalloutMock());
        Test.startTest();
        String jobId = System.schedule('Test', scheduleTime, new StatusServerScheduler());
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'Schedule Job Id must be not null');
        CronTrigger ct = [
            SELECT
                Id,
                CronExpression,
                TimesTriggered,
                NextFireTime
            FROM CronTrigger
            WHERE id = :jobId
        ];
        System.assertEquals(scheduleTime, ct.CronExpression, 'CronExpression must be like scheduleTime');
        System.assertEquals(0, ct.TimesTriggered, 'TimesTriggered must be 0');
    }

    @IsTest(SeeAllData=true)
    static void checkStatusErrorResultTest(){
        Datetime currentTime = Datetime.now();
        String scheduleHours = String.valueOf(currentTime.hour() + 1);
        String scheduleTime = '0 0 ' + scheduleHours + ' * * ?';
        Test.setMock(HttpCalloutMock.class, new StatusServerErrorHttpCalloutMock());
        Test.startTest();
        String jobId = System.schedule('Test', scheduleTime, new StatusServerScheduler());
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'Schedule Job Id must be not null');
        CronTrigger ct = [
            SELECT
                Id,
                CronExpression,
                TimesTriggered,
                NextFireTime
            FROM CronTrigger
            WHERE id = :jobId
        ];
        System.assertEquals(scheduleTime, ct.CronExpression, 'CronExpression must be like scheduleTime');
        System.assertEquals(0, ct.TimesTriggered, 'TimesTriggered must be 0');
    }

    public class StatusServerSuccessHttpCalloutMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            response.setBody('{"status":"Success","message":"Server is connected to SF."}');
            response.setStatusCode(200);
            return response;
        }
    }

    public class StatusServerErrorHttpCalloutMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            response.setBody('{"status":"Error","message":"Server is not connected to SF."}');
            response.setStatusCode(400);
            return response;
        }
    }
}