@isTest
public class ApplicationFormErrorTriggerTest {

    @IsTest
    static void createApplcationFormErrorTest() {
        Application_Form_Error__c errorData = new Application_Form_Error__c();
        errorData.Error_Body__c = 'Test message';
        errorData.Error_Date__c = Date.today();
        Test.startTest();
        insert errorData;
        Test.stopTest();
    }
}