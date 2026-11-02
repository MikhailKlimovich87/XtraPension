/**
 * PC1_AddressLookup — @AuraEnabled Loqate proxy for the pc1AddressEditor
 * LWC. Bypasses CORS/CSP by calling Loqate from the Salesforce server side.
 *
 * The Loqate key lives in a Remote Site + Named Credential OR in a
 * Protected Custom Setting (PC1_Config__c.Loqate_Key__c — added in this
 * class if missing). Same Find/Retrieve two-step as the Heroku widget.
 */
public with sharing class PC1_AddressLookup {

    private static final String FIND_URL     = 'https://api.addressy.com/Capture/Interactive/Find/v1.10/json3.ws';
    private static final String RETRIEVE_URL = 'https://api.addressy.com/Capture/Interactive/Retrieve/v1.20/json3.ws';
    private static final Integer TIMEOUT_MS  = 8000;

    public class Suggestion {
        @AuraEnabled public String id;
        @AuraEnabled public String type;         // 'Address' | 'Container'
        @AuraEnabled public String text;
        @AuraEnabled public String description;
    }

    public class Address {
        @AuraEnabled public String line1;
        @AuraEnabled public String line2;        // collapsed Line2..Line5
        @AuraEnabled public String town;
        @AuraEnabled public String county;
        @AuraEnabled public String postcode;
        @AuraEnabled public String country;
    }

    @AuraEnabled(cacheable=false)
    public static List<Suggestion> findAddress(String search, String lastId, String container) {
        String key = getKey();
        if (String.isBlank(key)) throw new AuraHandledException('Loqate key not configured. Set PC1_Config__c.Loqate_Key__c.');
        String s = search == null ? '' : search.trim();
        String c = String.isNotBlank(container) ? container : (String.isNotBlank(lastId) ? lastId : '');
        if (String.isBlank(s) && String.isBlank(c)) return new List<Suggestion>();

        String url = FIND_URL
            + '?Key=' + EncodingUtil.urlEncode(key, 'UTF-8')
            + '&Text=' + EncodingUtil.urlEncode(s, 'UTF-8')
            + '&Countries=GB&Language=en&Limit=20';
        if (String.isNotBlank(c)) url += '&Container=' + EncodingUtil.urlEncode(c, 'UTF-8');

        HttpResponse resp = call(url);
        Map<String, Object> body = safeParse(resp.getBody());
        List<Object> items = (List<Object>) body.get('Items');
        List<Suggestion> out = new List<Suggestion>();
        if (items == null) return out;
        for (Object o : items) {
            Map<String, Object> row = (Map<String, Object>) o;
            if (row.get('Error') != null) {
                throw new AuraHandledException('Loqate: ' + String.valueOf(row.get('Description')));
            }
            Suggestion sg = new Suggestion();
            sg.id          = (String) row.get('Id');
            String t       = (String) row.get('Type');
            sg.type        = (t == 'Address') ? 'Address' : 'Container';
            sg.text        = (String) row.get('Text');
            sg.description = (String) row.get('Description');
            out.add(sg);
        }
        return out;
    }

    @AuraEnabled(cacheable=false)
    public static Address retrieveAddress(String id) {
        String key = getKey();
        if (String.isBlank(key)) throw new AuraHandledException('Loqate key not configured.');
        if (String.isBlank(id)) throw new AuraHandledException('id required');

        String url = RETRIEVE_URL
            + '?Key=' + EncodingUtil.urlEncode(key, 'UTF-8')
            + '&Id='  + EncodingUtil.urlEncode(id,  'UTF-8');
        HttpResponse resp = call(url);
        Map<String, Object> body = safeParse(resp.getBody());
        List<Object> items = (List<Object>) body.get('Items');
        if (items == null || items.isEmpty()) throw new AuraHandledException('No address returned.');
        Map<String, Object> raw = (Map<String, Object>) items[0];
        if (raw.get('Error') != null) {
            throw new AuraHandledException('Loqate: ' + String.valueOf(raw.get('Description')));
        }
        Address a = new Address();
        String line1 = str(raw.get('Line1'));
        if (String.isBlank(line1)) {
            String fallback = firstNonBlank(new List<String>{
                str(raw.get('Company')), str(raw.get('BuildingName')), str(raw.get('SubBuilding'))
            });
            if (String.isBlank(fallback)) {
                String bn = str(raw.get('BuildingNumber'));
                String st = str(raw.get('Street'));
                fallback = String.join(new List<String>{ bn, st }, ' ').trim();
            }
            line1 = fallback;
        }
        List<String> extras = new List<String>();
        for (Integer i = 2; i <= 5; i++) {
            String ln = str(raw.get('Line' + i));
            if (String.isNotBlank(ln)) extras.add(ln);
        }
        a.line1    = line1 == null ? '' : line1.trim();
        a.line2    = String.join(extras, ', ');
        a.town     = firstNonBlank(new List<String>{ str(raw.get('City')), str(raw.get('PostTown')), str(raw.get('AdminAreaName')) });
        a.county   = firstNonBlank(new List<String>{ str(raw.get('ProvinceName')), str(raw.get('AdminAreaName')) });
        a.postcode = str(raw.get('PostalCode'));
        a.country  = firstNonBlank(new List<String>{ str(raw.get('CountryName')), 'United Kingdom' });
        return a;
    }

    // ── helpers ─────────────────────────────────────────────────────

    private static String getKey() {
        PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
        if (cfg != null && String.isNotBlank(cfg.Loqate_Key__c)) return cfg.Loqate_Key__c.trim();
        return null;
    }

    private static HttpResponse call(String url) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(url);
        req.setMethod('GET');
        req.setTimeout(TIMEOUT_MS);
        HttpResponse resp = new Http().send(req);
        if (resp.getStatusCode() < 200 || resp.getStatusCode() >= 300) {
            throw new AuraHandledException('Loqate HTTP ' + resp.getStatusCode());
        }
        return resp;
    }

    private static Map<String, Object> safeParse(String body) {
        try { return (Map<String, Object>) JSON.deserializeUntyped(body); }
        catch (Exception e) { throw new AuraHandledException('Loqate returned non-JSON: ' + body.substring(0, Math.min(120, body.length()))); }
    }

    private static String str(Object o) { return o == null ? '' : String.valueOf(o).trim(); }

    private static String firstNonBlank(List<String> xs) {
        for (String x : xs) if (String.isNotBlank(x)) return x.trim();
        return '';
    }
}