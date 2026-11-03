public with sharing class PK_PortalFaqHelper {

    public static Map<String, Object> getFaq() {
        Map<String, Object> results = new Map<String, Object>();
        try {
            List<Frequently_Asked_Question__c> questions = [
                SELECT
                    Answer__c,
                    Question__c,
                    Topic__c
                FROM Frequently_Asked_Question__c
                WHERE Is_Active__c = true
            ];
            if (questions.size() == 0) {
                results.put('status', 'error');
                results.put('message', 'No FAQ found');
            } else {
                List<PK_ResponseWrappers.FAQ_Wrapper> faqWrappers = new List<PK_ResponseWrappers.FAQ_Wrapper>();
                for (Frequently_Asked_Question__c faq : questions) {
                    faqWrappers.add(new PK_ResponseWrappers.FAQ_Wrapper(faq));
                }
                results.put('status', 'success');
                results.put('faqs', faqWrappers);
            }
        } catch (Exception e) {
            results.put('status', 'error');
            results.put('message', e.getLineNumber() + '-' + e.getMessage());
        }

        return results;
    }
}