/**
 * PC1_AnswersController — read-only backing for pc1AnswersList LWC.
 * Cacheable so navigating between records doesn't re-hit the DB.
 */
public with sharing class PC1_AnswersController {
    @AuraEnabled(cacheable=true)
    public static List<PC1_Answer__c> getAnswers(Id applicationId) {
        if (applicationId == null) return new List<PC1_Answer__c>();
        return [
            SELECT Id, Field_Id__c, Value__c, Source__c, Confidence__c, CreatedDate
            FROM PC1_Answer__c
            WHERE Application__c = :applicationId
            ORDER BY Source__c, Field_Id__c
            LIMIT 500
        ];
    }
}