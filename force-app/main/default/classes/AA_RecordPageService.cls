/**
 * AA_RecordPageService — @AuraEnabled bridge for the 5 record-page LWCs
 * (Header, PathBar, ApplicationData, CallHistory, StageTimeline).
 *
 * All read methods are `cacheable=true` so the framework can wire them and
 * refresh via `refreshApex`. Write methods (saveField, saveNotes, changeStage)
 * are non-cacheable and audit-trail via AA_Stage_Log__c where appropriate.
 * The legacy scheduleCall write was removed 2026-07-29 — scheduling now
 * flows through AA_Call_Schedule__c (Pending rows), not Next_Call_At__c.
 *
 * getFlowConfig() returns the raw aa-flow.json StaticResource body — the
 * ApplicationData LWC parses it client-side so we don't pay the JSON parse
 * cost on every render. saveField holds each answer to that catalogue
 * (normaliseAnswer) through AA_FlowEngine.flowPages(), the parse the answer
 * trigger's recompute uses too, so a save parses it once.
 */
public with sharing class AA_RecordPageService {

    // ── APPLICATION ──────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static AA_Application__c getApplication(Id recordId) {
        // Mary_Progress_Filled__c / _Total__c are retired (audit 2026-10-02
        // F44/F177): no LWC reads them, so they are no longer selected.
        // Mary_Progress_Complete__c stays: form.js and Mary write it.
        List<AA_Application__c> rows = [
            SELECT Id, Name, First_Name__c, Last_Name__c, Full_Name__c,
                   Email__c, Phone__c, DOB__c,
                   Address_Line1__c, Address_Line2__c, City__c, Postcode__c,
                   Notes__c, Stage__c, Stage_Changed_At__c, Next_Call_At__c,
                   DWP_Reference__c, Task_Instruction__c,
                   Progress_Filled__c, Progress_Total__c, Progress_Percent__c,
                   Mary_Progress_Complete__c,
                   CreatedDate
              FROM AA_Application__c
             WHERE Id = :recordId
             WITH USER_MODE
             LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    // ── ANSWERS (application data) ───────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<AA_Answer__c> getAnswers(Id recordId) {
        // audit 2026-10-02 F39: the LWC keys rows by Field_Id__c and the last
        // row wins, so oldest-first within an id makes the NEWEST duplicate the
        // one shown, the same winner AA_FlowEngine / AA_ApplicationFieldSync use.
        return [
            SELECT Id, Field_Id__c, Value__c, Source__c, Confidence__c, LastModifiedDate
              FROM AA_Answer__c
             WHERE Application__c = :recordId
             WITH USER_MODE
             ORDER BY Field_Id__c ASC, LastModifiedDate ASC, Id ASC
             LIMIT 1000
        ];
    }

    @AuraEnabled
    public static Id saveField(Id applicationId, String fieldId, String value, String source) {
        if (String.isBlank(fieldId)) throw new AuraHandledException('field_id is required');
        if (String.isBlank(source))  source = 'human';
        // audit 2026-10-02 F40/F58/F171: this path wrote any value verbatim,
        // while the Heroku paths (form, Mary) validate and normalise. Apply the
        // same NI / UK phone / UK postcode / email rules here, (e2e 2026-10-08
        // C5) the same option-code rules for radios and tick-boxes, and the
        // same entry-number, date-part and length limits.
        value = normaliseAnswer(applicationId, fieldId, value);
        rejectBareLoopSave(applicationId, fieldId);

        // Newest first: update the row every reader treats as current (F39).
        List<AA_Answer__c> existing = [
            SELECT Id FROM AA_Answer__c
             WHERE Application__c = :applicationId AND Field_Id__c = :fieldId
             WITH USER_MODE
             ORDER BY LastModifiedDate DESC, Id DESC
             LIMIT 1
        ];

        AA_Answer__c ans;
        if (!existing.isEmpty()) {
            ans = existing[0];
            ans.Value__c = value;
            ans.Source__c = source;
            update ans;
        } else {
            ans = new AA_Answer__c(
                Application__c = applicationId,
                Field_Id__c    = fieldId,
                Value__c       = value,
                Source__c      = source
            );
            insert ans;
        }
        // AA_MaryProgressCalculator.updateMaryProgress used to run here (audit
        // 2026-10-02 F44/F177): it counted every row against a hard-coded 70,
        // nothing reads Mary_Progress_*, and it cost an extra query plus an
        // Application update on every operator save. The real counters
        // (Progress_*) are recomputed by AA_AnswerTrigger.
        return ans.Id;
    }

    // ── ANSWER VALIDATION (twins of src/lib/mary-validator.js) ───────────

    // Twins of FORMAT_RULES / EMAIL_RE in src/lib/mary-validator.js (which
    // mirror public/validate.js). Keep the patterns in step with those files.
    private static final Set<String> NI_IDS = new Set<String>{
        'national-insurance', 'representative-national-insurance'
    };
    private static final Set<String> PHONE_IDS = new Set<String>{
        'main-contact-number', 'someone-else-number', 'gp-telephone',
        'healthcare-professional-telephone', 'representative-telephone-number'
    };
    private static final Set<String> POSTCODE_IDS = new Set<String>{
        'home-address-postcode', 'home-address-manual-postcode',
        'representative-address-postcode', 'representative-address-manual-postcode'
    };
    // mary-validator applies the email shape to text ids containing "email",
    // and (audit 2026-10-02 F10) to their "-confirm" twins; these are the four
    // such ids in the AA flow. Its other check, that a confirm matches the
    // address it confirms, needs the stored address and is not made here.
    private static final Set<String> EMAIL_IDS = new Set<String>{
        'contact-by-email', 'supporting-documents-email',
        'contact-by-email-confirm', 'supporting-documents-email-confirm'
    };
    private static final String NI_RE =
        '^(?!BG|GB|NK|KN|TN|NT|ZZ)[A-CEGHJ-PR-TW-Z][A-CEGHJ-NPR-TW-Z]\\d{6}[A-D]$';
    private static final String PHONE_RE = '^(?:0|\\+44|0044)[1-9]\\d{8,9}$';
    private static final String POSTCODE_RE = '^(GIR ?0AA|[A-Z]{1,2}\\d[A-Z\\d]? ?\\d[A-Z]{2})$';
    private static final String EMAIL_RE = '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$';
    // Repeating-block entries are saved as "<field>__<n>" (n 1-99, no leading
    // zero), as in src/lib/loop-folding.js LOOP_ID_RE.
    private static final Pattern LOOP_ID = Pattern.compile('^(.*)__([1-9][0-9]?)$');
    // DWP's repeating blocks take up to 20 entries ("You can add up to 20"),
    // and the fill can never type a 21st. Twin of mary-validator MAX_LOOP_ENTRY.
    private static final Integer MAX_LOOP_ENTRY = 20;
    // AA_Answer__c.Value__c is a Text Area(4000): mary-validator MAX_ANSWER_CHARS.
    private static final Integer MAX_ANSWER_CHARS = 4000;
    // One part of a date: "<stem>-day" / "-month" / "-year" from the generic
    // date editor, "decldate_day" / "_month" / "_year" for the declaration
    // date (aaApplicationData datePartId). Only when the stem is a catalogue
    // date: bed-day, wash-day and the like are questions of their own.
    private static final Pattern DATE_PART = Pattern.compile('^(.+)[-_](day|month|year)$');

    /**
     * DWP's own character limits ("You can enter up to 200 characters"), twin
     * of the maxLength mary-validator reads from the page copy in
     * config/aa-flow.json (audit 2026-10-02 F172: a longer answer saved, and
     * the live fill halted on that page). The aaFlowConfig static resource
     * carries no page copy, so the list lives here. Keep in step.
     */
    private static final Map<String, Integer> DWP_MAX_CHARS = new Map<String, Integer>{
        'aids-adaptations-reason-other'                         => 200,
        'bed-position-typically-how-long'                       => 200,
        'care-home-hospital-overnight-information'              => 500,
        'medication-typically-how-long'                         => 200,
        'safe-day-why-something-else'                           => 200,
        'something-else-bed-day-why-explain'                    => 200,
        'something-else-dress-day-why-explain'                  => 200,
        'something-else-eating-drinking-day-explain'            => 200,
        'something-else-eating-drinking-day-why-explain'        => 200,
        'something-else-explain'                                => 200,
        'something-else-explain-bed'                            => 200,
        'something-else-explain-bed-night'                      => 200,
        'something-else-explain-communication'                  => 200,
        'something-else-explain-dressing'                       => 200,
        'something-else-explain-medication'                     => 200,
        'something-else-explain-medication-night'               => 200,
        'something-else-explain-social'                         => 200,
        'something-else-explain-stairs'                         => 200,
        'something-else-explain-toilet'                         => 200,
        'something-else-explain-toilet-night'                   => 200,
        'something-else-explain-washing'                        => 200,
        'something-else-falling-explain'                        => 200,
        'something-else-medication-treatment-day-why-explain'   => 200,
        'something-else-medication-treatment-night-why-explain' => 200,
        'something-else-moving-around-why-explain'              => 200,
        'something-else-toilet-day-why-explain'                 => 200,
        'something-else-toilet-night-why-explain'               => 200,
        'something-else-wash-day-why-explain'                   => 200,
        'toilet-typically-how-long'                             => 200,
        'treatment-surgery-information'                         => 200,
        'turning-over-typically-how-long'                       => 200
    };

    /**
     * Loop member id (or date stem) -> loop group, mirroring
     * src/lib/loop-folding.js MEMBER_TO_GROUP (derived there from
     * config/aa-flow.json LOOP_CLEAR + LOOP_SNAPSHOT; the SF static resource
     * carries no loop metadata, so the list lives here). Keep in step.
     */
    private static final Map<String, String> LOOP_GROUP_BY_MEMBER = new Map<String, String>{
        'health-conditions'                 => 'health-conditions',
        'health-conditions-manual'          => 'health-conditions',
        'health-conditions-start-date'      => 'health-conditions',
        'aids-adaptations-2'                => 'aids-adaptations-2',
        'aids-adaptations-difficulty-2'     => 'aids-adaptations-2',
        'healthcare-professional-name'      => 'healthcare-professional-name',
        'place-of-work'                     => 'healthcare-professional-name',
        'healthcare-professional-telephone' => 'healthcare-professional-name'
    };

    // Field types whose answer is ONE option code (mary-validator radio /
    // select / yesno); a 'checkboxes' answer is a JSON list of codes.
    private static final Set<String> SINGLE_CHOICE_TYPES = new Set<String>{ 'radio', 'select', 'yesno' };

    // care-needs-cause asks which of the client's OWN conditions cause the
    // care needs. Its only catalogue option is none-of-these; DWP and the
    // client form build the others from the conditions entered (aaFlowConfig
    // dynamicOptions). Twins of mary-validator CARE_NEEDS_CAUSE_ID,
    // NONE_OF_THESE and CONDITION_ID_RE.
    private static final String CARE_NEEDS_CAUSE_ID = 'care-needs-cause';
    private static final String NONE_OF_THESE = 'none-of-these';
    private static final Pattern CONDITION_ID = Pattern.compile('^health-conditions(-manual)?(__[1-9][0-9]?)?$');

    /** What an answer is held to, from its field's catalogue definition. */
    @TestVisible
    private class FieldRule {
        public String type;          // catalogue type: radio, checkboxes, text, textarea, date, ...
        public String label;         // the question, as the record page shows it
        public Boolean ticked;       // checkboxes: a JSON list of codes, else one code
        public List<String> codes;   // option codes as the catalogue spells them; null: not an option answer
        public FieldRule(String type, String label) {
            this.type = type;
            this.label = label;
            this.ticked = false;
        }
    }

    // Catalogue field id -> FieldRule, built once per transaction (fieldRules).
    @TestVisible private static Map<String, FieldRule> FIELD_RULE_CACHE;

    /**
     * Validate and normalise one answer value the way the Heroku save paths do
     * (mary-validator validateSave). Returns the value to store (NI and
     * postcode upper-cased the DWP way, email with whitespace removed, phone
     * and date parts trimmed, an option answer as the code the catalogue
     * spells, other text as typed) and throws AuraHandledException with a
     * plain message when DWP would refuse the value or it does not fit the
     * Value__c column. A blank value is always allowed: it clears the answer,
     * as a clear on the client form does, and whitespace alone counts as
     * blank (returned as ''). Loop entries ("<field>__<n>", n 1 to 20) are
     * checked against their base field. Without an application,
     * care-needs-cause takes any condition name, as validateSave does without
     * the answers.
     */
    public static String normaliseAnswer(String fieldId, String value) {
        return normaliseAnswer(null, fieldId, value);
    }

    /** As above, holding care-needs-cause to the application's own conditions. */
    public static String normaliseAnswer(Id applicationId, String fieldId, String value) {
        // Whitespace alone ('   ', a tab, a newline) came back as the value to
        // store, on every id (review 2026-10-08), and only the org's save made
        // it null. validateSave never stores it (free text of only whitespace
        // is an empty answer there), so it is a clear here, exactly as '' is.
        // String.isBlank misses the no-break spaces (U+00A0, U+2007, U+202F)
        // and U+FEFF, which JS trim strips and the org stores as sent, so
        // space separators are dropped before the test.
        if (value == null) return null;
        if (String.isBlank(value.replaceAll('[\\p{Z}\\uFEFF]', ''))) return '';
        if (String.isBlank(fieldId)) return value;
        String base = entryBase(fieldId);
        String stored = normaliseValue(applicationId, base, value);
        // audit 2026-10-02 E3/F176: a longer value reached the insert, and the
        // LWC showed the raw DmlException.
        if (stored.length() > MAX_ANSWER_CHARS) {
            throwInvalid('Salesforce saves up to ' + MAX_ANSWER_CHARS + ' characters per answer. This answer to '
                + questionName(base) + ' has ' + stored.length() + ' characters. Shorten it and save again.');
        }
        return stored;
    }

    /**
     * The field an answer id belongs to: the base of a "<field>__<n>" entry,
     * else the id itself. As in validateSave (audit 2026-10-02 F30d), the
     * entry number is a whole number from 1 to MAX_LOOP_ENTRY with no leading
     * zero. Blank values never get here, so an entry saved before the cap can
     * still be cleared.
     */
    private static String entryBase(String fieldId) {
        Integer cut = fieldId.lastIndexOf('__');
        if (cut < 0) return fieldId;
        Matcher lm = LOOP_ID.matcher(fieldId);
        if (!lm.matches()) {
            throwInvalid('Entries of ' + questionName(fieldId.left(cut)) + ' are numbered 1 to ' + MAX_LOOP_ENTRY
                + ', so entry "' + fieldId.substring(cut + 2) + '" cannot be saved.');
        }
        Integer n = Integer.valueOf(lm.group(2));
        if (n > MAX_LOOP_ENTRY) {
            throwInvalid(questionName(lm.group(1)) + ' takes up to ' + MAX_LOOP_ENTRY + ' entries on the DWP form, so entry '
                + n + ' cannot be saved. Keep the ' + MAX_LOOP_ENTRY + ' that matter most.');
        }
        return lm.group(1);
    }

    /** normaliseAnswer for a non-blank value, by the field the answer belongs to. */
    private static String normaliseValue(Id applicationId, String base, String value) {
        String raw = value.trim();
        if (NI_IDS.contains(base)) {
            String ni = raw.toUpperCase().replaceAll('\\s+', '');
            if (!Pattern.matches(NI_RE, ni)) {
                throwInvalid('Enter a National Insurance number in the correct format: two letters, six digits, then one letter A to D, for example AB 12 34 56 C.');
            }
            return ni;
        }
        if (PHONE_IDS.contains(base)) {
            if (!Pattern.matches(PHONE_RE, raw.replaceAll('[\\s\\-().]', ''))) {
                throwInvalid('Enter a UK telephone number, like 01632 960001, 07700 900982 or +44 20 7946 0000. DWP rejects non-UK numbers.');
            }
            return raw;
        }
        if (POSTCODE_IDS.contains(base)) {
            String pc = raw.toUpperCase();
            if (!Pattern.matches(POSTCODE_RE, pc)) {
                throwInvalid('Enter a real UK postcode, like SW1A 2AA.');
            }
            return pc;
        }
        if (EMAIL_IDS.contains(base)) {
            String em = raw.replaceAll('\\s+', '');
            if (!Pattern.matches(EMAIL_RE, em)) {
                throwInvalid('Enter an email address, like name@example.com.');
            }
            return em;
        }
        Map<String, FieldRule> rules = fieldRules();
        FieldRule rule = rules.get(base);
        if (rule == null) {
            // A day of 32 or a year of 19 was stored as sent; validateSave
            // range-checks every date part (audit 2026-10-02 F38).
            Matcher dm = DATE_PART.matcher(base);
            FieldRule stem = dm.matches() ? rules.get(dm.group(1)) : null;
            if (stem != null && stem.type == 'date') return normaliseDatePart(dm.group(1), dm.group(2), raw);
        }
        if (rule == null || rule.codes == null) {
            // Text, textarea, date stems and ids outside the catalogue
            // (health-conditions-rows) are stored as sent, within DWP's own
            // character limit where its page sets one, counted without the
            // surrounding spaces as validateSave counts it.
            Integer max = DWP_MAX_CHARS.get(base);
            if (max != null && raw.length() > max) {
                throwInvalid('The DWP form takes up to ' + max + ' characters for ' + questionName(base)
                    + '. This answer has ' + raw.length() + ' characters. Shorten it and save again.');
            }
            return value;
        }
        // e2e 2026-10-08 C5: radio and tick-box answers were stored as sent
        // ('mars' as residence-country, a bare code on a tick-box question)
        // although validateSave refuses them on the client form and in Mary.
        if (rule.ticked) return normaliseTicked(applicationId, base, raw, rule.codes);
        String code = canonCode(rule.codes, raw);
        if (code == null) {
            throwInvalid((raw.startsWith('[')
                    ? questionName(base) + ' takes one option, not a list.'
                    : '"' + raw + '" is not an option for ' + questionName(base) + '.')
                + ' Choose one of: ' + String.join(rule.codes, ', ') + '.');
        }
        return code;
    }

    /**
     * One part of a catalogue date, held to the ranges validateSave uses: day
     * 1 to 31, month 1 to 12, year 4 digits from 1900 to 2099, and no later
     * than this year for a date of birth. Digits only; leading zeros pass
     * ("08"), and the part is stored trimmed. Whether the three parts make a
     * real date takes all three: the record page's date editor checks that
     * before it saves them (aaDataRules checkDateParts).
     */
    private static String normaliseDatePart(String stem, String part, String raw) {
        Integer lo = part == 'year' ? 1900 : 1;
        Integer hi = part == 'day' ? 31 : part == 'month' ? 12
            : (stem == 'birth-date' || stem.endsWith('-birth-date') ? Date.today().year() : 2099);
        Boolean ok = Pattern.matches('[0-9]+', raw) && (part != 'year' || raw.length() == 4);
        if (ok) {
            Decimal n = Decimal.valueOf(raw);
            ok = n >= lo && n <= hi;
        }
        if (!ok) {
            throwInvalid('The ' + part + ' of ' + questionName(stem) + ' must be '
                + (part == 'year' ? '4 digits from ' : 'a number from ') + lo + ' to ' + hi + ', not "' + raw + '".');
        }
        return raw;
    }

    /** The question an answer id belongs to, in quotes, as the record page labels it (else the id). */
    private static String questionName(String id) {
        FieldRule rule = fieldRules().get(id);
        return '"' + (rule != null && String.isNotBlank(rule.label) ? rule.label : id) + '"';
    }

    /**
     * Answer rules from the aaFlowConfig catalogue, built once per transaction
     * from AA_FlowEngine.flowPages(). That is the parse the AA_AnswerTrigger
     * recompute uses, so a save parses the ~200 KB resource once (it parsed it
     * a second time here before). A missing resource gives no rules
     * (AA_FlowEngine's empty fallback): every answer passes as before.
     */
    private static Map<String, FieldRule> fieldRules() {
        if (FIELD_RULE_CACHE == null) FIELD_RULE_CACHE = fieldRulesFrom(AA_FlowEngine.flowPages());
        return FIELD_RULE_CACHE;
    }

    /**
     * Rules from the catalogue's PAGES[].fields[], read the way AA_FlowEngine
     * reads them (the first definition of an id wins, as in mary-validator's
     * index): each field's type and label, and the codes an option answer is
     * held to. Every checkboxes field gets codes, and so does a radio / select
     * / yesno with at least one option. A single-choice field without usable
     * options is edited as free text by the LWC, and the postcode lookup
     * pickers (*-address-select) stay free text as in mary-validator: the fill
     * takes "1" (the first lookup result) or the address exactly as DWP lists it.
     */
    @TestVisible
    private static Map<String, FieldRule> fieldRulesFrom(List<Object> pages) {
        Map<String, FieldRule> rules = new Map<String, FieldRule>();
        if (pages == null) return rules;
        for (Object po : pages) {
            Object fieldsObj = ((Map<String, Object>) po).get('fields');
            if (!(fieldsObj instanceof List<Object>)) continue;
            for (Object fo : (List<Object>) fieldsObj) {
                Map<String, Object> f = (Map<String, Object>) fo;
                String id = (String) f.get('id');
                if (String.isBlank(id) || rules.containsKey(id)) continue;
                FieldRule rule = new FieldRule((String) f.get('type'), (String) f.get('label'));
                List<String> codes = rule.type == 'yesno' ? new List<String>{ 'yes', 'no' } : optionCodes(f.get('options'));
                if (rule.type == 'checkboxes') {
                    rule.ticked = true;
                    rule.codes = codes;
                } else if (SINGLE_CHOICE_TYPES.contains(rule.type) && !codes.isEmpty() && !id.endsWith('-address-select')) {
                    rule.codes = codes;
                }
                rules.put(id, rule);
            }
        }
        return rules;
    }

    /** Codes of [code, label] option pairs, skipping blank codes as the LWC's cleanOptions does. */
    private static List<String> optionCodes(Object options) {
        List<String> codes = new List<String>();
        if (!(options instanceof List<Object>)) return codes;
        for (Object o : (List<Object>) options) {
            Object code = o;
            if (o instanceof List<Object>) {
                List<Object> pair = (List<Object>) o;
                code = pair.isEmpty() ? null : pair[0];
            }
            if (isScalar(code) && String.isNotBlank(String.valueOf(code))) codes.add(String.valueOf(code));
        }
        return codes;
    }

    /**
     * The code matching value exactly, else ignoring case, else null. Twin of
     * mary-validator canonCode: DWP spells aids-adaptations-difficulty-2's
     * codes 'Yes' / 'No', so 'no' is stored as 'No'.
     */
    private static String canonCode(List<String> codes, String value) {
        String s = value == null ? '' : value.trim();
        for (String c : codes) {
            if (c.equals(s)) return c;
        }
        for (String c : codes) {
            if (c.equalsIgnoreCase(s)) return c;
        }
        return null;
    }

    /**
     * A tick-box answer: a JSON list whose entries are all option codes,
     * stored as the catalogue spells them. An empty list passes, as in
     * validateSave (the LWC itself saves an unticked box as blank).
     */
    private static String normaliseTicked(Id applicationId, String base, String raw, List<String> codes) {
        List<Object> ticked = null;
        if (raw.startsWith('[')) {
            try {
                Object parsed = JSON.deserializeUntyped(raw);
                if (parsed instanceof List<Object>) ticked = (List<Object>) parsed;
            } catch (Exception ignore) {}
        }
        if (ticked == null) {
            throwInvalid('Save the answer to ' + questionName(base) + ' as a list of the ticked options'
                + (codes.isEmpty() ? '' : ', like ["' + codes[0] + '"]') + '.');
        }
        if (base == CARE_NEEDS_CAUSE_ID) return normaliseCareNeedsCause(applicationId, ticked);
        if (codes.isEmpty()) return JSON.serialize(ticked);
        List<String> out = new List<String>();
        List<String> bad = new List<String>();
        for (Object o : ticked) {
            String code = isScalar(o) ? canonCode(codes, String.valueOf(o)) : null;
            if (code == null) bad.add(o == null ? 'null' : String.valueOf(o));
            else out.add(code);
        }
        if (!bad.isEmpty()) {
            throwInvalid('Not an option for ' + questionName(base) + ': "' + String.join(bad, '", "') + '". Choose from: '
                + String.join(codes, ', ') + '.');
        }
        return JSON.serialize(out);
    }

    /**
     * care-needs-cause: each entry is one of the client's own conditions
     * (matched ignoring case and repeated spaces, stored as the client saved
     * it), or none-of-these on its own. With no condition on file, or no
     * application, any non-empty name passes, as in validateSave: refusing a
     * real answer is the worse failure, and DWP checks it again at fill time.
     */
    private static String normaliseCareNeedsCause(Id applicationId, List<Object> ticked) {
        List<String> known = applicationId == null ? new List<String>() : conditionNames(applicationId);
        List<String> out = new List<String>();
        Set<String> kept = new Set<String>();
        List<String> bad = new List<String>();
        for (Object o : ticked) {
            String s = isScalar(o) ? String.valueOf(o).trim().replaceAll('\\s+', ' ') : '';
            String name;
            if (String.isBlank(s))                      name = null;
            else if (s.equalsIgnoreCase(NONE_OF_THESE)) name = NONE_OF_THESE;
            else if (known.isEmpty())                   name = s;
            else                                        name = matchCondition(known, s);
            if (name == null) bad.add(String.isBlank(s) ? '(blank)' : s);
            else if (kept.add(name)) out.add(name);
        }
        String choices = 'Choose from: '
            + (known.isEmpty() ? 'the client\'s own health conditions' : String.join(known, ', '))
            + ', or none-of-these on its own.';
        if (!bad.isEmpty()) {
            throwInvalid('Not one of the client\'s health conditions: "' + String.join(bad, '", "') + '". ' + choices);
        }
        if (out.isEmpty()) throwInvalid(questionName(CARE_NEEDS_CAUSE_ID) + ' needs at least one answer. ' + choices);
        if (out.size() > 1 && kept.contains(NONE_OF_THESE)) {
            throwInvalid('The answer to ' + questionName(CARE_NEEDS_CAUSE_ID) + ' cannot combine none-of-these with a condition. '
                + 'Save the conditions, or none-of-these on its own.');
        }
        return JSON.serialize(out);
    }

    /**
     * The client's own condition names, the first spelling seen winning
     * (ignoring case): the health-conditions-rows list the client form saves,
     * then health-conditions / health-conditions-manual and their "__<n>"
     * entries, newest row per id (F39). Twin of mary-validator
     * conditionNamesFromAnswers.
     */
    private static List<String> conditionNames(Id applicationId) {
        Map<String, String> latest = new Map<String, String>();
        for (AA_Answer__c a : [
            SELECT Field_Id__c, Value__c FROM AA_Answer__c
             WHERE Application__c = :applicationId AND Field_Id__c LIKE 'health-conditions%'
             WITH USER_MODE
             ORDER BY Field_Id__c ASC, LastModifiedDate ASC, Id ASC
             LIMIT 1000
        ]) {
            latest.put(a.Field_Id__c, a.Value__c);
        }
        List<String> names = new List<String>();
        Set<String> seen = new Set<String>();
        String rows = latest.get('health-conditions-rows');
        if (rows != null && rows.trim().startsWith('[')) {
            try {
                for (Object o : (List<Object>) JSON.deserializeUntyped(rows)) addCondition(names, seen, o);
            } catch (Exception ignore) {}
        }
        for (String fid : latest.keySet()) {
            if (CONDITION_ID.matcher(fid).matches()) addCondition(names, seen, latest.get(fid));
        }
        return names;
    }

    private static void addCondition(List<String> names, Set<String> seen, Object v) {
        if (!isScalar(v)) return;
        String s = String.valueOf(v).trim();
        if (s.length() > 0 && seen.add(s.toLowerCase())) names.add(s);
    }

    /** The known condition matching s ignoring case and repeated spaces, else null. */
    private static String matchCondition(List<String> known, String s) {
        String want = s.toLowerCase();
        for (String k : known) {
            if (k.toLowerCase().replaceAll('\\s+', ' ').equals(want)) return k;
        }
        return null;
    }

    /** Not null, and not a JSON object or list. */
    private static Boolean isScalar(Object o) {
        return o != null && !(o instanceof Map<String, Object>) && !(o instanceof List<Object>);
    }

    private static void throwInvalid(String msg) {
        // setMessage: a bare AuraHandledException reads 'Script-thrown
        // exception' to Apex callers (tests, the REST twins).
        AuraHandledException e = new AuraHandledException(msg);
        e.setMessage(msg);
        throw e;
    }

    /**
     * audit 2026-10-02 F34/F49/F168: repeating-block answers (health
     * conditions, aids, healthcare professionals) live as "<field>__<n>" rows.
     * The fill folds those into per-entry items that override the bare id, so
     * an operator edit saved under the BARE id was silently ignored whenever
     * entries exist. Refuse it with a message instead; the entry rows
     * ("<field>__1", "<field>__2", ...) are the ones to edit. With no entries
     * yet, the bare id still reaches the fill and stays allowed.
     */
    private static void rejectBareLoopSave(Id applicationId, String fieldId) {
        if (applicationId == null || LOOP_ID.matcher(fieldId).matches()) return;
        String loopGroup = loopGroupOf(fieldId);
        if (loopGroup == null) return;
        for (AA_Answer__c a : [
            SELECT Field_Id__c FROM AA_Answer__c
             WHERE Application__c = :applicationId
             WITH USER_MODE
             LIMIT 2000
        ]) {
            Matcher m = LOOP_ID.matcher(a.Field_Id__c == null ? '' : a.Field_Id__c);
            if (m.matches() && loopGroupOf(m.group(1)) == loopGroup) {
                throwInvalid('This answer is part of a repeating list (one entry per condition, aid or professional). '
                    + 'The client already has numbered entries, and the DWP fill uses those, so this change would be ignored. '
                    + 'Edit the numbered entry instead.');
            }
        }
    }

    /** Loop group of a bare member id or of one of its date parts, else null. */
    private static String loopGroupOf(String baseId) {
        if (LOOP_GROUP_BY_MEMBER.containsKey(baseId)) return LOOP_GROUP_BY_MEMBER.get(baseId);
        for (String suffix : new List<String>{ '-day', '-month', '-year' }) {
            if (baseId.endsWith(suffix)) {
                String stem = baseId.removeEnd(suffix);
                if (LOOP_GROUP_BY_MEMBER.containsKey(stem)) return LOOP_GROUP_BY_MEMBER.get(stem);
            }
        }
        return null;
    }

    // ── CALL HISTORY ─────────────────────────────────────────────────────

    /** Rows the Call History cards load; getCallHistoryCount says how many exist. */
    @TestVisible private static final Integer CALL_HISTORY_LIMIT = 50;

    /**
     * Newest calls first, with the rep (Rep_Name__c — AA_User has read).
     * Hidden: personalization-only placeholders that closed without a
     * conversation (an inbound ring that never connected, or a probe) — they
     * are not calls. One still in progress is shown (2026-10-29 audit).
     */
    @AuraEnabled(cacheable=true)
    public static List<AA_Call_Log__c> getCallHistory(Id recordId) {
        return [
            SELECT Id, Name, Direction__c, Started_At__c, Ended_At__c,
                   Duration_Min__c, Status__c, Voicemail_Left__c,
                   Detail__c, Task_Instruction__c, Rescheduled_To__c,
                   Conversation_Id__c, Source__c, Rep_Name__c, Transcript_URL__c,
                   Recording_URL__c, Summary__c, Personalization_Only__c
              FROM AA_Call_Log__c
             WHERE Application__c = :recordId
               AND (Personalization_Only__c = false OR Status__c = 'in_progress')
             WITH USER_MODE
             ORDER BY Started_At__c DESC NULLS LAST
             LIMIT :CALL_HISTORY_LIMIT
        ];
    }

    /** Same filter as getCallHistory, without the row limit. */
    @AuraEnabled(cacheable=true)
    public static Integer getCallHistoryCount(Id recordId) {
        return [
            SELECT COUNT() FROM AA_Call_Log__c
             WHERE Application__c = :recordId
               AND (Personalization_Only__c = false OR Status__c = 'in_progress')
             WITH USER_MODE
        ];
    }

    // ── STAGE TIMELINE ───────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<AA_Stage_Log__c> getStageHistory(Id recordId) {
        return [
            SELECT Id, From_Stage__c, To_Stage__c, Actor__c, Note__c,
                   Changed_At__c, Changed_By__r.Name
              FROM AA_Stage_Log__c
             WHERE Application__c = :recordId
             WITH USER_MODE
             ORDER BY Changed_At__c DESC
             LIMIT 50
        ];
    }

    // ── STAGES (path bar) ────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<AA_Stage__mdt> getStages() {
        return [
            SELECT MasterLabel, DeveloperName, Order__c, Description__c,
                   Is_Terminal__c, Is_Human_Only__c
              FROM AA_Stage__mdt
             ORDER BY Order__c ASC
        ];
    }

    // ── FLOW CONFIG (aa-flow.json static resource) ──────────────────────

    @AuraEnabled(cacheable=true)
    public static String getFlowConfig() {
        List<StaticResource> rows = [SELECT Body FROM StaticResource WHERE Name = 'aaFlowConfig' LIMIT 1];
        if (rows.isEmpty()) return '{"PAGES":[]}';
        return rows[0].Body.toString();
    }

    // ── FILES (native ContentDocument) ───────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getFiles(Id recordId) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (ContentDocumentLink l : [
            SELECT ContentDocumentId,
                   ContentDocument.Title, ContentDocument.FileType,
                   ContentDocument.ContentSize, ContentDocument.CreatedDate,
                   ContentDocument.LastModifiedDate,
                   ContentDocument.LatestPublishedVersionId,
                   ContentDocument.OwnerId, ContentDocument.Owner.Name
              FROM ContentDocumentLink
             WHERE LinkedEntityId = :recordId
             ORDER BY ContentDocument.LastModifiedDate DESC
             LIMIT 200
        ]) {
            out.add(new Map<String, Object>{
                'id'             => l.ContentDocumentId,
                'title'          => l.ContentDocument.Title,
                'fileType'       => l.ContentDocument.FileType,
                'size'           => l.ContentDocument.ContentSize,
                'createdAt'      => l.ContentDocument.CreatedDate,
                'lastModified'   => l.ContentDocument.LastModifiedDate,
                'versionId'      => l.ContentDocument.LatestPublishedVersionId,
                'ownerId'        => l.ContentDocument.OwnerId,
                'ownerName'      => l.ContentDocument.Owner != null ? l.ContentDocument.Owner.Name : null
            });
        }
        return out;
    }

    /**
     * Delete a ContentDocument (removes the file from SF for everyone —
     * ContentDocument is org-wide, not per-record). Called from the aaFilesFull
     * / aaFilesCard row menu. Throws AuraHandledException with a friendly
     * message if the caller lacks delete permission on ContentDocument.
     */
    @AuraEnabled
    public static void deleteFile(Id contentDocumentId) {
        if (contentDocumentId == null) throw new AuraHandledException('Missing file id.');
        try {
            delete new ContentDocument(Id = contentDocumentId);
        } catch (DmlException e) {
            throw new AuraHandledException('Could not delete file: ' + e.getDmlMessage(0));
        }
    }

    // ── WRITES (notes / schedule / stage) ────────────────────────────────

    @AuraEnabled
    public static void saveNotes(Id applicationId, String notes) {
        update new AA_Application__c(Id = applicationId, Notes__c = notes);
    }

    // scheduleCall removed 2026-07-29 — writing Next_Call_At__c directly
    // bypasses the AA_Call_Schedule__c model (Pending rows + mirror trigger)
    // that everything else in the app now relies on. Scheduling flows come
    // in via aaCallSchedule LWC → AA_CallScheduleService.

    // ── CLIENTS LIST (home page) ─────────────────────────────────────────

    // Allowlist for the LWC's "stage:<Name>" filter keys: every Stage__c
    // picklist value, read from the field describe so it can never drift from
    // the picklist again. The hand-kept list this replaces drifted twice — it
    // stopped at 'Needs Human' after the 8 post-submission stages became
    // reachable (2026-09-09) and it carried 'Ready for Autofill', which was
    // never a Stage__c value — and because resolveFilter drops the WHERE for a
    // value it does not know, 'stage:Awarded' silently returned every client
    // (review-backlog 2026-09-11). Inactive values are kept on purpose: a
    // retired value can still sit on old records, and the value is only ever
    // bound (:stage), never concatenated, so nothing hostile gets through.
    private static final Set<String> KNOWN_STAGES = stagePicklistValues();

    private static Set<String> stagePicklistValues() {
        Set<String> out = new Set<String>();
        for (Schema.PicklistEntry e : Schema.SObjectType.AA_Application__c.fields.Stage__c.getPicklistValues()) {
            out.add(e.getValue());
        }
        return out;
    }

    /**
     * Resolve a filter key from the Clients LWC into a SOQL WHERE clause +
     * bind vars. Returns [whereSql, stageBind] — stageBind is non-null only
     * when the key is a 'stage:X' pattern the WHERE clause references as :stage.
     * Legacy shortcut keys (needs_human / awaiting_first_call / etc.) are
     * kept for backwards-compat with any bookmarked-state.
     */
    private static Map<String, Object> resolveFilter(String filter) {
        String f = String.isBlank(filter) ? 'all' : filter;
        String fLower = f.toLowerCase();
        String whereSql = '';
        String stageBind = null;

        if (f.startsWith('stage:')) {
            String stage = f.substring(6);
            if (KNOWN_STAGES.contains(stage)) {
                whereSql  = ' WHERE Stage__c = :stage';
                stageBind = stage;
            }
        } else if (fLower == 'needs_human')          whereSql = ' WHERE Stage__c = \'Needs Human\'';
        else if (fLower == 'awaiting_first_call')    whereSql = ' WHERE Stage__c = \'Awaiting First Call\'';
        else if (fLower == 'ready_for_review')       whereSql = ' WHERE Stage__c = \'Ready for Review\'';
        else if (fLower == 'ready_for_submit')       whereSql = ' WHERE Stage__c IN (\'Ready for Submit\',\'Reviewed\')';
        else if (fLower == 'my_clients')             whereSql = ' WHERE OwnerId = :currentUser';

        return new Map<String, Object>{ 'where' => whereSql, 'stage' => stageBind };
    }

    /**
     * getClientsList — list rows for the Attendance Allowance home-page Clients LWC.
     * Filter is 'all', 'my_clients', 'stage:<Any Picklist Value>', or one of
     * the legacy shortcut keys (needs_human / awaiting_first_call / etc).
     * Returns lightweight rows so 100+ clients render quickly. CreatedDate DESC.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getClientsList(String filter, Integer pageSize, Integer offset) {
        Integer lim  = (pageSize == null || pageSize <= 0 || pageSize > 200) ? 100 : pageSize;
        Integer skip = (offset == null || offset < 0) ? 0 : offset;
        Id currentUser = UserInfo.getUserId();
        Map<String, Object> f = resolveFilter(filter);
        String whereSql = (String) f.get('where');
        String stage    = (String) f.get('stage');

        String soql =
            'SELECT Id, Name, Full_Name__c, First_Name__c, Last_Name__c, ' +
            '       Phone__c, Stage__c, Next_Call_At__c, Notes__c, ' +
            '       Progress_Filled__c, Progress_Total__c, Progress_Percent__c, ' +
            '       CreatedDate ' +
            '  FROM AA_Application__c' +
            whereSql +
            ' ORDER BY CreatedDate DESC' +
            ' LIMIT :lim OFFSET :skip';

        List<AA_Application__c> rows = Database.query(soql);
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (AA_Application__c a : rows) {
            String descriptor = null;
            if (a.Notes__c != null) {
                String n = a.Notes__c.trim();
                if (n.length() > 0 && n.length() <= 80) descriptor = n;
                else if (n.length() > 80) descriptor = n.substring(0, 77) + '...';
            }
            out.add(new Map<String, Object>{
                'id'            => a.Id,
                'name'          => a.Name,
                'fullName'      => a.Full_Name__c,
                'descriptor'    => descriptor,
                'phone'         => a.Phone__c,
                'stage'         => a.Stage__c,
                'nextCallAt'    => a.Next_Call_At__c,
                'progressFilled'=> a.Progress_Filled__c,
                'progressTotal' => a.Progress_Total__c,
                'progressPct'   => a.Progress_Percent__c,
                'createdAt'     => a.CreatedDate
            });
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static Integer getClientsCount(String filter) {
        Id currentUser = UserInfo.getUserId();
        Map<String, Object> f = resolveFilter(filter);
        String whereSql = (String) f.get('where');
        String stage    = (String) f.get('stage');
        String soql = 'SELECT COUNT() FROM AA_Application__c' + whereSql;
        return Database.countQuery(soql);
    }

    @AuraEnabled
    public static void changeStage(Id applicationId, String newStage, String note) {
        // audit #10: a null/blank newStage used to clear Stage__c and log a
        // transition to null. Reject it — the picklist is restricted and an empty
        // stage is never a valid target.
        if (String.isBlank(newStage)) throw new AuraHandledException('A target stage is required.');
        List<AA_Application__c> rows = [SELECT Id, Stage__c FROM AA_Application__c WHERE Id = :applicationId LIMIT 1];
        if (rows.isEmpty()) throw new AuraHandledException('Application not found');
        // audit #55: the AA_Application trigger (AA_StageTransitionHelper) already
        // writes the AA_Stage_Log__c on every Stage__c change. Inserting our own
        // here produced TWO rows per change. Stash the note for the trigger and
        // let it log exactly once. (A no-op stage change now logs nothing — the
        // trigger short-circuits when Stage__c is unchanged, which is correct.)
        AA_StageTransitionHelper.noteByApp.put(
            applicationId, String.isBlank(note) ? 'Changed via record page' : note
        );
        update new AA_Application__c(
            Id = applicationId,
            Stage__c = newStage,
            Stage_Changed_At__c = Datetime.now()
        );
    }
}