/**
 * PC1_FlowEngine — Apex port of src/fill/flow.js (Hostinger walker).
 *
 * Given a PC1_Application__c + its child PC1_Answer__c rows, walks
 * pc1FlowConfig (StaticResource) using the same 4-operator grammar as the JS
 * walker — {id,eq} / {id,has} / {id,hasnot} / {any:[…]} — and produces the
 * ordered list of fields the applicant still owes ("what Mary must do").
 *
 * Design decisions from Phase 1's coordinator pass:
 *   Q1  Sub-flows CHILD/PENSION/MONEY: SKIPPED — no loop invokes them today.
 *   Q2  Policy defaults (Source__c='default') COUNT as filled.
 *   Q3  Declaration fields decl/declname/decldate are NEVER counted, and any
 *       page with declaration:true is skipped entirely.
 *   Q4  Blocked fields (gate not yet answered) live in blockedFieldIds /
 *       blockedReasonById, NOT in requiredFieldIds.
 *   Q5  Trigger-driven (PC1_AnswerTrigger already invokes recomputeAndUpdate).
 *
 * Bulk-safe: one SOQL for the answers, one static JSON parse per transaction
 * (~90KB static resource — expensive), one DML for the update.
 */
public with sharing class PC1_FlowEngine {

    // ── Public result shapes ─────────────────────────────────────────────

    public class ProgressResult {
        @AuraEnabled public Integer filled;
        @AuraEnabled public Integer total;
        @AuraEnabled public Decimal percent;                     // 0..100, null if total==0
        @AuraEnabled public List<String> requiredFieldIds;
        @AuraEnabled public List<String> filledFieldIds;
        @AuraEnabled public List<String> missingFieldIds;
        @AuraEnabled public List<String> blockedFieldIds;
        // Fields on the client's path that are optional (won't fail the fill
        // if empty) — surfaced so the LWC path tab can render them even
        // though they don't count toward Progress totals. Currently: q9,
        // q_mobile, address-line-2, county, middle names, etc.
        @AuraEnabled public List<String> pathOptionalFieldIds;
        @AuraEnabled public Map<String, String> labelById;       // fieldId → human label
        @AuraEnabled public Map<String, String> partByFieldId;   // fieldId → Part name
        @AuraEnabled public Map<String, String> blockedReasonById;
        @AuraEnabled public Map<String, PartCount> byPart;
        @AuraEnabled public List<String> missingParts;           // ordered dedup
    }

    public class PartCount {
        @AuraEnabled public Integer filled;
        @AuraEnabled public Integer total;
        @AuraEnabled public List<String> missing;                // field ids
    }

    // ── Per-transaction cache of the parsed flow ─────────────────────────

    private static Map<String, Object> FLOW_CACHE;
    private static List<Object> PAGES_CACHE;
    private static Map<String, String> LABEL_BY_ID_CACHE;
    private static List<String> PART_ORDER_CACHE;

    // Field ids that never count toward "what Mary must do".
    private static final Set<String> DECLARATION_IDS = new Set<String>{
        'decl', 'declname', 'decldate'
    };

    // ── Public entry points ──────────────────────────────────────────────

    public static ProgressResult compute(Id appId) {
        Map<Id, ProgressResult> m = compute(new Set<Id>{ appId });
        return m.get(appId);
    }

    /**
     * getPathForRecord — LWC-facing wrapper.
     * Returns the "client's actual path" data the pc1ApplicationData LWC needs
     * to render its two tabs and lock icons:
     *   requiredFieldIds  → fields on the client's path (path tab filter)
     *   blockedFieldIds   → fields whose gate is unanswered (lock icon in both tabs)
     *   blockedReasonById → human string per blocked field (LightningConfirm body)
     *   filledFieldIds / missingFieldIds → totals for the path header
     *   partsCovered      → ordered part names that appear on this client's path
     *   filled / total / declarationComplete → for the mode-aware header
     *
     * Cacheable so the LWC can @wire it; also refreshApex-able after a save.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getPathForRecord(Id recordId) {
        if (recordId == null) return new Map<String, Object>();
        ProgressResult r = compute(recordId);
        // Ordered parts on the client's path (Map.keySet() preserves insertion order in Apex).
        List<String> partsCovered = new List<String>();
        if (r != null && r.byPart != null) {
            for (String p : r.byPart.keySet()) partsCovered.add(p);
        }
        Boolean decl = false;
        List<PC1_Application__c> apps = [
            SELECT Declaration_Complete__c
              FROM PC1_Application__c
             WHERE Id = :recordId
             LIMIT 1
        ];
        if (!apps.isEmpty() && apps[0].Declaration_Complete__c == true) decl = true;

        return new Map<String, Object>{
            'requiredFieldIds'    => r == null ? new List<String>() : r.requiredFieldIds,
            'pathOptionalFieldIds' => r == null ? new List<String>() : r.pathOptionalFieldIds,
            'blockedFieldIds'     => r == null ? new List<String>() : r.blockedFieldIds,
            'blockedReasonById'   => r == null ? new Map<String, String>() : r.blockedReasonById,
            'filledFieldIds'      => r == null ? new List<String>() : r.filledFieldIds,
            'missingFieldIds'     => r == null ? new List<String>() : r.missingFieldIds,
            'partsCovered'        => partsCovered,
            'filled'              => r == null ? 0 : r.filled,
            'total'               => r == null ? 0 : r.total,
            'declarationComplete' => decl
        };
    }

    public static Map<Id, ProgressResult> compute(Set<Id> appIds) {
        Map<Id, ProgressResult> out = new Map<Id, ProgressResult>();
        if (appIds == null || appIds.isEmpty()) return out;
        loadFlow();

        // Governor guard — if we're at risk of the 50k row cap, bail.
        Integer count = [SELECT COUNT() FROM PC1_Answer__c WHERE Application__c IN :appIds LIMIT 45000];
        if (count >= 45000) {
            throw new AuraHandledException('PC1_FlowEngine: answer count ' + count + ' too high for a single bulk pass');
        }

        // Group answers by application in memory.
        Map<Id, Map<String, String>> answersByApp = new Map<Id, Map<String, String>>();
        for (Id id : appIds) answersByApp.put(id, new Map<String, String>());
        for (PC1_Answer__c a : [
            SELECT Application__c, Field_Id__c, Value__c
              FROM PC1_Answer__c
             WHERE Application__c IN :appIds
        ]) {
            if (a.Application__c == null || String.isBlank(a.Field_Id__c)) continue;
            answersByApp.get(a.Application__c).put(a.Field_Id__c, a.Value__c);
        }

        for (Id id : appIds) {
            out.put(id, computeOne(answersByApp.get(id)));
        }
        return out;
    }

    public static void recomputeAndUpdate(Set<Id> appIds) {
        if (appIds == null || appIds.isEmpty()) return;
        Map<Id, ProgressResult> results = compute(appIds);
        // Also compute declaration state per app — decl + declname +
        // decldate triplet all present. Fill DWP is blocked when this is
        // false; the progress bar surfaces "Declaration pending".
        Map<Id, Boolean> declByApp = new Map<Id, Boolean>();
        for (Id id : appIds) declByApp.put(id, false);
        for (PC1_Answer__c a : [
            SELECT Application__c, Field_Id__c, Value__c
              FROM PC1_Answer__c
             WHERE Application__c IN :appIds
               AND Field_Id__c IN ('decl','declname','decldate_day','decldate_month','decldate_year')
        ]) {
            if (a.Value__c == null || a.Value__c == '') continue;
            Map<String, Boolean> flags = (Map<String, Boolean>) declFlagsCache.get(a.Application__c);
            if (flags == null) {
                flags = new Map<String, Boolean>();
                declFlagsCache.put(a.Application__c, flags);
            }
            flags.put(a.Field_Id__c, true);
        }
        for (Id id : appIds) {
            Map<String, Boolean> flags = (Map<String, Boolean>) declFlagsCache.get(id);
            Boolean complete = flags != null
                && flags.get('decl') == true
                && flags.get('declname') == true
                && flags.get('decldate_day') == true
                && flags.get('decldate_month') == true
                && flags.get('decldate_year') == true;
            declByApp.put(id, complete);
        }
        List<PC1_Application__c> toUpdate = new List<PC1_Application__c>();
        for (Id id : appIds) {
            ProgressResult r = results.get(id);
            if (r == null) continue;
            toUpdate.add(new PC1_Application__c(
                Id = id,
                Progress_Filled__c        = r.filled,
                Progress_Total__c         = r.total,
                Progress_Last_Updated__c  = Datetime.now(),
                Progress_Missing_Sections__c = buildMissingSectionsJson(r),
                Declaration_Complete__c   = declByApp.get(id)
            ));
        }
        if (!toUpdate.isEmpty()) update toUpdate;
    }
    // Per-transaction cache — cleared between trigger firings automatically.
    private static Map<Id, Object> declFlagsCache = new Map<Id, Object>();

    // ── Flow loader (cached) ─────────────────────────────────────────────

    private static void loadFlow() {
        if (FLOW_CACHE != null) return;
        List<StaticResource> rows = [SELECT Body FROM StaticResource WHERE Name = 'pc1FlowConfig' LIMIT 1];
        if (rows.isEmpty()) {
            FLOW_CACHE = new Map<String, Object>{ 'PAGES' => new List<Object>() };
        } else {
            FLOW_CACHE = (Map<String, Object>) JSON.deserializeUntyped(rows[0].Body.toString());
        }
        Object p = FLOW_CACHE.get('PAGES');
        PAGES_CACHE = (p instanceof List<Object>) ? (List<Object>) p : new List<Object>();

        // Precompute id → label lookup for blocked-reason messages.
        LABEL_BY_ID_CACHE = new Map<String, String>();
        for (Object po : PAGES_CACHE) collectLabels((Map<String, Object>) po, '');
    }

    private static void collectLabels(Map<String, Object> page, String prefix) {
        Object fieldsObj = page.get('fields');
        if (fieldsObj instanceof List<Object>) {
            for (Object fo : (List<Object>) fieldsObj) {
                Map<String, Object> f = (Map<String, Object>) fo;
                String rawId = (String) f.get('id');
                if (String.isBlank(rawId)) continue;
                String resolved = resolveId(rawId, prefix);
                String label = (String) f.get('label');
                if (String.isNotBlank(label)) LABEL_BY_ID_CACHE.put(resolved, label);
            }
        }
        // Loop pages (only shares today) — recurse into pages using placeholder prefix "s1_"
        Object pagesInner = page.get('pages');
        String loopName = (String) page.get('loop');
        if (String.isNotBlank(loopName) && pagesInner instanceof List<Object>) {
            String pfx = loopName.substring(0, 1) + '1_';
            for (Object po : (List<Object>) pagesInner) collectLabels((Map<String, Object>) po, pfx);
        }
    }

    // ── Per-application computation ──────────────────────────────────────

    private static ProgressResult computeOne(Map<String, String> answers) {
        ProgressResult r = new ProgressResult();
        r.requiredFieldIds  = new List<String>();
        r.filledFieldIds    = new List<String>();
        r.missingFieldIds   = new List<String>();
        r.blockedFieldIds   = new List<String>();
        r.pathOptionalFieldIds = new List<String>();
        r.labelById         = new Map<String, String>();
        r.partByFieldId     = new Map<String, String>();
        r.blockedReasonById = new Map<String, String>();
        r.byPart            = new Map<String, PartCount>();
        r.missingParts      = new List<String>();

        Set<String> seenReq = new Set<String>();
        List<String> partOrder = new List<String>();
        Set<String> partSeen = new Set<String>();

        // Walk the built flow — only the pages that survive the gates.
        List<Map<String, Object>> flow = buildFlow(answers);
        for (Map<String, Object> page : flow) {
            if (isTerminal(page)) continue;
            String part = (String) page.get('part');
            String prefix = (String) page.get('prefix');
            if (prefix == null) prefix = '';

            Object fieldsObj = page.get('fields');
            if (!(fieldsObj instanceof List<Object>)) continue;
            Set<String> seenOptOnThisPage = new Set<String>();
            for (Object fo : (List<Object>) fieldsObj) {
                Map<String, Object> f = (Map<String, Object>) fo;
                // Phase 0.1 (boss brief 2026-08-18): fields with hidden:true
                // are never asked of the client — their default is seeded
                // server-side and the field never counts toward totals.
                // Autofill on the DWP side reads the answer like any other
                // (hiding is a client-form-only concept).
                if (asBool(f.get('hidden'))) continue;
                // field-level gate
                if (!condOK(answers, (List<Object>) f.get('cond'), prefix)) continue;
                String rawId = (String) f.get('id');
                if (String.isBlank(rawId)) continue;
                String fid = resolveId(rawId, prefix);
                if (DECLARATION_IDS.contains(fid)) continue;

                // Optional fields are on the client's path (Playwright would
                // interact with them if answered) but don't fail the fill
                // when empty. Track separately so the LWC path tab can
                // still render them — Fernando: "why isn't phone showing?".
                if (asBool(f.get('optional'))) {
                    if (!seenOptOnThisPage.contains(fid)) {
                        seenOptOnThisPage.add(fid);
                        r.pathOptionalFieldIds.add(fid);
                        if (f.get('label') != null) r.labelById.put(fid, (String) f.get('label'));
                        if (String.isNotBlank(part)) r.partByFieldId.put(fid, part);
                    }
                    continue;
                }

                if (seenReq.contains(fid)) continue;
                seenReq.add(fid);
                r.requiredFieldIds.add(fid);

                String lbl = (String) f.get('label');
                if (String.isNotBlank(lbl)) r.labelById.put(fid, lbl);
                if (String.isNotBlank(part)) r.partByFieldId.put(fid, part);

                Boolean isFilled = isFieldFilled(answers, f, fid);
                if (isFilled) r.filledFieldIds.add(fid);
                else          r.missingFieldIds.add(fid);

                if (String.isNotBlank(part)) {
                    if (!partSeen.contains(part)) { partSeen.add(part); partOrder.add(part); }
                    PartCount pc = r.byPart.get(part);
                    if (pc == null) {
                        pc = new PartCount();
                        pc.filled = 0; pc.total = 0; pc.missing = new List<String>();
                        r.byPart.put(part, pc);
                    }
                    pc.total++;
                    if (isFilled) pc.filled++;
                    else          pc.missing.add(fid);
                }
            }
        }

        r.filled  = r.filledFieldIds.size();
        r.total   = r.requiredFieldIds.size();
        r.percent = (r.total == 0) ? null : (Decimal.valueOf(r.filled) / r.total * 100).setScale(1);

        // Missing Parts, in flow order.
        for (String p : partOrder) {
            PartCount pc = r.byPart.get(p);
            if (pc != null && pc.missing != null && !pc.missing.isEmpty()) r.missingParts.add(p);
        }

        // Second pass — blocked fields (fields whose gate refers to an unanswered gateId).
        Set<String> answeredIds = new Set<String>();
        for (String k : answers.keySet()) {
            String v = answers.get(k);
            if (v != null && v != '') answeredIds.add(k);
        }
        collectBlocked(answers, answeredIds, seenReq, r);

        return r;
    }

    private static Boolean isTerminal(Map<String, Object> page) {
        if (asBool(page.get('stop'))) return true;
        if (asBool(page.get('exit'))) return true;
        if (asBool(page.get('summary'))) return true;
        if (asBool(page.get('declaration'))) return true;
        if (asBool(page.get('confirmation'))) return true;
        String part = (String) page.get('part');
        if (part == 'Check your answers' || part == 'Application complete') return true;
        return false;
    }

    private static Boolean isFieldFilled(Map<String, String> A, Map<String, Object> f, String fid) {
        String type = (String) f.get('type');
        if (type == 'date') {
            String d = A.get(fid + '_day');
            String m = A.get(fid + '_month');
            String y = A.get(fid + '_year');
            return isNonEmpty(d) && isNonEmpty(m) && isNonEmpty(y);
        }
        String v = A.get(fid);
        if (!isNonEmpty(v)) return false;
        if (type == 'checkboxes') {
            // JSON array with at least one entry.
            try {
                Object parsed = JSON.deserializeUntyped(v);
                if (parsed instanceof List<Object>) return !((List<Object>) parsed).isEmpty();
            } catch (Exception ignore) {}
            return v.trim().length() > 0 && v.trim() != '[]';
        }
        return true;
    }

    private static Boolean isNonEmpty(String v) {
        return v != null && v.trim().length() > 0;
    }

    // ── Blocked-field pass ───────────────────────────────────────────────

    private static void collectBlocked(Map<String, String> A, Set<String> answered, Set<String> alreadyRequired, ProgressResult r) {
        Set<String> seen = new Set<String>();
        for (Object po : PAGES_CACHE) {
            walkForBlocked((Map<String, Object>) po, '', A, answered, alreadyRequired, seen, r);
        }
    }

    private static void walkForBlocked(Map<String, Object> page, String prefix,
                                       Map<String, String> A, Set<String> answered,
                                       Set<String> alreadyRequired, Set<String> seen,
                                       ProgressResult r) {
        if (isTerminal(page)) return;

        // Loop pages — walk inner pages once with placeholder prefix "s1_".
        String loopName = (String) page.get('loop');
        Object pagesInner = page.get('pages');
        if (String.isNotBlank(loopName) && pagesInner instanceof List<Object>) {
            String pfx = loopName.substring(0, 1) + '1_';
            for (Object po : (List<Object>) pagesInner) {
                walkForBlocked((Map<String, Object>) po, pfx, A, answered, alreadyRequired, seen, r);
            }
            return;
        }

        List<Object> pageConds = (List<Object>) page.get('cond');
        Set<String> pageGates = gatesReferenced(pageConds, prefix);

        Object fieldsObj = page.get('fields');
        if (!(fieldsObj instanceof List<Object>)) return;
        for (Object fo : (List<Object>) fieldsObj) {
            Map<String, Object> f = (Map<String, Object>) fo;
            if (asBool(f.get('optional'))) continue;
            if (asBool(f.get('hidden'))) continue;   // Phase 0.1: hidden fields never surface as blocked
            String rawId = (String) f.get('id');
            if (String.isBlank(rawId)) continue;
            String fid = resolveId(rawId, prefix);
            if (DECLARATION_IDS.contains(fid)) continue;
            if (alreadyRequired.contains(fid)) continue; // already counted
            if (seen.contains(fid)) continue;

            Set<String> gates = new Set<String>();
            gates.addAll(pageGates);
            gates.addAll(gatesReferenced((List<Object>) f.get('cond'), prefix));
            List<String> unanswered = new List<String>();
            for (String g : gates) {
                if (!answered.contains(g)) unanswered.add(g);
            }
            if (unanswered.isEmpty()) continue; // no unanswered gate → not blocked

            seen.add(fid);
            r.blockedFieldIds.add(fid);

            // Build a human-friendly reason. Prefer the gate label; fall back
            // to the raw id when the label is missing. If multiple gates block
            // this field, enumerate up to 2 and append "… and N more".
            String primary = unanswered[0];
            String primaryLabel = LABEL_BY_ID_CACHE.get(primary);
            String reason;
            if (unanswered.size() == 1) {
                reason = 'Requires an answer to '
                    + (String.isNotBlank(primaryLabel) ? primaryLabel : primary)
                    + ' (' + primary + ')';
            } else {
                String secondary = unanswered[1];
                String secondaryLabel = LABEL_BY_ID_CACHE.get(secondary);
                reason = 'Requires: '
                    + (String.isNotBlank(primaryLabel) ? primaryLabel : primary)
                    + ' · '
                    + (String.isNotBlank(secondaryLabel) ? secondaryLabel : secondary);
                if (unanswered.size() > 2) {
                    reason += ' … and ' + (unanswered.size() - 2) + ' more';
                }
            }
            r.blockedReasonById.put(fid, reason);
        }
    }

    private static Set<String> gatesReferenced(List<Object> conds, String prefix) {
        Set<String> out = new Set<String>();
        if (conds == null) return out;
        for (Object co : conds) {
            Map<String, Object> c = (Map<String, Object>) co;
            Object anyObj = c.get('any');
            if (anyObj instanceof List<Object>) {
                for (Object ao : (List<Object>) anyObj) {
                    Map<String, Object> sub = (Map<String, Object>) ao;
                    String sid = (String) sub.get('id');
                    if (String.isNotBlank(sid)) out.add(resolveId(sid, prefix));
                }
            } else {
                String cid = (String) c.get('id');
                if (String.isNotBlank(cid)) out.add(resolveId(cid, prefix));
            }
        }
        return out;
    }

    // ── Ported walker (buildFlow + condOK) ───────────────────────────────

    /** Byte-parallel port of flow.js:condOK. */
    private static Boolean condOK(Map<String, String> A, List<Object> conds, String prefix) {
        if (conds == null) return true;
        for (Object co : conds) {
            Map<String, Object> c = (Map<String, Object>) co;
            Object anyObj = c.get('any');
            if (anyObj instanceof List<Object>) {
                Boolean anyPass = false;
                for (Object ao : (List<Object>) anyObj) {
                    if (singleTest(A, (Map<String, Object>) ao, prefix)) { anyPass = true; break; }
                }
                if (!anyPass) return false;
            } else {
                if (!singleTest(A, c, prefix)) return false;
            }
        }
        return true;
    }

    private static Boolean singleTest(Map<String, String> A, Map<String, Object> x, String prefix) {
        String id = resolveId((String) x.get('id'), prefix);
        String v = A.get(id);
        // hasnot: array does NOT contain (also true when v is absent)
        if (x.containsKey('hasnot')) {
            String needle = String.valueOf(x.get('hasnot'));
            List<String> arr = parseCheckboxArray(v);
            return !(arr != null && arr.contains(needle));
        }
        // has: array contains
        if (x.containsKey('has')) {
            String needle = String.valueOf(x.get('has'));
            List<String> arr = parseCheckboxArray(v);
            return arr != null && arr.contains(needle);
        }
        // eq: strict equality
        Object eq = x.get('eq');
        if (eq == null) return v == null || v == '';
        return v == String.valueOf(eq);
    }

    private static List<String> parseCheckboxArray(String v) {
        if (v == null || v == '') return null;
        try {
            Object parsed = JSON.deserializeUntyped(v);
            if (parsed instanceof List<Object>) {
                List<String> out = new List<String>();
                for (Object o : (List<Object>) parsed) out.add(String.valueOf(o));
                return out;
            }
        } catch (Exception ignore) {}
        return null;
    }

    private static String resolveId(String id, String prefix) {
        if (String.isBlank(id)) return id;
        if (id.startsWith('@')) return (prefix == null ? '' : prefix) + id.substring(1);
        return id;
    }

    /** Port of flow.js:buildFlow. Returns an ordered list of instantiated page maps. */
    private static List<Map<String, Object>> buildFlow(Map<String, String> A) {
        List<Map<String, Object>> flow = new List<Map<String, Object>>();
        if (PAGES_CACHE == null || PAGES_CACHE.isEmpty()) return flow;

        String start = A.get('start');
        if (start == 'no') {
            flow.add(instantiate((Map<String, Object>) PAGES_CACHE[0], '', null, 0));
            if (PAGES_CACHE.size() > 1) {
                flow.add(instantiate((Map<String, Object>) PAGES_CACHE[1], '', null, 0));
            }
            return flow;
        }

        for (Object po : PAGES_CACHE) {
            Map<String, Object> tpl = (Map<String, Object>) po;
            if (asBool(tpl.get('stop'))) continue;

            // Loops
            String loopName = (String) tpl.get('loop');
            if (String.isNotBlank(loopName)) {
                if (!condOK(A, (List<Object>) tpl.get('cond'), '')) continue;
                Integer max = tpl.get('max') == null ? 1 : Integer.valueOf(tpl.get('max'));
                String addKey = (String) tpl.get('addKey');
                String letter = loopName.substring(0, 1);
                Integer i = 1;
                while (true) {
                    String pfx = letter + i + '_';
                    Object innerPages = tpl.get('pages');
                    if (innerPages instanceof List<Object>) {
                        for (Object ipo : (List<Object>) innerPages) {
                            Map<String, Object> p = (Map<String, Object>) ipo;
                            if (!condOK(A, (List<Object>) p.get('cond'), pfx)) continue;
                            flow.add(instantiate(p, pfx, tpl, i));
                        }
                    }
                    String addKeyI = (addKey == null ? 'add' : addKey) + '_' + i;
                    // Emit the "add another?" yesno page.
                    Map<String, Object> addPage = new Map<String, Object>{
                        'key' => addKeyI,
                        'part' => tpl.get('addPart'),
                        'blockInfo' => String.valueOf(tpl.get('label')) + ' ' + i + ' complete',
                        'fields' => new List<Object>{
                            new Map<String, Object>{ 'q' => '—', 'id' => addKeyI, 'label' => tpl.get('addTitle'), 'type' => 'yesno' }
                        }
                    };
                    flow.add(addPage);
                    String v = A.get(addKeyI);
                    if (v != 'yes' || i >= max) break;
                    i++;
                }
                continue;
            }

            // Named-function gate
            String fnName = (String) tpl.get('fn');
            if (String.isNotBlank(fnName)) {
                if (fnName == 'partnerActive') {
                    if (A.get('q14') != 'yeslivetogether') continue;
                } else {
                    // Unknown fn — fail closed.
                    continue;
                }
            }
            if (!condOK(A, (List<Object>) tpl.get('cond'), '')) continue;
            // Phase 2.3 (boss brief 2026-08-18): a page marked
            // skipIfAnswered=true drops out of the flow once its first
            // non-hidden field already has an answer. Used by q0_country so
            // a postcode-derived country never counts as an unanswered
            // required field on the Progress bar.
            if (asBool(tpl.get('skipIfAnswered'))) {
                Object fieldsObjPre = tpl.get('fields');
                Boolean shouldSkip = false;
                if (fieldsObjPre instanceof List<Object>) {
                    for (Object fo : (List<Object>) fieldsObjPre) {
                        Map<String, Object> f = (Map<String, Object>) fo;
                        if (asBool(f.get('hidden'))) continue;
                        String rawId = (String) f.get('id');
                        if (String.isBlank(rawId)) continue;
                        String ans = A.get(rawId);
                        if (ans != null && ans != '') shouldSkip = true;
                        break;
                    }
                }
                if (shouldSkip) continue;
            }
            flow.add(instantiate(tpl, '', null, 0));
            if (asBool(tpl.get('exit'))) break;
        }
        return flow;
    }

    private static Map<String, Object> instantiate(Map<String, Object> tpl, String prefix, Map<String, Object> loopTpl, Integer idx) {
        // Shallow clone, but rewrite fields' ids if prefix is non-empty (loop instances).
        Map<String, Object> out = new Map<String, Object>();
        for (String k : tpl.keySet()) out.put(k, tpl.get(k));
        if (String.isBlank(prefix)) {
            out.put('prefix', '');
            return out;
        }
        out.put('prefix', prefix);
        out.put('key', prefix + String.valueOf(tpl.get('key')));
        if (loopTpl != null) {
            out.put('part', loopTpl.get('addPart'));
            out.put('blockInfo', String.valueOf(loopTpl.get('label')) + ' ' + idx);
        }
        Object fieldsObj = tpl.get('fields');
        if (fieldsObj instanceof List<Object>) {
            List<Object> newFields = new List<Object>();
            for (Object fo : (List<Object>) fieldsObj) {
                Map<String, Object> f = (Map<String, Object>) fo;
                Map<String, Object> nf = new Map<String, Object>();
                for (String k : f.keySet()) nf.put(k, f.get(k));
                nf.put('id', resolveId((String) f.get('id'), prefix));
                Object fcond = f.get('cond');
                if (fcond instanceof List<Object>) {
                    List<Object> newConds = new List<Object>();
                    for (Object co : (List<Object>) fcond) {
                        Map<String, Object> c = (Map<String, Object>) co;
                        Map<String, Object> nc = new Map<String, Object>();
                        for (String k : c.keySet()) nc.put(k, c.get(k));
                        if (c.get('id') != null) nc.put('id', resolveId((String) c.get('id'), prefix));
                        newConds.add(nc);
                    }
                    nf.put('cond', newConds);
                }
                newFields.add(nf);
            }
            out.put('fields', newFields);
        }
        return out;
    }

    private static Boolean asBool(Object o) {
        if (o == null) return false;
        if (o instanceof Boolean) return (Boolean) o;
        return String.valueOf(o) == 'true';
    }

    // ── JSON payload builder for Progress_Missing_Sections__c ────────────

    private static String buildMissingSectionsJson(ProgressResult r) {
        Map<String, Object> payload = new Map<String, Object>();
        Integer missCount = r.missingFieldIds == null ? 0 : r.missingFieldIds.size();
        Boolean modeFields = missCount < 10;
        payload.put('mode', modeFields ? 'fields' : 'sections');
        payload.put('filled', r.filled);
        payload.put('total', r.total);

        // Always include the compact "missing" list of ids + labels (so the LWC
        // can render fields mode without a second query).
        List<Object> missing = new List<Object>();
        if (r.missingFieldIds != null) {
            for (String fid : r.missingFieldIds) {
                Map<String, Object> item = new Map<String, Object>();
                item.put('id', fid);
                item.put('label', r.labelById.get(fid));
                item.put('part', r.partByFieldId.get(fid));
                missing.add(item);
            }
        }
        payload.put('missing', missing);
        payload.put('sections', r.missingParts == null ? new List<String>() : r.missingParts);

        // Blocked map (fieldId → reason) — for the LWC to display in phase 3.
        payload.put('blocked', r.blockedReasonById == null ? new Map<String, String>() : r.blockedReasonById);

        String json = JSON.serialize(payload);
        // Long text hard cap is 32k — keep a safety margin.
        if (json.length() > 31500) json = json.substring(0, 31500) + '"...truncated"}';
        return json;
    }
}