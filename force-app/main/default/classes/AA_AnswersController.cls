/**
 * AA_AnswersController — read-only backing for aaAnswersList LWC.
 * Cacheable so navigating between records doesn't re-hit the DB.
 */
public with sharing class AA_AnswersController {
    @AuraEnabled(cacheable=true)
    public static List<AA_Answer__c> getAnswers(Id applicationId) {
        if (applicationId == null) return new List<AA_Answer__c>();
        return [
            SELECT Id, Field_Id__c, Value__c, Source__c, Confidence__c, CreatedDate
            FROM AA_Answer__c
            WHERE Application__c = :applicationId
            WITH USER_MODE
            ORDER BY Source__c, Field_Id__c
            LIMIT 500
        ];
    }
}