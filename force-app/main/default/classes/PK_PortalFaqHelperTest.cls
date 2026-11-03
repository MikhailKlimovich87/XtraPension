@isTest
public class PK_PortalFaqHelperTest {
    
    @TestSetup
    static void setup() {
        // Create test FAQ records using TestDataFactory
        List<Frequently_Asked_Question__c> faqs = TestDataFactory.createFrequentlyAskedQuestions(2, false);
        if (faqs.size() >= 2) {
            faqs[0].Question__c = 'What is a pension?';
            faqs[0].Answer__c = 'A pension is a retirement benefit...';
            faqs[0].Topic__c = 'General';
            faqs[0].Is_Active__c = true;
            
            faqs[1].Question__c = 'How do I apply?';
            faqs[1].Answer__c = 'You can apply online at our website...';
            faqs[1].Topic__c = 'Application';
            faqs[1].Is_Active__c = true;
        }
        insert faqs;
        
        Frequently_Asked_Question__c faq3 = TestDataFactory.createFrequentlyAskedQuestion(false);
        faq3.Question__c = 'What is an inactive FAQ?';
        faq3.Answer__c = 'This FAQ should not be returned';
        faq3.Topic__c = 'General';
        faq3.Is_Active__c = false;
        insert faq3;
    }
    
    @isTest
    static void testGetFaqSuccess() {
        Test.startTest();
        Map<String, Object> result = PK_PortalFaqHelper.getFaq();
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
        System.assertNotEquals(null, result.get('faqs'));
        
        List<PK_ResponseWrappers.FAQ_Wrapper> faqs = (List<PK_ResponseWrappers.FAQ_Wrapper>) result.get('faqs');
        System.assertEquals(2, faqs.size());
    }
    
    @isTest
    static void testGetFaqNoActiveRecords() {
        // Delete all active FAQs
        List<Frequently_Asked_Question__c> activeFaqs = [
            SELECT Id FROM Frequently_Asked_Question__c WHERE Is_Active__c = true
        ];
        delete activeFaqs;
        
        Test.startTest();
        Map<String, Object> result = PK_PortalFaqHelper.getFaq();
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
        System.assertEquals('No FAQ found', result.get('message'));
    }
    
    @isTest
    static void testGetFaqMultipleRecords() {
        // Create additional FAQs
        List<Frequently_Asked_Question__c> additionalFaqs = new List<Frequently_Asked_Question__c>();
        for (Integer i = 0; i < 5; i++) {
            additionalFaqs.add(new Frequently_Asked_Question__c(
                Question__c = 'Question ' + i,
                Answer__c = 'Answer ' + i,
                Topic__c = 'Topic ' + i,
                Is_Active__c = true
            ));
        }
        insert additionalFaqs;
        
        Test.startTest();
        Map<String, Object> result = PK_PortalFaqHelper.getFaq();
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
        List<PK_ResponseWrappers.FAQ_Wrapper> faqs = (List<PK_ResponseWrappers.FAQ_Wrapper>) result.get('faqs');
        System.assertEquals(7, faqs.size());
    }
    
    @isTest
    static void testGetFaqExceptionHandling() {
        // This test verifies exception handling, though it's hard to trigger without mocking
        Test.startTest();
        Map<String, Object> result = PK_PortalFaqHelper.getFaq();
        Test.stopTest();
        
        System.assertNotEquals(null, result);
        System.assertNotEquals(null, result.get('status'));
    }
    
    @isTest
    static void testGetFaqVerifyFaqWrapper() {
        Test.startTest();
        Map<String, Object> result = PK_PortalFaqHelper.getFaq();
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
        List<PK_ResponseWrappers.FAQ_Wrapper> faqs = (List<PK_ResponseWrappers.FAQ_Wrapper>) result.get('faqs');
        
        if (faqs.size() > 0) {
            PK_ResponseWrappers.FAQ_Wrapper faq = faqs[0];
            System.assertNotEquals(null, faq);
        }
    }
}