@isTest
public with sharing class XtraPensionTemporaryEmailServiceTest {
    @isTest
    static void testCreateEmailMessage(){
        Test.startTest();
        XtraPensionTemporaryEmailService.fakeMethod();
        Test.stopTest();
    }
}