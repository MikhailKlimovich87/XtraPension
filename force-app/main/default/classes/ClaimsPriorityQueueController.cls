/**
 * Claims Priority: what each validation agent should do next on the claims (Basic__c), one row per claim.
 * Read-only: it never writes. The work itself is done on the Claim page (and the DWP checks in the Claim Check tab).
 *
 * All the rules are in this class: the lanes (LANES), the waiting times (DAYS) and what each stage means (the stage
 * sets below). The "How it works" panel of the claimsPriorityQueue tab reads DAYS from here, so change a number only here.
 *
 * Lanes, in priority order (a claim can have several actions; the first due one is its lane)
 *   problem  the big envelope or the Stage 2 pack is stuck (ZIP or upload error, not sent, not posted by the printer)
 *   reply    the client wrote (email linked to the claim) or rang and nobody answered yet
 *   next     our move: Form completed / Agent Check (QC) / QC Approved, everything in on a Pending Client claim, Stage 2 to send
 *   call     Form In Progress / Validation Call: book the validation call, do it, then Send to Validation
 *   chase    Pending Client (or QC Approved with something missing): chase the client for what Missing Info lists
 *            (recomputed live with BP_MissingInfo for up to LIVE_MISSING_MAX claims; the saved Missing_Info__c after that)
 *   esign    Sent for eSignature: follow up 3 days after it went out, then 3 days after each contact with the client
 *   pack     the big envelope was posted to the client and the signed pages are not back at the printer
 *   dwp      with the DWP: only what needs the validation agent (DWP asked for more info, rejected, Agent Call, Charge DD)
 *   hold     On Hold: look again after a while
 * Stages left out (a client email or a missed call still shows): IGNORED_STAGES. A stage no rule knows shows as a problem.
 *
 * Owner: every action belongs to the claim's validation agent (Validation_Agent__c), except the QC of an Agent Check
 * claim and the DocuSign (send it at QC Approved, then chase it while Sent for eSignature), which belong to QC
 * (QC_OWNER, the "QC" entry of the agent list; the QC user's list opens on it, QC_USERNAMES). Call of 11/11/2026 17h13:
 * Fiona (QC) rechecks, sends the DocuSign and chases it, or asks the validation agent to chase.
 */
