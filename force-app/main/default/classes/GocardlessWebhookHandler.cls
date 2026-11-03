@RestResource(urlMapping='/GoCardlessWebhookApi/*')
global class GocardlessWebhookHandler {

    // ============================================================
    // CONSTANTS
    // ============================================================
    private static final Integer SIGNATURE_MISMATCH = 498;
    private static final Integer BAD_REQUEST        = 400;
    private static final Integer SERVER_ERROR       = 500;


    // ============================================================
    // WEBHOOK ENTRY POINT
    // ============================================================
    @HttpPost
    global static void postRouter() {

        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;

        // -----------------------------------------------------------------
        // 0. Safe default — guarantees we never send a null body
        // -----------------------------------------------------------------
        res.statusCode   = SERVER_ERROR;
        res.responseBody = Blob.valueOf('{"status":"error","message":"Handler did not complete"}');

        try {
            // ---------------------------------------------------------
            // 1. Load configuration
            // ---------------------------------------------------------
            List<GoCardless_Integration__c> configs = [
                SELECT Webhook_Secret__c
                FROM GoCardless_Integration__c
                LIMIT 1
            ];

            if (configs.isEmpty() || String.isBlank(configs[0].Webhook_Secret__c)) {
                res.statusCode   = SERVER_ERROR;
                res.responseBody = Blob.valueOf('{"status":"error","message":"Webhook secret not configured"}');
                return;
            }

            String webhookSecret = configs[0].Webhook_Secret__c.trim();

            // ---------------------------------------------------------
            // 2. Read raw body — keep the Blob, we hash the Blob
            // ---------------------------------------------------------
            if (req.requestBody == null || req.requestBody.size() == 0) {
                res.statusCode   = BAD_REQUEST;
                res.responseBody = Blob.valueOf('{"status":"error","message":"Empty request body"}');
                return;
            }

            Blob   rawBodyBlob = req.requestBody;
            String rawBodyStr  = rawBodyBlob.toString();

            // ---------------------------------------------------------
            // 3. Read signature header (case-insensitive)
            // ---------------------------------------------------------
            String signatureHeader = null;
            for (String key : req.headers.keySet()) {
                if ('webhook-signature'.equalsIgnoreCase(key)) {
                    signatureHeader = req.headers.get(key);
                    break;
                }
            }

            if (String.isBlank(signatureHeader)) {
                res.statusCode   = SIGNATURE_MISMATCH;
                res.responseBody = Blob.valueOf('{"status":"error","message":"Missing webhook-signature header"}');
                return;
            }

            signatureHeader = signatureHeader.trim().toLowerCase();

            // ---------------------------------------------------------
            // 4. Compute expected HMAC over raw Blob
            // ---------------------------------------------------------
            Blob expectedMac = Crypto.generateMac(
                'HmacSHA256',
                rawBodyBlob,
                Blob.valueOf(webhookSecret)
            );
            String expectedSignature = EncodingUtil.convertToHex(expectedMac).toLowerCase();

            System.debug(LoggingLevel.ERROR,
                'Sig debug | bodyBytes=' + rawBodyBlob.size()
                + ' | secretLen=' + webhookSecret.length()
                + ' | expected=' + expectedSignature
                + ' | received=' + signatureHeader);

            // ---------------------------------------------------------
            // 5. Constant-time compare
            // ---------------------------------------------------------
            if (!constantTimeEquals(expectedSignature, signatureHeader)) {
                res.statusCode   = SIGNATURE_MISMATCH;
                res.responseBody = Blob.valueOf(
                    '{"status":"error","message":"Invalid Webhook Signature"}'
                );
                return;
            }

            // ---------------------------------------------------------
            // 6. Parse the payload
            // ---------------------------------------------------------
            Map<String, Object> jsonRoot;
            try {
                jsonRoot = (Map<String, Object>) JSON.deserializeUntyped(rawBodyStr);
            } catch (Exception ex) {
                res.statusCode   = BAD_REQUEST;
                res.responseBody = Blob.valueOf(
                    '{"status":"error","message":"Invalid JSON payload"}'
                );
                return;
            }
            
            List<Object> events = (List<Object>) jsonRoot.get('events');
            System.debug('events ===== ' + events);
            List<GoCardless_Webhook_Event__c> toInsert = new List<GoCardless_Webhook_Event__c>();

            if (events != null && !events.isEmpty()) {
                for (Object evtObj : events) {
                    Map<String, Object> evt = (Map<String, Object>) evtObj;
                    toInsert.add(
                        new GoCardless_Webhook_Event__c(
                            Event_Id__c  = (String) evt.get('id'), // <-- Dedupe on this
                            Event_Type__c = (String) evt.get('resource_type') + '.' + (String) evt.get('action'),
                            Payload__c    = JSON.serialize(evt),
                            Processed__c  = false
                        )
                    );
                }
            }

            System.debug('toInsert ===== ' + toInsert);

            // Insert with partial success to skip duplicates safely
            if (!toInsert.isEmpty()) {
                Database.insert(toInsert, false); // false = allow partial success (ignore duplicates)
            }


            // ---------------------------------------------------------
            // 7. Enqueue processing — return 200 fast, avoid CPU limits
            // ---------------------------------------------------------
            List<GoCardless_Webhook_Event__c> newEvents = [
                SELECT Id, Event_Id__c, Event_Type__c, Payload__c 
                FROM GoCardless_Webhook_Event__c 
                WHERE Processed__c = false
            ];  
            System.debug('newEvents ===== ' + newEvents);
            System.debug(newEvents.size() + ' GoCardless webhook events to enqueue for processing.'); 
            if (events != null && !events.isEmpty()) {
                System.enqueueJob(new GoCardlessWebhookQueueable(newEvents));
            }


            // ---------------------------------------------------------
            // 8. Acknowledge
            // ---------------------------------------------------------
            res.statusCode   = 200;
            res.responseBody = Blob.valueOf('{"status":"ok"}');

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'GoCardless webhook unexpected error: ' + e.getMessage()
                + ' | Stack: ' + e.getStackTraceString());

            res.statusCode   = SERVER_ERROR;
            res.responseBody = Blob.valueOf(
                '{"status":"error","message":"' +
                String.escapeSingleQuotes(e.getMessage()) + '"}'
            );
        }
    }


    // ============================================================
    // HELPERS
    // ============================================================

    @TestVisible
    private static Boolean constantTimeEquals(String a, String b) {
        if (a == null || b == null) {
            return false;
        }
        if (a.length() != b.length()) {
            return false;
        }

        Integer diff = 0;
        for (Integer i = 0; i < a.length(); i++) {
            diff |= (a.charAt(i) ^ b.charAt(i));
        }
        return diff == 0;
    }
}