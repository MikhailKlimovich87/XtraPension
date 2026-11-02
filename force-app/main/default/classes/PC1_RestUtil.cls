/**
 * PC1_RestUtil — helpers shared by every PC1 Apex REST endpoint.
 *
 * The mock endpoints under /services/apexrest/pc1/* stand in for what the
 * Heroku worker will do once deployed. They accept the same JSON payloads
 * that Mary's Eleven Labs tools send today, so nothing in the agent config
 * has to change when we cut over to Heroku.
 */
public with sharing class PC1_RestUtil {

    public static Map<String, Object> parseBody() {
        RestRequest req = RestContext.request;
        if (req == null || req.requestBody == null || req.requestBody.size() == 0) {
            return new Map<String, Object>();
        }
        String body = req.requestBody.toString();
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(body);
        } catch (Exception e) {
            return new Map<String, Object>{ '_parseError' => e.getMessage(), '_raw' => body };
        }
    }

    public static void writeJson(Object o) {
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(o));
    }

    public static void writeError(Integer status, String message) {
        RestContext.response.statusCode = status;
        writeJson(new Map<String, Object>{ 'status' => 'error', 'error' => message });
    }

    public static String str(Map<String, Object> body, String key) {
        Object v = body.get(key);
        return v == null ? null : String.valueOf(v);
    }

    /**
     * Locate a PC1_Application__c by any of: application_id (SF Id or Name),
     * dwp_reference, phone (E.164). Returns null if none match.
     */
    public static PC1_Application__c findApplication(Map<String, Object> body) {
        String appId  = str(body, 'application_id');
        String dwpRef = str(body, 'dwp_reference');
        String phone  = str(body, 'phone');

        if (appId != null) {
            // Might be a SF 15/18-char Id, or a Name like PC1-00042
            if (appId.length() == 15 || appId.length() == 18) {
                List<PC1_Application__c> l = [SELECT Id, Name, Stage__c, Full_Name__c, Progress_Filled__c, Progress_Total__c FROM PC1_Application__c WHERE Id = :appId LIMIT 1];
                if (!l.isEmpty()) return l[0];
            } else {
                List<PC1_Application__c> l = [SELECT Id, Name, Stage__c, Full_Name__c, Progress_Filled__c, Progress_Total__c FROM PC1_Application__c WHERE Name = :appId LIMIT 1];
                if (!l.isEmpty()) return l[0];
            }
        }
        if (dwpRef != null) {
            List<PC1_Application__c> l = [SELECT Id, Name, Stage__c, Full_Name__c, Progress_Filled__c, Progress_Total__c FROM PC1_Application__c WHERE DWP_Reference__c = :dwpRef LIMIT 1];
            if (!l.isEmpty()) return l[0];
        }
        if (phone != null) {
            List<PC1_Application__c> l = [SELECT Id, Name, Stage__c, Full_Name__c, Progress_Filled__c, Progress_Total__c FROM PC1_Application__c WHERE Phone__c = :phone LIMIT 1];
            if (!l.isEmpty()) return l[0];
        }
        return null;
    }
}