public with sharing class ClaimsPriorityQueueController {

    @TestVisible static final List<String> LANES = new List<String>{ 'problem', 'reply', 'next', 'call', 'chase', 'esign', 'pack', 'dwp', 'hold' };
    static final Map<String, String> LANE_LABELS = new Map<String, String>{
        'problem' => 'Fix a problem', 'reply' => 'Reply to the client', 'next' => 'Move it on', 'call' => 'Validation call',
        'chase' => 'Chase the client', 'esign' => 'DocuSign', 'pack' => 'Signed pack', 'dwp' => 'DWP and fee', 'hold' => 'On hold'
    };

    /** Waiting times in calendar days. Due = the start date of the step + these days. */
    @TestVisible static final Map<String, Integer> DAYS = new Map<String, Integer>{
        'stage1Send' => 1,        // big envelope (Stage 1 ZIP) uploaded to the printer, after the sale
        'printerPost' => 3,       // the printer posts the big envelope, after we upload it
        'bookCall' => 1,          // validation call booked, after the sale
        'afterCall' => 1,         // Send to Validation pressed, after the validation call
        'chaseFirst' => 0,        // first chase, after the claim goes Pending Client
        'chaseEvery' => 3,        // next chase, after the last contact
        'nextStep' => 1,          // Form completed, Agent Check (QC), QC Approved, Stage 2 to send: our move
        'esignFirst' => 3,        // 1st DocuSign follow-up, after the DocuSign went out
        'esignEvery' => 3,        // next follow-up, after the last contact with the client (REPLY_TYPES)
        'esignFollowUps' => 3,    // a count, not days: answered calls since the DocuSign went out before "decide what to do"
        'esignDecide' => 7,       // decide what to do, after the last contact
        'signedPack' => 14,       // signed pack back at the printer, after the printer posted the big envelope
        'signedPackFar' => 21,    // the same for Australia and New Zealand (FAR_COUNTRIES)
        'signedPackEvery' => 7,   // call again, after the last contact
        'stage2Post' => 3,        // the printer posts the claim to the DWP, after we upload the Stage 2 pack
        'agentCall' => 1,         // call the client about the DWP decision, after the claim goes Agent Call
        'chargeDd' => 2,          // charge our fee by direct debit, after the claim goes Charge DD
        'onHoldReview' => 30,     // look at an On Hold claim again, after it went On Hold or the last contact
        'emailWindow' => 30,      // client emails older than this are not looked at
        'callWindow' => 14,       // missed calls older than this are not looked at
        'upcoming' => 7           // "Upcoming" shows what becomes due within these days
    };

    @TestVisible static final Set<String> CALL_STAGES = new Set<String>{ 'Form In Progress', 'Validation Call' };
    static final String PENDING = 'Pending Client';
    @TestVisible static final Map<String, String> NEXT_STEPS = new Map<String, String>{
        'Form completed' => 'Check the forms and move the claim to Agent Check',
        'Agent Check' => 'QC the claim and move it to QC Approved',
        'QC Approved' => 'Send the DocuSign'
    };
    // QC is done by the QC person (Fernando, 11/11/2026: probably Fiona, but anyone may do it), not the validation agent
    @TestVisible static final String QC_OWNER = 'QC';
    static final String QC_STAGE = 'Agent Check';
    static final String QC_APPROVED = 'QC Approved';
    // Users whose agent list opens on QC: Fiona Carey's user is the QC mailbox
    @TestVisible static final Set<String> QC_USERNAMES = new Set<String>{ 'qc@xtrapension.com' };
    static final String ESIGN = 'Sent for eSignature';
    static final String SIGNED = 'Signed - Waiting Docs at WDM';
    // Before the DWP: the big envelope and the signed pack are followed in these stages
    @TestVisible static final Set<String> PACK_STAGES = new Set<String>{
        'Form In Progress', 'Validation Call', 'Form completed', 'Pending Client', 'Agent Check', 'QC Approved', ESIGN, SIGNED
    };
    // With the DWP: the check team follows these in the Claim Check tab; here only what the last check asks of us
    @TestVisible static final Set<String> DWP_STAGES = new Set<String>{
        'Posted to DWP', '45D Check', 'Awaiting Lump Sum Letter', 'Decision Posted to DWP', 'Awaiting DWP Payment'
    };
    static final String AGENT_CALL = 'Agent Call';
    static final String CHARGE_DD = 'Charge DD';
    static final String ON_HOLD = 'On Hold';
    @TestVisible static final Map<String, String> IGNORED_STAGES = new Map<String, String>{
        'Closed Won' => 'finished', 'Closed' => 'finished', 'Deposit Refund' => 'the deposit is being refunded'
    };
    static final Set<String> FAR_COUNTRIES = new Set<String>{ 'AU', 'NZ' };

    static final String COMPLETE = 'Form Fully Completed'; // BP_MissingInfo.COMPLETE
    static final String OUR_DOMAIN = '@xtrapension.com';
    // Last Contact types that answer the client (a missed call or a voicemail does not)
    static final Set<String> REPLY_TYPES = new Set<String>{ 'Phone Chat', 'Email Sent', 'Wapp Sent' };
    // Validation_Agent__c value -> the user's full name, when the user's first name is not the value
    @TestVisible static final Map<String, String> AGENT_USERS = new Map<String, String>{ 'Sean B' => 'Sean Byrne' };
    static final Integer MAX_CLAIMS = 2000;
    // Missing Info recomputed live (one SOQL per claim, BP_MissingInfo.load); after this many, the saved Missing_Info__c
    @TestVisible static final Integer LIVE_MISSING_MAX = 50;
    // Missing Info is recomputed live in these stages (QC Approved: the DocuSign is blocked while something is missing)
    static final Set<String> LIVE_MISSING_STAGES = new Set<String>{ 'Pending Client', 'QC Approved' };

    // Missing_Info__c line heads (before the colon) -> words for "Chase the client for: ..."
    static final Map<String, String> MISSING_WORDS = new Map<String, String>{
        'Bank' => 'bank details', 'UK employers' => 'UK employers', 'Countries lived' => 'countries lived',
        'UK residence' => 'UK residence dates', 'UK work' => 'UK work dates', 'Home address' => 'home address',
        'Name' => 'name', 'Title' => 'title', 'Date of birth' => 'date of birth', 'Phone' => 'phone number',
        'Email (needed to write to the client)' => 'email address', 'Marital status' => 'marital status', 'NINO' => 'NINO',
        'Date of marriage' => 'date of marriage', 'Date of civil partnership' => 'date of civil partnership',
        'Date of bereavement' => 'date of bereavement', 'Date of divorce' => 'date of divorce',
        'Date of separation' => 'date of separation', 'Pension start date' => 'pension start date',
        'Helper' => 'helper details', 'Children' => 'children', 'HM Forces' => 'HM Forces details'
    };
    static final Pattern SPOUSE_HEAD = Pattern.compile('^(Husband or wife|Husband|Wife|Civil partner|Late husband or wife|Late husband|Late wife|Former husband or wife|Former husband|Former wife)(, (.+))?$');
    static final Pattern CALL_DATE = Pattern.compile('(\\d{1,2})/(\\d{1,2})/(\\d{4})');

    @AuraEnabled(cacheable=false)
    public static QueueResult getQueue() {
        Date today = Date.today();
        Datetime emailSince = Datetime.newInstance(today.addDays(-DAYS.get('emailWindow')), Time.newInstance(0, 0, 0, 0));
        Datetime callSince = Datetime.newInstance(today.addDays(-DAYS.get('callWindow')), Time.newInstance(0, 0, 0, 0));

        // Claims in a stage this queue leaves out still show when the client wrote lately
        Set<Id> wrote = new Set<Id>();
        for (EmailMessage m : [
            SELECT Claim__c FROM EmailMessage
            WHERE Incoming = true AND Claim__c != null AND CreatedDate >= :emailSince
            ORDER BY CreatedDate DESC LIMIT :MAX_CLAIMS
        ]) {
            wrote.add(m.Claim__c);
        }
        Set<String> skipped = IGNORED_STAGES.keySet();

        QueueResult result = new QueueResult();
        List<Basic__c> claims = [
            SELECT Id, Name, First_Name__c, Last_Name__c, Phone__c, Status__c, Validation_Agent__c, CreatedDate,
                Deposit_Payment_Date__c, Missing_Info__c, Current_Address_Abroad_Country__c, Blocker__c, Val_Call_Booked_Date__c,
                Claim_Created_ZIP_for_UPLOAD__c, FTP_Claim_Created_Send_Date__c, FTP_Claim_Created_ZIP_Error__c, FTP_Claim_Created_Error__c,
                Big_Envelop_Posted_Date__c, Stage_1_Pack_Posted_Date__c, Big_Envelop_Tracking_Number__c,
                Claim_Full_Form_ZIP_for_UPLOAD__c, FTP_Claim_Full_Form_Created_Send_Date__c, FTP_Claim_Full_Form_ZIP_Error__c, FTP_Claim_Full_Form_Error__c,
                GoCardless_Mandate_Id__c, Last_Contact_At__c, Last_Contact_Date__c, Contact_Type__c, Who__c,
                (SELECT CreatedDate FROM Histories WHERE Field = 'Status__c' ORDER BY CreatedDate DESC LIMIT 1),
                (SELECT Check_Date__c, CreatedDate, Check_Agents__c, More_Info_Requested__c, Rejected__c, Notes__c
                 FROM Claim_Checks__r ORDER BY CreatedDate DESC LIMIT 1),
                (SELECT MessageDate, CreatedDate, Incoming, FromAddress, Subject, Has_message_been_processed__c
                 FROM Claim_Emails__r WHERE CreatedDate >= :emailSince ORDER BY CreatedDate DESC LIMIT 5),
                (SELECT Started_At__c, Direction__c, Outcome__c
                 FROM Call_Logs__r WHERE Started_At__c >= :callSince ORDER BY Started_At__c DESC LIMIT 3)
            FROM Basic__c
            WHERE Is_Test_Claim__c = false AND (Status__c NOT IN :skipped OR Id IN :wrote)
            ORDER BY CreatedDate DESC
            LIMIT :MAX_CLAIMS
        ];
        result.truncated = claims.size() == MAX_CLAIMS;
        result.claimsLooked = claims.size();

        Map<Id, Date> entered = new Map<Id, Date>();
        List<String> missingOrder = new List<String>(); // oldest in the stage first: "yyyy-MM-dd|Id"
        Map<Id, Date> esignSince = new Map<Id, Date>();
        for (Basic__c b : claims) {
            Date day = b.Histories.isEmpty() ? b.CreatedDate.date() : b.Histories[0].CreatedDate.date();
            entered.put(b.Id, day);
            if (LIVE_MISSING_STAGES.contains(b.Status__c)) missingOrder.add(String.valueOf(day) + '|' + b.Id);
            if (b.Status__c == ESIGN) esignSince.put(b.Id, day);
        }
        missingOrder.sort();
        List<Id> missingIds = new List<Id>();
        for (String key : missingOrder) missingIds.add((Id) key.substringAfter('|'));
        Map<Id, String> missing = liveMissing(missingIds);
        result.liveMissingCount = missing.size();
        result.savedMissingCount = missingIds.size() - missing.size();
        Map<Id, Integer> answered = answeredCallsSince(esignSince);

        for (Basic__c b : claims) {
            Claim_Check__c check = b.Claim_Checks__r.isEmpty() ? null : b.Claim_Checks__r[0];
            Item item = evaluate(b, entered.get(b.Id), check, b.Claim_Emails__r, b.Call_Logs__r, missing.get(b.Id), answered.get(b.Id), today);
            if (item != null) result.items.add(item);
        }
        result.items.sort();

        result.agents = new List<String>();
        for (Schema.PicklistEntry e : Basic__c.Validation_Agent__c.getDescribe().getPicklistValues()) {
            if (e.isActive()) result.agents.add(e.getValue());
        }
        String username = UserInfo.getUserName();
        result.me = username != null && QC_USERNAMES.contains(username.toLowerCase())
            ? QC_OWNER : agentFor(UserInfo.getFirstName(), UserInfo.getName(), result.agents);
        result.qcOwner = QC_OWNER;
        result.liveMissingMax = LIVE_MISSING_MAX;
        result.days = DAYS;
        result.laneLabels = LANE_LABELS;
        result.lanes = LANES;
        result.generatedAt = Datetime.now();
        return result;
    }

    /**
     * Missing Info as BP_MissingInfo sees the claim now (the same lines the Send to Validation and the DocuSign check use),
     * for up to LIVE_MISSING_MAX claims, in the order given. One SOQL per claim (BP_MissingInfo.load, with its countries,
     * employers and children). A claim left out, or one that fails, keeps its saved Missing_Info__c.
     */
    @TestVisible
    static Map<Id, String> liveMissing(List<Id> ids) {
        Map<Id, String> out = new Map<Id, String>();
        for (Id claimId : ids) {
            if (out.size() >= LIVE_MISSING_MAX || Limits.getQueries() >= Limits.getLimitQueries() - 10) break;
            try {
                List<String> lines = BP_MissingInfo.agentTexts(BP_MissingInfo.check(BP_MissingInfo.load(claimId)));
                out.put(claimId, lines.isEmpty() ? COMPLETE : String.join(lines, '; '));
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Missing Info not recomputed for ' + claimId + ': ' + e.getMessage());
            }
        }
        return out;
    }

    /** Answered calls (either way, Call_Log__c) since each claim's DocuSign went out. One SOQL, only when a claim is out for signature. */
    @TestVisible
    static Map<Id, Integer> answeredCallsSince(Map<Id, Date> sinceByClaim) {
        Map<Id, Integer> out = new Map<Id, Integer>();
        if (sinceByClaim.isEmpty()) return out;
        Date earliest;
        for (Date d : sinceByClaim.values()) {
            if (earliest == null || d < earliest) earliest = d;
        }
        Datetime fromAt = Datetime.newInstance(earliest, Time.newInstance(0, 0, 0, 0));
        Set<Id> claimIds = sinceByClaim.keySet();
        for (Call_Log__c call : [
            SELECT Claim__c, Started_At__c FROM Call_Log__c
            WHERE Claim__c IN :claimIds AND Outcome__c = 'Answered' AND Started_At__c >= :fromAt
            ORDER BY Started_At__c DESC LIMIT 5000
        ]) {
            if (call.Started_At__c.date() < sinceByClaim.get(call.Claim__c)) continue;
            out.put(call.Claim__c, (out.containsKey(call.Claim__c) ? out.get(call.Claim__c) : 0) + 1);
        }
        return out;
    }

    /** The Validation_Agent__c value of a user: the full name in AGENT_USERS, else the first name. Null when none fits. */
    @TestVisible
    static String agentFor(String firstName, String fullName, List<String> agents) {
        for (String value : AGENT_USERS.keySet()) {
            if (AGENT_USERS.get(value).equalsIgnoreCase(fullName == null ? '' : fullName.trim()) && agents.contains(value)) return value;
        }
        if (String.isBlank(firstName)) return null;
        for (String value : agents) {
            if (!AGENT_USERS.containsKey(value) && value.equalsIgnoreCase(firstName.trim())) return value;
        }
        return null;
    }

    /**
     * One claim against the rules: every action it needs, the first due one on top. Null when nothing is due within
     * DAYS.upcoming. entered = the day it moved to its stage; check = its last Claim Check; emails/calls newest first.
     */
    @TestVisible
    static Item evaluate(Basic__c b, Date entered, Claim_Check__c check, List<EmailMessage> emails, List<Call_Log__c> calls, Date today) {
        return evaluate(b, entered, check, emails, calls, null, null, today);
    }

    /** liveMissing: Missing Info recomputed now (null = use the saved Missing_Info__c); answeredCalls: since the DocuSign went out. */
    @TestVisible
    static Item evaluate(Basic__c b, Date entered, Claim_Check__c check, List<EmailMessage> emails, List<Call_Log__c> calls,
            String liveMissing, Integer answeredCalls, Date today) {
        String missingInfo = liveMissing != null ? liveMissing : b.Missing_Info__c;
        String savedNote = liveMissing != null ? '' : '; list as saved on the claim (open it to refresh)';
        String stage = b.Status__c == null ? '' : b.Status__c;
        Date created = b.CreatedDate == null ? today : b.CreatedDate.date();
        if (entered == null) entered = created;
        Date sale = b.Deposit_Payment_Date__c != null ? b.Deposit_Payment_Date__c : created;
        Ctx c = new Ctx(b, entered, today);
        List<Action> actions = new List<Action>();

        replies(c, emails, calls, actions);
        if (!IGNORED_STAGES.containsKey(stage)) {
            if (PACK_STAGES.contains(stage)) pack(c, sale, actions);
            if (CALL_STAGES.contains(stage)) {
                validationCall(c, sale, actions);
            } else if (stage == PENDING) {
                String missing = missingWords(missingInfo);
                if (missing == null) {
                    actions.add(c.action('next', 'Everything is in: press Send to Validation on the claim',
                        'Pending Client since ' + fmt(entered) + '; Missing Info says the form is complete' + savedNote + '.', entered, later(entered, c.contactDay()), 0));
                } else {
                    chase(c, 'Chase the client for: ' + missing, 'Pending Client since ' + fmt(entered) + savedNote, actions);
                }
            } else if (NEXT_STEPS.containsKey(stage)) {
                String missing = stage == QC_APPROVED ? missingWords(missingInfo) : null;
                if (missing != null) {
                    chase(c, 'Chase the client for: ' + missing + ' (the DocuSign is blocked until then)', 'QC Approved since ' + fmt(entered) + savedNote, actions);
                } else {
                    Action a = c.action('next', NEXT_STEPS.get(stage), stage + ' since ' + fmt(entered) + '.', entered, entered, DAYS.get('nextStep'));
                    // QC and the DocuSign are for QC (11/11/2026 17h13); a QC Approved claim with something missing stays a chase
                    if (stage == QC_STAGE || stage == QC_APPROVED) a.owner = QC_OWNER;
                    actions.add(a);
                }
            } else if (stage == ESIGN) {
                esign(c, answeredCalls, actions);
            } else if (stage == SIGNED) {
                // the pack rules above cover it
            } else if (DWP_STAGES.contains(stage)) {
                dwp(c, check, actions);
            } else if (stage == AGENT_CALL) {
                Date base = c.contactedSince(entered) ? c.contactDay() : entered;
                Integer wait = c.contactedSince(entered) ? DAYS.get('chaseEvery') : DAYS.get('agentCall');
                actions.add(c.action('dwp', 'Call the client about the DWP decision',
                    'Agent Call since ' + fmt(entered) + c.contactNote(entered) + '.', entered, base, wait));
            } else if (stage == CHARGE_DD) {
                actions.add(c.action('dwp', 'Charge our fee by direct debit'
                        + (String.isBlank(b.GoCardless_Mandate_Id__c) ? ': there is no direct debit mandate on the claim' : ''),
                    'Charge DD since ' + fmt(entered) + '.', entered, entered, DAYS.get('chargeDd')));
            } else if (stage == ON_HOLD) {
                Date base = later(entered, c.contactDay());
                actions.add(c.action('hold', 'On hold: check if it can move on',
                    'On Hold since ' + fmt(entered) + (String.isBlank(b.Blocker__c) ? '' : '. Blocker: ' + b.Blocker__c.abbreviate(200))
                        + c.contactNote(entered) + '.', entered, base, DAYS.get('onHoldReview')));
            } else if (stage == '') {
                actions.add(c.action('problem', 'The claim has no stage: set one', 'Status is empty.', entered, entered, 0));
            } else {
                actions.add(c.action('problem', 'Stage "' + stage + '" is new to this queue: tell Fernando',
                    'No rule in the Claims Priority queue for this stage yet.', entered, entered, 0));
            }
        }

        Integer upcoming = DAYS.get('upcoming');
        List<Action> kept = new List<Action>();
        for (Action a : actions) {
            if (a.daysOverdue >= -upcoming) kept.add(a);
        }
        if (kept.isEmpty()) return null;
        kept.sort();

        Item item = new Item();
        item.claimId = b.Id;
        item.name = b.Name;
        item.client = (nz(b.First_Name__c) + ' ' + nz(b.Last_Name__c)).trim();
        item.phone = b.Phone__c;
        item.stage = stage;
        item.agent = b.Validation_Agent__c;
        item.daysInStage = entered.daysBetween(today);
        item.lastContactAt = b.Last_Contact_At__c;
        item.lastContactDate = b.Last_Contact_Date__c;
        item.lastContactType = b.Contact_Type__c;
        item.lastContactWho = b.Who__c;
        item.actions = kept;
        Action top = kept[0];
        item.lane = top.lane;
        item.rank = top.rank;
        item.due = top.due;
        item.daysOverdue = top.daysOverdue;
        return item;
    }

    // ------------------------------------------------------------------ the rules, lane by lane

    /** reply: the newest client email not answered, and a missed call from the client not returned. */
    static void replies(Ctx c, List<EmailMessage> emails, List<Call_Log__c> calls, List<Action> actions) {
        if (emails != null) {
            EmailMessage newest, oldest;
            Integer count = 0;
            for (EmailMessage m : emails) { // newest first: stop at our last reply or at an email marked Done
                // a copy of our own email (clients@ or an agent's mailbox) also means we answered
                if (m.Incoming != true || nz(m.FromAddress).toLowerCase().endsWith(OUR_DOMAIN)) break;
                if (m.Has_message_been_processed__c == 'Done') break;
                Datetime at = m.MessageDate != null ? m.MessageDate : m.CreatedDate;
                if (c.repliedAfter(at)) break; // answered by phone, email or WhatsApp after it
                if (newest == null) newest = m;
                oldest = m;
                count++;
            }
            if (oldest != null) {
                Date since = (oldest.MessageDate != null ? oldest.MessageDate : oldest.CreatedDate).date();
                actions.add(c.action('reply', 'Reply to the client\'s email from ' + fmt(since),
                    '"' + nz(newest.Subject).abbreviate(120) + '"' + (count > 1 ? ' (' + count + ' emails waiting)' : '')
                        + '. Mark it Done if it was answered outside Salesforce.', since, since, 0));
            }
        }
        if (calls != null) {
            for (Call_Log__c call : calls) { // newest first
                if (call.Started_At__c == null) continue;
                if (call.Outcome__c == 'Answered') break; // spoke since
                if (call.Direction__c == 'Inbound' && call.Outcome__c == 'Missed') {
                    if (!c.repliedAfter(call.Started_At__c)) {
                        actions.add(c.action('reply', 'Call the client back: missed call on ' + call.Started_At__c.format('dd/MM/yyyy HH:mm'),
                            'The client rang and nobody answered; no contact since.', call.Started_At__c.date(), call.Started_At__c.date(), 0));
                    }
                    break;
                }
            }
        }
    }

    /** problem / next / pack: the big envelope (Stage 1), the signed pack coming back and the Stage 2 pack. */
    static void pack(Ctx c, Date sale, List<Action> actions) {
        Basic__c b = c.b;
        Date sent = b.FTP_Claim_Created_Send_Date__c;
        Date posted = b.Big_Envelop_Posted_Date__c != null ? b.Big_Envelop_Posted_Date__c : b.Stage_1_Pack_Posted_Date__c;
        Boolean docsBack = b.Claim_Full_Form_ZIP_for_UPLOAD__c == true || b.FTP_Claim_Full_Form_Created_Send_Date__c != null;

        if (sent == null && posted == null) {
            if (String.isNotBlank(b.FTP_Claim_Created_ZIP_Error__c)) {
                actions.add(c.action('problem', 'Big envelope not sent: fix the ZIP error',
                    'Sale on ' + fmt(sale) + '. ' + b.FTP_Claim_Created_ZIP_Error__c.normalizeSpace().abbreviate(250), sale, sale, 0));
            } else if (String.isNotBlank(b.FTP_Claim_Created_Error__c)) {
                actions.add(c.action('problem', 'Big envelope not sent: the upload to the printer failed',
                    'Sale on ' + fmt(sale) + '. ' + b.FTP_Claim_Created_Error__c.normalizeSpace().abbreviate(250), sale, sale, 0));
            } else {
                actions.add(c.action('problem', 'Big envelope not sent to the printer yet',
                    'Sale on ' + fmt(sale) + '. ' + (b.Claim_Created_ZIP_for_UPLOAD__c == true
                        ? 'The Stage 1 ZIP is built and waits for the hourly upload.'
                        : 'No Stage 1 ZIP waiting to go: build the Stage 1 pack again (Redo a Form, Collect Stage 1).'),
                    sale, sale, DAYS.get('stage1Send')));
            }
        } else if (posted == null) {
            actions.add(c.action('problem', 'The printer has not posted the big envelope: ask WDM',
                'Sent to the printer on ' + fmt(sent) + '; no BIG ENV POSTED email since.', sent, sent, DAYS.get('printerPost')));
        } else if (!docsBack) {
            Boolean far = FAR_COUNTRIES.contains(nz(b.Current_Address_Abroad_Country__c).toUpperCase());
            Integer packDays = DAYS.get(far ? 'signedPackFar' : 'signedPack');
            Date due = posted.addDays(packDays);
            if (c.contactDay() != null) {
                Date again = c.contactDay().addDays(DAYS.get('signedPackEvery'));
                if (again > due) due = again;
            }
            actions.add(c.action('pack', 'Signed pack not back ' + packDays + ' days after posting: call the client',
                'Big envelope posted on ' + fmt(posted) + (String.isBlank(b.Big_Envelop_Tracking_Number__c) ? '' : ' (tracking ' + b.Big_Envelop_Tracking_Number__c + ')')
                    + '; the printer has not had the signed pages back' + c.contactNote(posted) + '.', posted, due, 0));
        }

        if (String.isNotBlank(b.FTP_Claim_Full_Form_ZIP_Error__c)
                || (String.isNotBlank(b.FTP_Claim_Full_Form_Error__c) && b.FTP_Claim_Full_Form_Created_Send_Date__c == null)) {
            String error = String.isNotBlank(b.FTP_Claim_Full_Form_ZIP_Error__c) ? b.FTP_Claim_Full_Form_ZIP_Error__c : b.FTP_Claim_Full_Form_Error__c;
            actions.add(c.action('problem', 'Stage 2 pack not sent: fix the error', error.normalizeSpace().abbreviate(250), c.entered, c.entered, 0));
        } else if (b.Status__c == SIGNED && b.Claim_Full_Form_ZIP_for_UPLOAD__c == true && b.FTP_Claim_Full_Form_Created_Send_Date__c == null) {
            actions.add(c.action('next', 'Signed pages are back at the printer: press Resend Big Envelope (Stage 2)',
                'Signed on ' + fmt(c.entered) + '; the printer emailed that the signed pages arrived.', c.entered, c.entered, DAYS.get('nextStep')));
        } else if (b.Status__c == SIGNED && b.FTP_Claim_Full_Form_Created_Send_Date__c != null) {
            Date stage2 = b.FTP_Claim_Full_Form_Created_Send_Date__c;
            actions.add(c.action('problem', 'The printer has not posted the claim to the DWP: ask WDM',
                'Stage 2 pack sent to the printer on ' + fmt(stage2) + '; no CLAIM email since (it moves the claim to Posted to DWP).',
                stage2, stage2, DAYS.get('stage2Post')));
        }
    }

    /** call: Form In Progress / Validation Call. */
    static void validationCall(Ctx c, Date sale, List<Action> actions) {
        String booked = c.b.Val_Call_Booked_Date__c;
        Date callDay = callDate(booked);
        if (callDay == null) {
            actions.add(c.action('call', 'Book the validation call',
                'No validation call booked; sale on ' + fmt(sale) + c.contactNote(sale) + '.', sale, sale, DAYS.get('bookCall')));
        } else if (callDay >= c.today) {
            actions.add(c.action('call', 'Do the validation call', 'Booked: ' + booked.abbreviate(120) + '.', sale, callDay, 0));
        } else {
            actions.add(c.action('call', 'Finish the form and press Send to Validation',
                'The validation call was on ' + fmt(callDay) + '; the claim is still ' + c.b.Status__c + '.', callDay, callDay, DAYS.get('afterCall')));
        }
    }

    /** chase: first the day it went Pending Client, then DAYS.chaseEvery after each contact. */
    static void chase(Ctx c, String text, String why, List<Action> actions) {
        Boolean contacted = c.contactedSince(c.entered);
        actions.add(c.action('chase', text, why + c.contactNote(c.entered) + '.', c.entered,
            contacted ? c.contactDay() : c.entered, contacted ? DAYS.get('chaseEvery') : DAYS.get('chaseFirst')));
    }

    /**
     * esign: follow up DAYS.esignFirst after the DocuSign went out, then DAYS.esignEvery after each contact with the client
     * (Last Contact: Phone Chat, Email Sent or WhatsApp; a call nobody answered does not count). After DAYS.esignFollowUps
     * answered calls since it went out (Call Log), decide what to do. Emails and WhatsApp are not counted there: only
     * calls are logged one by one.
     */
    static void esign(Ctx c, Integer answeredCalls, List<Action> actions) {
        Integer calls = answeredCalls == null ? 0 : answeredCalls;
        Integer most = DAYS.get('esignFollowUps');
        Date spoke = c.replyDaySince(c.entered);
        String why = 'DocuSign sent on ' + fmt(c.entered)
            + (spoke == null ? '; no contact with the client since' : '; last contact ' + fmt(spoke) + ' (' + c.b.Contact_Type__c
                + (String.isBlank(c.b.Who__c) ? '' : ', ' + c.b.Who__c) + ')')
            + (calls > 0 ? '; ' + calls + (calls == 1 ? ' answered call' : ' answered calls') + ' since it went out' : '') + '.';
        Action a;
        if (calls >= most) {
            a = c.action('esign', 'Not signed after ' + most + ' follow-up calls: decide what to do (call again or On Hold)',
                why, c.entered, spoke == null ? c.entered : spoke, DAYS.get('esignDecide'));
        } else if (spoke == null) {
            a = c.action('esign', 'DocuSign not signed: follow up with the client (or ask the validation agent to chase)', why, c.entered, c.entered, DAYS.get('esignFirst'));
        } else {
            a = c.action('esign', 'DocuSign not signed: follow up again (or ask the validation agent to chase)', why, c.entered, spoke, DAYS.get('esignEvery'));
        }
        // QC sends the DocuSign and chases it (call of 11/11/2026 17h13)
        a.owner = QC_OWNER;
        actions.add(a);
    }

    /** dwp: only when the last Claim Check asks something of the validation agent. The checks themselves are in the Claim Check tab. */
    static void dwp(Ctx c, Claim_Check__c check, List<Action> actions) {
        if (check == null || (check.More_Info_Requested__c != true && check.Rejected__c != true)) return;
        Date checked = check.Check_Date__c != null ? check.Check_Date__c : check.CreatedDate.date();
        Boolean contacted = c.contactedSince(checked);
        String why = 'Claim Check on ' + fmt(checked) + (String.isBlank(check.Check_Agents__c) ? '' : ' by ' + check.Check_Agents__c)
            + (String.isBlank(check.Notes__c) ? '' : ': ' + check.Notes__c.normalizeSpace().abbreviate(200)) + c.contactNote(checked) + '.';
        String text = check.Rejected__c == true ? 'The DWP rejected the claim: call the client' : 'The DWP asked for more information: get it from the client';
        actions.add(c.action('dwp', text, why, checked, contacted ? c.contactDay() : checked, contacted ? DAYS.get('chaseEvery') : 0));
    }

    // ------------------------------------------------------------------ helpers

    /** Missing_Info__c in a few words ("bank details, UK employers"); null when the form is complete. */
    @TestVisible
    static String missingWords(String missing) {
        if (String.isBlank(missing) || missing.trim() == COMPLETE) return null;
        List<String> words = new List<String>();
        Set<String> seen = new Set<String>();
        for (String line : missing.split(';')) {
            String text = line.trim();
            if (text == '') continue;
            Integer colon = text.indexOf(':');
            String head = colon > 0 ? text.substring(0, colon).trim() : text;
            String word;
            Matcher spouse = SPOUSE_HEAD.matcher(head);
            if (MISSING_WORDS.containsKey(head)) {
                word = MISSING_WORDS.get(head);
            } else if (spouse.matches()) {
                String rest = spouse.group(3);
                word = spouse.group(1).toLowerCase() + '\'s ' + (rest == null ? 'details' : (MISSING_WORDS.containsKey(rest) ? MISSING_WORDS.get(rest) : rest));
            } else {
                word = head; // a country, an employer or a child, by its name
            }
            if (seen.add(word.toLowerCase())) words.add(word);
        }
        if (words.isEmpty()) return null;
        if (words.size() > 5) {
            Integer more = words.size() - 4;
            List<String> firstFour = new List<String>();
            for (Integer i = 0; i < 4; i++) firstFour.add(words[i]);
            return String.join(firstFour, ', ') + ' and ' + more + ' more';
        }
        return String.join(words, ', ');
    }

    /** The day in Val_Call_Booked_Date__c ("12/11/2026 10:00 (Irish time) - Becky"); null when empty or unreadable. */
    @TestVisible
    static Date callDate(String booked) {
        if (String.isBlank(booked)) return null;
        Matcher m = CALL_DATE.matcher(booked);
        if (!m.find()) return null;
        try {
            return Date.newInstance(Integer.valueOf(m.group(3)), Integer.valueOf(m.group(2)), Integer.valueOf(m.group(1)));
        } catch (Exception e) {
            return null;
        }
    }

    static Date later(Date a, Date b) {
        if (a == null) return b;
        if (b == null) return a;
        return a > b ? a : b;
    }

    static String nz(String s) {
        return s == null ? '' : s;
    }

    static String fmt(Date d) {
        return d == null ? '' : String.valueOf(d.day()).leftPad(2, '0') + '/' + String.valueOf(d.month()).leftPad(2, '0') + '/' + d.year();
    }

    /** The claim being looked at, with its last contact. */
    class Ctx {
        Basic__c b;
        Date entered;
        Date today;
        Ctx(Basic__c b, Date entered, Date today) {
            this.b = b;
            this.entered = entered;
            this.today = today;
        }
        Date contactDay() {
            if (b.Last_Contact_At__c != null) return b.Last_Contact_At__c.date();
            return b.Last_Contact_Date__c;
        }
        Boolean contactedSince(Date d) {
            Date day = contactDay();
            return day != null && d != null && day >= d;
        }
        /** The day of the last contact that reached the client (REPLY_TYPES), when it is on or after d; else null. */
        Date replyDaySince(Date d) {
            Date day = contactDay();
            return day != null && d != null && day >= d && REPLY_TYPES.contains(b.Contact_Type__c) ? day : null;
        }
        /** A person answered the client after this moment (call, email or WhatsApp from Last Contact). */
        Boolean repliedAfter(Datetime at) {
            return b.Last_Contact_At__c != null && b.Last_Contact_At__c > at && REPLY_TYPES.contains(b.Contact_Type__c);
        }
        String contactNote(Date since) {
            if (!contactedSince(since)) return '; no contact since';
            return '; last contact ' + fmt(contactDay()) + (String.isBlank(b.Contact_Type__c) ? '' : ' (' + b.Contact_Type__c
                + (String.isBlank(b.Who__c) ? '' : ', ' + b.Who__c) + ')');
        }
        Action action(String lane, String text, String why, Date since, Date base, Integer wait) {
            Action a = new Action();
            a.lane = lane;
            a.laneLabel = LANE_LABELS.get(lane);
            a.rank = LANES.indexOf(lane);
            a.text = text;
            a.why = why;
            a.since = since;
            a.daysWaiting = since == null ? null : since.daysBetween(today);
            a.due = (base == null ? today : base).addDays(wait == null ? 0 : wait);
            a.daysOverdue = a.due.daysBetween(today);
            return a;
        }
    }

    public class QueueResult {
        @AuraEnabled public List<Item> items = new List<Item>();
        @AuraEnabled public List<String> agents;
        @AuraEnabled public String me;
        @AuraEnabled public String qcOwner;
        @AuraEnabled public Integer liveMissingCount = 0;
        @AuraEnabled public Integer savedMissingCount = 0;
        @AuraEnabled public Integer liveMissingMax;
        @AuraEnabled public Map<String, Integer> days;
        @AuraEnabled public Map<String, String> laneLabels;
        @AuraEnabled public List<String> lanes;
        @AuraEnabled public Integer claimsLooked;
        @AuraEnabled public Boolean truncated = false;
        @AuraEnabled public Datetime generatedAt;
    }

    public class Action implements Comparable {
        @AuraEnabled public String lane;
        @AuraEnabled public String laneLabel;
        @AuraEnabled public Integer rank;
        @AuraEnabled public String text;
        @AuraEnabled public String why;
        @AuraEnabled public Date since;
        @AuraEnabled public Integer daysWaiting;
        @AuraEnabled public Date due;
        @AuraEnabled public Integer daysOverdue;
        /** Who does it: null = the claim's validation agent; QC_OWNER = the QC person. */
        @AuraEnabled public String owner;

        // due ones first, then the lane order, then the longest overdue
        public Integer compareTo(Object other) {
            Action o = (Action) other;
            Boolean dueNow = daysOverdue >= 0, otherDue = o.daysOverdue >= 0;
            if (dueNow != otherDue) return dueNow ? -1 : 1;
            if (rank != o.rank) return rank < o.rank ? -1 : 1;
            if (daysOverdue != o.daysOverdue) return daysOverdue > o.daysOverdue ? -1 : 1;
            return 0;
        }
    }

    public class Item implements Comparable {
        @AuraEnabled public Id claimId;
        @AuraEnabled public String name;
        @AuraEnabled public String client;
        @AuraEnabled public String phone;
        @AuraEnabled public String stage;
        @AuraEnabled public String agent;
        @AuraEnabled public Integer daysInStage;
        @AuraEnabled public Datetime lastContactAt;
        @AuraEnabled public Date lastContactDate;
        @AuraEnabled public String lastContactType;
        @AuraEnabled public String lastContactWho;
        @AuraEnabled public List<Action> actions;
        @AuraEnabled public String lane;
        @AuraEnabled public Integer rank;
        @AuraEnabled public Date due;
        @AuraEnabled public Integer daysOverdue;

        // the same order as the claim's first action, then the claim number
        public Integer compareTo(Object other) {
            Item o = (Item) other;
            Integer byAction = actions[0].compareTo(o.actions[0]);
            if (byAction != 0) return byAction;
            return name < o.name ? -1 : (name > o.name ? 1 : 0);
        }
    }
}