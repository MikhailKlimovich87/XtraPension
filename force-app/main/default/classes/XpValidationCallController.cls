/**
 * The Validation call box on the Claim (lwc/xpValidationCall; Fernando, 10 Nov 2026): the client's Claims
 * validation call as XP Booking (book.xtrapension.com) has it, found by the client's e-mail, and the links
 * that book one with the claim's validation agent (AUS/NZ on /go/claim-aus, the rest on /go/claim-eu: the
 * same split as BasicTriggerHandler.isAusNz).
 *
 * XP Booking asks for a key, kept in the XP Booking Settings custom setting and sent from here only: the
 * browser never sees it. XP Booking not answering, or the key not set: the box shows the claim's own
 * Val Call Booked Date, which XP Booking writes on every booking, move and cancel.
 */
public with sharing class XpValidationCallController {

    @TestVisible
    private static final String DEFAULT_BASE = 'https://book.xtrapension.com';

    @AuraEnabled
    public static Map<String, Object> getCall(Id claimId) {
        Basic__c c = [
            SELECT Id, Email__c, First_Name__c, Last_Name__c, Phone__c, Validation_Agent__c,
                   Current_Address_Abroad_Country__c, Current_Address_Abroad_Country_Name__c, Val_Call_Booked_Date__c
            FROM Basic__c
            WHERE Id = :claimId
            LIMIT 1
        ];
        XP_Booking_Settings__c s = XP_Booking_Settings__c.getOrgDefaults();
        String base = (s != null && String.isNotBlank(s.Base_URL__c)) ? s.Base_URL__c.trim().removeEnd('/') : DEFAULT_BASE;
        Boolean ausNz = BasicTriggerHandler.isAusNz(c);
        String page = ausNz ? 'claim-aus' : 'claim-eu';

        Map<String, Object> out = new Map<String, Object>{
            'agent' => c.Validation_Agent__c,
            'region' => ausNz ? 'AUS/NZ' : 'EU/ROW',
            'bookUrl' => bookLink(base, page, c, true),
            'clientUrl' => bookLink(base, page, c, false),
            'fallback' => c.Val_Call_Booked_Date__c
        };
        if (String.isBlank(c.Email__c)) {
            out.put('status', 'no_email');
            return out;
        }
        if (s == null || String.isBlank(s.Key__c)) {
            out.put('status', 'offline');
            out.put('detail', 'XP Booking Settings has no key');
            return out;
        }
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(base + '/api/book/claims/validation-call');
            req.setMethod('POST');
            req.setTimeout(8000);
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('X-XP-Key', s.Key__c.trim());
            req.setBody(JSON.serialize(new Map<String, Object>{ 'email' => c.Email__c.trim(), 'agent' => c.Validation_Agent__c, 'page' => page }));
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() != 200) {
                out.put('status', 'offline');
                out.put('detail', 'XP Booking answered ' + res.getStatusCode());
                return out;
            }
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            out.put('status', 'ok');
            out.put('call', body.get('call'));
            // Whose times "Book the call" opens: the claim's agent when they take this page's calls.
            out.put('offers', body.get('offers'));
        } catch (Exception e) {
            out.put('status', 'offline');
            out.put('detail', e.getMessage());
        }
        return out;
    }

    // The booking page with the client's name, e-mail and phone filled in. From Salesforce the booking says
    // so (utm_source=salesforce); the link for the client to book themselves does not.
    @TestVisible
    private static String bookLink(String base, String page, Basic__c c, Boolean fromSalesforce) {
        String first = c.First_Name__c == null ? '' : c.First_Name__c.trim();
        String last = c.Last_Name__c == null ? '' : c.Last_Name__c.trim();
        String name = (first + ' ' + last).trim();
        List<String> q = new List<String>();
        if (String.isNotBlank(name)) {
            q.add('name=' + EncodingUtil.urlEncode(name, 'UTF-8'));
        }
        if (String.isNotBlank(c.Email__c)) {
            q.add('email=' + EncodingUtil.urlEncode(c.Email__c.trim(), 'UTF-8'));
        }
        if (String.isNotBlank(c.Phone__c)) {
            q.add('a1=' + EncodingUtil.urlEncode(c.Phone__c.trim(), 'UTF-8'));
        }
        if (fromSalesforce) {
            q.add('utm_source=salesforce');
        }
        return base + '/go/' + page + (q.isEmpty() ? '' : '?' + String.join(q, '&'));
    }
}