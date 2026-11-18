/**
 * What is still missing on a claim before it can go to the DWP, written for two
 * readers: a short line for the agent (Missing_Info__c, the Missing Information
 * panel, the DocuSign and Stage 2 checks) and a plain sentence for the client
 * (the missing-information email).
 *
 * Replaces the old list built from field help texts ("Your Address:
 * Postcode/Eircode", "Bank: BIC/SWIFT"), which clients could not act on.
 * BP_PortalUtils.generateValidationEmail, setMissing and getMissing call this.
 * Audit and reasons: docs/claims-xpai/missing-info-audit.md (Claude XP repo).
 *
 * Rules worth knowing:
 *  - Parts of one thing are one item (whole address, bank branch, spouse's name and date of birth, from/to dates).
 *  - Records are named (the country, the employer, the child), and the spouse's own rows go under the spouse.
 *  - The spouse is "your husband/wife", "your late husband/wife" or "your former husband/wife" by marital status.
 *  - Bank: BSB and account number for Australia; IBAN and BIC elsewhere (no sort code or account number then).
 *  - A missing pension start date is for the agent only: it changes the lump sum, so a person decides it.
 *  - No helper at all is optional: the email asks softly and it does not block the claim.
 *  - "Wants a helper?" answered No on the long form (Wants_Helper__c, 11/11/2026): the helper is not listed at all.
 *  - The agent ticks what the email asks (call of 11/11/2026). No helper given starts unticked (ticked only when the
 *    long form says "Wants a helper"); everything else starts ticked. previewLeavingOut / sendLeavingOut take the
 *    agent lines left unticked.
 *  - John's edits to the email (16/11/2026): no "Thank you for filling in your claim form" (the agent often filled it
 *    in on the call), the bank name can be a new or empty account, and "we'll figure out the best way to proceed"
 *    instead of "we'll help you find it". The spouse's address is asked only when it is not the client's own
 *    (Partner_same_as_claimant__c ticked = nothing to ask; BR1 Q26 is the spouse's address if different).
 */
public with sharing class BP_MissingInfo {

    public static final String COMPLETE = 'Form Fully Completed';
    public static final String CLIENTS_EMAIL = 'clients@xtrapension.com';
    public static final String WHATSAPP = '+353 (0)83 123 4000';
    private static final Set<String> EDITABLE_STATUSES = new Set<String>{ 'Form In Progress', 'Validation Call', 'Pending Client' };
    // Estágios do formulário: o painel pede ao cliente só daqui (Form In Progress a QC Approved).
    public static final Set<String> STAGES = new Set<String>{
        'Form In Progress', 'Validation Call', 'Form completed', 'Pending Client', 'Agent Check', 'QC Approved'
    };
    // Vai no assunto de todo email do painel; é também como o painel acha o último.
    public static final String SUBJECT_MARK = 'a few details we still need for your UK State Pension claim';
    // John's wording, 16/11/2026 (was "If you don't have something, just tell us and we'll help you find it.")
    @TestVisible
    private static final String CLOSING = 'If you don\'t have something we\'ve asked for, just tell us and we\'ll figure out the best way to proceed with your claim.';

    private static final String G_YOU = 'About you';
    private static final String G_SPOUSE = 'spouse';
    private static final String G_HELPER = 'Your helper';
    private static final String G_HISTORY = 'Where you lived and worked';
    private static final String G_CHILDREN = 'Your children';
    private static final String G_BANK = 'Your bank account';
    private static final List<String> GROUP_ORDER = new List<String>{ G_YOU, G_SPOUSE, G_HELPER, G_HISTORY, G_CHILDREN, G_BANK };
    // Só no painel, por último, como no Sales: o que só o agente resolve (nunca vai ao cliente).
    private static final String G_AGENT = 'For you to check';

    // As 9 páginas do formulário do cliente, pelo nome curto.
    private static final List<String> PAGE_NAMES = new List<String>{
        'Helper', 'About the claimant', 'Husband, wife or civil partner', 'Have you ever claimed', 'Has your partner ever claimed',
        'Claiming from today', 'Current pension and benefits', 'Bank details', 'Summary'
    };
    // Step__c guarda a página em que o cliente está, mas da 4 em diante com o título da anterior (outputCurrentStep do portal).
    private static final Map<String, Integer> STEP_PAGE = new Map<String, Integer>{
        'Friend / Family for Communication' => 1, 'About the Claimant' => 2, 'About your husband, wife or civil partner' => 3,
        'About Partner' => 4, 'Have you (Claimant) Ever Claimed' => 5, 'Has Partner Ever Claimed' => 6,
        'Are You Claiming Pension from Today?' => 7, 'Benefits' => 8, 'Bank Details' => 9, 'Review' => 10
    };

    public class Item {
        @AuraEnabled public String groupKey;
        @AuraEnabled public String agentText;
        /** What the client is asked; null when only the agent should act (never sent to the client). */
        @AuraEnabled public String clientText;
        /** Asked of the client but does not block the claim (no helper given). */
        @AuraEnabled public Boolean optional;
        /** Ticked when the agent opens the email; false: asked only if the agent ticks it. */
        @AuraEnabled public Boolean askByDefault = true;
        @AuraEnabled public List<String> fields;
        Item(String groupKey, String agentText, String clientText, List<String> fields, Boolean optional) {
            this.groupKey = groupKey;
            this.agentText = agentText;
            this.clientText = clientText;
            this.fields = fields;
            this.optional = optional;
        }
    }

    public class GroupView {
        @AuraEnabled public String label;
        @AuraEnabled public List<Item> items = new List<Item>();
    }

    // ------------------------------------------------------------------ reading the claim

    public static Basic__c load(Id basicId) {
        return [
            SELECT Id, Name, Status__c, Missing_Info__c, Step__c, Agent_Form_Step__c, Is_envelope_created__c, First_Name__c, Last_Name__c, Email__c, Phone__c, Contact__c,
                   Claimant_title__c, Claimant_dob__c, Claimant_marital_Status__c,
                   Claimant_date_Of_Marriage__c, Claimant_date_Of_Bereavement__c, Claimant_date_Of_Divorce__c,
                   Claimant_hasNino__c, Claimant_nino__c, Has_Nino__c,
                   // Call of 11/11/2026 17h13: Remarried, spouse address not known
                   Previous_Marriage_Ended__c, Date_Of_Remarriage__c, Current_Spouse_First_Name__c, Current_Spouse_Last_Name__c,
                   Current_Spouse_DOB__c, Partner_Address_Unknown__c, Partner_same_as_claimant__c,
                   Claimant_ever_Lived_UK__c, Claimant_lived_UK_From__c, Claimant_lived_UK_to__c,
                   Claimant_Ever_Worked_UK__c, Claimant_worked_UK_From__c, Claimant_worked_UK_To__c,
                   Claimant_Minded_Kids__c,
                   Claimant_HM_Forces__c, Claimant_HM_Forces_Service__c, Claimant_HM_Forces_Enlisted__c, Claimant_HM_Forces_Discharged__c,
                   Claimant_self_Employed_UK__c, Ever_Self_Employed_UK_after_1978__c,
                   Current_Address_Abroad_Country_Name__c, Claimant_address1__c, Claimant_City__c, Eircode__c,
                   Friend_First_Name__c, Friend_Last_Name__c, Friend_Phone__c, Friend_Email__c, Relationship__c, CC_Helper_on_All_Comms__c, Wants_Helper__c,
                   Partner_Title__c, Partner_First_Name__c, Partner_Surname__c, Partner_DOB__c, Partner_Has_Nino__c, Partner_Nino__c,
                   Partner_Address1__c, Partner_City__c, Partner_Postcode__c, Partner_Country__c,
                   Track__c, Partner_Has_Nino_values__c, Partner_State_Pension__c, Partner_Claiming_UK_Pension__c,
                   Pension_Claiming_from_Today__c, Pension_Start_Date__c,
                   Bank_Account_Owner_Name__c, Owns_This_Account__c, Bank_Name__c, Bank_Address__c, Bank_City__c, Bank_Post_Code__c,
                   Bank_Country__c, Bank_Country_Code__c, Bank_IBAN__c, Bank_BIC__c, Bank_Sort_Code__c, Bank_Account__c,
                   (SELECT Name, Country_Type__c, From_date__c, To_Date__c, Is_Live_Here_Now__c, Social_Security_Number__c, Is_Partner__c
                    FROM ClaimantCountrieslived__r ORDER BY From_date__c NULLS LAST, CreatedDate),
                   (SELECT Name, Address1__c, City__c, Country__c, Postcode__c, From_Date__c, To_Date__c, Is_Partner__c, Is_Addresses__c
                    FROM Claimant_Companies__r ORDER BY From_Date__c NULLS LAST, CreatedDate),
                   (SELECT Name, Dob__c, Minded_From__c, Minded_To__c
                    FROM Clamant_Children__r ORDER BY Dob__c NULLS LAST, CreatedDate)
            FROM Basic__c
            WHERE Id = :basicId
        ];
    }

    // ------------------------------------------------------------------ the checks

    public static List<Item> check(Basic__c b) {
        List<Item> items = new List<Item>();
        aboutYou(b, items);
        spouse(b, items);
        helper(b, items);
        history(b, items);
        children(b, items);
        bank(b, items);
        return items;
    }

    private static void aboutYou(Basic__c b, List<Item> items) {
        List<String> nameParts = new List<String>();
        if (isBlank(b.First_Name__c)) nameParts.add('first name');
        if (isBlank(b.Last_Name__c)) nameParts.add('surname');
        if (!nameParts.isEmpty()) {
            add(items, G_YOU, 'Name: ' + joinParts(nameParts), 'Your ' + joinParts(nameParts) + ', as on your passport', new List<String>{ 'First_Name__c', 'Last_Name__c' });
        }
        if (isBlank(b.Claimant_title__c)) add(items, G_YOU, 'Title', 'Your title (Mr, Mrs, Ms, Miss or Dr)', new List<String>{ 'Claimant_title__c' });
        if (b.Claimant_dob__c == null) add(items, G_YOU, 'Date of birth', 'Your date of birth', new List<String>{ 'Claimant_dob__c' });
        if (isBlank(b.Phone__c)) add(items, G_YOU, 'Phone', 'A phone number we can reach you on', new List<String>{ 'Phone__c' });
        if (isBlank(b.Email__c)) add(items, G_YOU, 'Email (needed to write to the client)', null, new List<String>{ 'Email__c' });
        if (isBlank(b.Claimant_marital_Status__c)) {
            add(items, G_YOU, 'Marital status', 'Whether you are married, widowed, divorced, separated or single', new List<String>{ 'Claimant_marital_Status__c' });
        }

        String code = postcodeWord(b.Current_Address_Abroad_Country_Name__c);
        List<String> addressParts = new List<String>();
        if (isBlank(b.Claimant_address1__c)) addressParts.add('street address');
        if (isBlank(b.Claimant_City__c)) addressParts.add('town or city');
        if (isBlank(b.Eircode__c)) addressParts.add(code);
        if (isBlank(b.Current_Address_Abroad_Country_Name__c)) addressParts.add('country');
        if (!addressParts.isEmpty()) {
            String client = addressParts.size() >= 3
                ? 'Your full home address, including your ' + code
                : 'The ' + joinParts(addressParts) + ' of your home address';
            add(items, G_YOU, 'Home address: ' + joinParts(addressParts), client,
                new List<String>{ 'Claimant_address1__c', 'Claimant_City__c', 'Eircode__c', 'Current_Address_Abroad_Country_Name__c' });
        }

        // "Forgot" (Short Form or long form, 11/11/2026 17h13): never asked, the DWP traces it
        if (b.Claimant_hasNino__c && isBlank(b.Claimant_nino__c) && b.Has_Nino__c != 'Forgot') {
            add(items, G_YOU, 'NINO',
                'Your UK National Insurance number. It is on old UK payslips, P60s and letters from HMRC or the DWP. If you can\'t find it, tell us and we will trace it',
                new List<String>{ 'Claimant_nino__c' });
        }

        String status = b.Claimant_marital_Status__c;
        if ((status == 'Married' || status == 'Civil Partner') && b.Claimant_date_Of_Marriage__c == null) {
            add(items, G_YOU, status == 'Civil Partner' ? 'Date of civil partnership' : 'Date of marriage',
                status == 'Civil Partner' ? 'The date your civil partnership was registered' : 'The date you got married',
                new List<String>{ 'Claimant_date_Of_Marriage__c' });
        }
        if (status == 'Widowed' && b.Claimant_date_Of_Bereavement__c == null) {
            add(items, G_YOU, 'Date of bereavement', 'The date your ' + spouseBase(b) + ' passed away', new List<String>{ 'Claimant_date_Of_Bereavement__c' });
        }
        if ((status == 'Divorced' || status == 'Separated') && b.Claimant_date_Of_Divorce__c == null) {
            add(items, G_YOU, status == 'Separated' ? 'Date of separation' : 'Date of divorce',
                status == 'Separated' ? 'The date you separated' : 'The date of your divorce',
                new List<String>{ 'Claimant_date_Of_Divorce__c' });
        }
        if (status == 'Remarried') remarried(b, items);

        if (b.Claimant_ever_Lived_UK__c && (b.Claimant_lived_UK_From__c == null || b.Claimant_lived_UK_to__c == null)) {
            add(items, G_HISTORY, 'UK residence: ' + fromTo(b.Claimant_lived_UK_From__c == null, b.Claimant_lived_UK_to__c == null),
                b.Claimant_lived_UK_From__c == null && b.Claimant_lived_UK_to__c == null
                    ? 'When you lived in the UK: the year you arrived and the year you left (the month too, if you remember)'
                    : (b.Claimant_lived_UK_From__c == null ? 'The year you came to live in the UK' : 'The year you left the UK'),
                new List<String>{ 'Claimant_lived_UK_From__c', 'Claimant_lived_UK_to__c' });
        }
        if (b.Claimant_Ever_Worked_UK__c && (b.Claimant_worked_UK_From__c == null || b.Claimant_worked_UK_To__c == null)) {
            add(items, G_HISTORY, 'UK work: ' + fromTo(b.Claimant_worked_UK_From__c == null, b.Claimant_worked_UK_To__c == null),
                b.Claimant_worked_UK_From__c == null && b.Claimant_worked_UK_To__c == null
                    ? 'When you worked in the UK: the year you started and the year you stopped'
                    : (b.Claimant_worked_UK_From__c == null ? 'The year you started working in the UK' : 'The year you stopped working in the UK'),
                new List<String>{ 'Claimant_worked_UK_From__c', 'Claimant_worked_UK_To__c' });
        }

        if (b.Pension_Claiming_from_Today__c == false && b.Pension_Start_Date__c == null) {
            add(items, G_YOU, 'Pension start date: agree it with the client (it changes the lump sum, see IPCBR1 Q46)', null,
                new List<String>{ 'Pension_Start_Date__c' });
        }
    }

    // Remarried (call of 11/11/2026 17h13): the spouse of the form's section 3 is the first (former or late) one, whose UK
    // record we claim on; the BR1 also needs the current husband / wife (Q21-Q28) and the dates of both marriages.
    private static void remarried(Basic__c b, List<Item> items) {
        String first = 'first ' + spouseBase(b);
        if (b.Claimant_date_Of_Marriage__c == null) {
            add(items, G_YOU, 'Date of first marriage', 'The date you married your ' + first, new List<String>{ 'Claimant_date_Of_Marriage__c' });
        }
        String ended = b.Previous_Marriage_Ended__c;
        if (isBlank(ended)) {
            add(items, G_YOU, 'First marriage: ended in divorce or a death',
                'Whether your first marriage ended in divorce or because your ' + first + ' passed away', new List<String>{ 'Previous_Marriage_Ended__c' });
        } else if (ended == 'Divorced' && b.Claimant_date_Of_Divorce__c == null) {
            add(items, G_YOU, 'Date of divorce (first marriage)', 'The date of your divorce from your ' + first, new List<String>{ 'Claimant_date_Of_Divorce__c' });
        } else if (ended == 'Widowed' && b.Claimant_date_Of_Bereavement__c == null) {
            add(items, G_YOU, 'Date of bereavement (first marriage)', 'The date your ' + first + ' passed away', new List<String>{ 'Claimant_date_Of_Bereavement__c' });
        }
        if (b.Date_Of_Remarriage__c == null) {
            add(items, G_YOU, 'Date of remarriage', 'The date you married again', new List<String>{ 'Date_Of_Remarriage__c' });
        }
        List<String> parts = new List<String>();
        if (isBlank(b.Current_Spouse_First_Name__c)) parts.add('first name');
        if (isBlank(b.Current_Spouse_Last_Name__c)) parts.add('surname');
        if (b.Current_Spouse_DOB__c == null) parts.add('date of birth');
        if (!parts.isEmpty()) {
            String current = 'current ' + currentBase(b);
            add(items, G_YOU, capitalise(current) + ': ' + joinParts(parts), 'The ' + joinParts(parts) + ' of your ' + current,
                new List<String>{ 'Current_Spouse_First_Name__c', 'Current_Spouse_Last_Name__c', 'Current_Spouse_DOB__c' });
        }
    }

    // The current spouse's word from the claimant's title (the section 3 title is the first spouse's).
    private static String currentBase(Basic__c b) {
        String own = normaliseTitle(b.Claimant_title__c);
        if (own == 'mrs' || own == 'ms' || own == 'miss') return 'husband';
        if (own == 'mr') return 'wife';
        return 'husband or wife';
    }

    private static void spouse(Basic__c b, List<Item> items) {
        if (!hasSpouse(b)) return;
        String noun = spouseNoun(b);
        List<String> idParts = new List<String>();
        if (isBlank(b.Partner_Title__c)) idParts.add('title');
        if (isBlank(b.Partner_Surname__c)) idParts.add('surname');
        if (b.Partner_DOB__c == null) idParts.add('date of birth');
        if (!idParts.isEmpty()) {
            add(items, G_SPOUSE, capitalise(noun) + ': ' + joinParts(idParts), 'The ' + joinParts(idParts) + ' of your ' + noun,
                new List<String>{ 'Partner_Title__c', 'Partner_Surname__c', 'Partner_DOB__c' });
        }
        if (b.Partner_Has_Nino__c && isBlank(b.Partner_Nino__c) && b.Partner_Has_Nino_values__c != 'Forgot') {
            add(items, G_SPOUSE, capitalise(noun) + ': NINO', 'The UK National Insurance number of your ' + noun + ', if ' + spousePronoun(b) + ' had one',
                new List<String>{ 'Partner_Nino__c' });
        }
        List<String> addressParts = new List<String>();
        if (isBlank(b.Partner_Address1__c)) addressParts.add('street address');
        if (isBlank(b.Partner_City__c)) addressParts.add('town or city');
        if (isBlank(b.Partner_Postcode__c)) addressParts.add('postcode');
        if (isBlank(b.Partner_Country__c)) addressParts.add('country');
        // "Not known" on the long form (11/11/2026 17h13): the BR1 says so, nothing to ask
        // "Same address as me" ticked: the BR1 leaves Q26 blank (= the client's address), nothing to ask (John, 16/11/2026)
        if (!addressParts.isEmpty() && b.Partner_Address_Unknown__c != true && b.Partner_same_as_claimant__c != true) {
            String status = b.Claimant_marital_Status__c;
            Boolean late = status == 'Widowed' || (status == 'Remarried' && b.Previous_Marriage_Ended__c == 'Widowed');
            String client = late
                ? 'The last home address of your ' + noun + ', if it was different from yours'
                : (status == 'Divorced' || status == 'Separated' || status == 'Remarried')
                    ? 'The last address you know for your ' + noun + ', if you know it'
                    : 'The home address of your ' + noun + ', if it is different from yours';
            add(items, G_SPOUSE, capitalise(noun) + ': address (' + joinParts(addressParts) + ')', client,
                new List<String>{ 'Partner_Address1__c', 'Partner_City__c', 'Partner_Postcode__c', 'Partner_Country__c' });
        }
    }

    private static void helper(Basic__c b, List<Item> items) {
        // The client said on the long form that they do not want a helper (John, 11/11/2026): nothing about a helper is
        // listed, for the agent or for the client, even if the sale page left an email. Blank (not asked) or Yes: as before.
        if (b.Wants_Helper__c == 'No') return;
        Boolean noneGiven = isBlank(b.Friend_First_Name__c) && isBlank(b.Friend_Last_Name__c) && isBlank(b.Friend_Phone__c)
            && isBlank(b.Friend_Email__c) && isBlank(b.Relationship__c);
        List<String> fields = new List<String>{ 'Friend_First_Name__c', 'Friend_Last_Name__c', 'Friend_Phone__c', 'Friend_Email__c', 'Relationship__c' };
        if (noneGiven) {
            Item none = new Item(G_HELPER, 'Helper: none given (optional)',
                'If someone helps you with your claim, such as a son, daughter or friend: their name, phone number and email, and how they are related to you. If no one helps you, just tell us',
                fields, true);
            // Not in the email unless the agent ticks it (Fernando, call of 11/11/2026), or the client said they want one.
            none.askByDefault = b.Wants_Helper__c == 'Yes';
            items.add(none);
            return;
        }
        List<String> parts = new List<String>();
        if (isBlank(b.Friend_First_Name__c)) parts.add('first name');
        if (isBlank(b.Friend_Last_Name__c)) parts.add('surname');
        if (isBlank(b.Friend_Phone__c)) parts.add('phone number');
        if (isBlank(b.Friend_Email__c)) parts.add('email');
        if (isBlank(b.Relationship__c)) parts.add('how they are related to you');
        if (parts.isEmpty()) return;
        String who = isBlank(b.Friend_First_Name__c) ? 'Your helper' : 'Your helper, ' + b.Friend_First_Name__c.trim();
        // The helper is optional (Fernando, 10/11/2026): a half-given helper (often just the email from the sale page)
        // is listed but never holds the claim in Pending Client nor the DocuSign (audit 11/11/2026).
        items.add(new Item(G_HELPER, 'Helper: ' + joinParts(parts) + ' (optional)', who + ': ' + joinParts(parts), fields, true));
    }

    private static void history(Basic__c b, List<Item> items) {
        List<Claimant_Country_lived__c> countries = b.ClaimantCountrieslived__r;
        Boolean ownCountry = false;
        for (Claimant_Country_lived__c c : countries) {
            if (c.Is_Partner__c != true) ownCountry = true;
        }
        if (!ownCountry) {
            add(items, G_HISTORY, 'Countries lived: none listed', 'The countries you have lived in since you left the UK, and the years you lived in each',
                new List<String>{ 'ClaimantCountrieslived__r' });
        }
        Integer position = 0;
        for (Claimant_Country_lived__c c : countries) {
            position++;
            Boolean partner = c.Is_Partner__c == true;
            // Single (12/11/2026 audit): spouse rows left on the record from an earlier status are not asked for
            if (partner && isSingle(b)) continue;
            String place = isBlank(c.Name) ? 'Country ' + position : c.Name.trim();
            String groupKey = partner ? G_SPOUSE : G_HISTORY;
            String subject = partner ? spousePronoun(b) : 'you';
            String possessive = partner ? spousePossessive(b) : 'your';
            Boolean noFrom = c.From_date__c == null;
            Boolean noTo = c.To_Date__c == null && c.Is_Live_Here_Now__c != true;
            if (noFrom || noTo) {
                String client = noFrom && noTo ? place + ': the years ' + subject + ' lived there'
                    : noFrom ? place + ': the year ' + subject + ' moved there'
                    : place + ': the year ' + subject + ' left, or tell us if ' + subject + (partner ? ' still lives' : ' still live') + ' there';
                add(items, groupKey, agentPrefix(b, partner) + place + ': ' + fromTo(noFrom, noTo), client,
                    new List<String>{ 'From_date__c', 'To_Date__c', 'Is_Live_Here_Now__c' });
            }
            if (isBlank(c.Social_Security_Number__c)) {
                String taxName = taxNumberName(c);
                add(items, groupKey, agentPrefix(b, partner) + place + ': ' + taxName, place + ': ' + possessive + ' ' + taxName + (taxName.startsWith('social security') ? ' there' : ''),
                    new List<String>{ 'Social_Security_Number__c' });
            }
        }
        // Whoever worked in the UK needs their UK employers on the BR1 (Q18), with or without a NINO (John, 10/11/2026).
        Boolean ownEmployer = false;
        for (Claimant_Company__c co : b.Claimant_Companies__r) {
            if (co.Is_Partner__c != true && co.Is_Addresses__c != true) ownEmployer = true;
        }
        // Someone who was only self-employed in the UK has no employer to give: not asked (it would block the DocuSign).
        Boolean selfEmployed = b.Claimant_self_Employed_UK__c == true || b.Ever_Self_Employed_UK_after_1978__c == true;
        if (b.Claimant_Ever_Worked_UK__c == true && !ownEmployer && !selfEmployed) {
            add(items, G_HISTORY, 'UK employers: none listed', 'The name and address of each employer you had in the UK, and the years you worked there',
                new List<String>{ 'Claimant_Companies__r' });
        }
        // A claim on the husband's or wife's record (track B or C) needs their UK employers when we have no NINO for them
        // (forgotten, or a widow: the Short Form's rule) or when they already get a UK State Pension (John, 11/11/2026).
        // With their NINO and no UK pension they are not asked.
        if (needsSpouseEmployers(b)) {
            Boolean spouseEmployer = false;
            for (Claimant_Company__c co : b.Claimant_Companies__r) {
                if (co.Is_Partner__c == true && co.Is_Addresses__c != true) spouseEmployer = true;
            }
            if (!spouseEmployer) {
                String noun = spouseNoun(b);
                add(items, G_SPOUSE, capitalise(noun) + ', UK employers: none listed',
                    'The name and address of each employer your ' + noun + ' had in the UK, and the years ' + spousePronoun(b) + ' worked there',
                    new List<String>{ 'Claimant_Companies__r' });
            }
        }
        // HM Forces (BR1 Q17): when the client served, the service and the dates.
        if (b.Claimant_HM_Forces__c == true) {
            List<String> forces = new List<String>();
            if (isBlank(b.Claimant_HM_Forces_Service__c)) forces.add('service');
            if (b.Claimant_HM_Forces_Enlisted__c == null) forces.add('date enlisted');
            if (b.Claimant_HM_Forces_Discharged__c == null) forces.add('date discharged');
            if (!forces.isEmpty()) {
                add(items, G_HISTORY, 'HM Forces: ' + joinParts(forces),
                    'Your time in HM Forces: which service you were in (Army, Navy or RAF) and the dates you enlisted and were discharged',
                    new List<String>{ 'Claimant_HM_Forces_Service__c', 'Claimant_HM_Forces_Enlisted__c', 'Claimant_HM_Forces_Discharged__c' });
            }
        }
        position = 0;
        for (Claimant_Company__c co : b.Claimant_Companies__r) {
            position++;
            Boolean partner = co.Is_Partner__c == true;
            if (partner && isSingle(b)) continue;
            // A UK home address row (Short Form, NINO lost) keeps the country in Name: call it an address, not an employer
            Boolean home = co.Is_Addresses__c == true;
            String employer = home ? 'UK home address ' + position : isBlank(co.Name) ? 'UK employer ' + position : co.Name.trim();
            String groupKey = partner ? G_SPOUSE : G_HISTORY;
            String subject = partner ? spousePronoun(b) : 'you';
            List<String> parts = new List<String>();
            if (isBlank(co.Address1__c)) parts.add('street');
            if (isBlank(co.City__c)) parts.add('town');
            if (isBlank(co.Postcode__c)) parts.add('postcode');
            if (isBlank(co.Country__c)) parts.add('country');
            if (!parts.isEmpty()) {
                String verb = home ? ' lived' : ' worked';
                String client = parts.size() >= 3
                    ? employer + ': the address where ' + subject + verb + ' (the town and postcode are enough)'
                    : employer + ': the ' + joinParts(parts) + ' where ' + subject + verb + ', if ' + subject + (partner ? ' knows it' : ' know it');
                add(items, groupKey, agentPrefix(b, partner) + employer + ': address (' + joinParts(parts) + ')', client,
                    new List<String>{ 'Address1__c', 'City__c', 'Postcode__c', 'Country__c' });
            }
            if (co.From_Date__c == null || co.To_Date__c == null) {
                String client = co.From_Date__c == null && co.To_Date__c == null
                    ? employer + ': the years ' + subject + (home ? ' lived there' : ' worked there')
                    : (co.From_Date__c == null ? employer + ': the year ' + subject + (home ? ' moved in' : ' started there') : employer + ': the year ' + subject + ' left');
                add(items, groupKey, agentPrefix(b, partner) + employer + ': ' + fromTo(co.From_Date__c == null, co.To_Date__c == null), client,
                    new List<String>{ 'From_Date__c', 'To_Date__c' });
            }
        }
    }

    private static void children(Basic__c b, List<Item> items) {
        if (!b.Claimant_Minded_Kids__c) return;
        if (b.Clamant_Children__r.isEmpty()) {
            add(items, G_CHILDREN, 'Children: none listed',
                'The name and date of birth of each child you stayed at home to look after, and the years you did',
                new List<String>{ 'Clamant_Children__r' });
            return;
        }
        Integer position = 0;
        for (Claimant_Child__c ch : b.Clamant_Children__r) {
            position++;
            String child = isBlank(ch.Name) ? 'Child ' + position : ch.Name.trim();
            List<String> agent = new List<String>();
            List<String> client = new List<String>();
            if (ch.Dob__c == null) { agent.add('date of birth'); client.add('date of birth'); }
            if (ch.Minded_From__c == null || ch.Minded_To__c == null) {
                agent.add('years at home');
                client.add('the years you stayed at home to look after them');
            }
            if (!agent.isEmpty()) {
                add(items, G_CHILDREN, child + ': ' + joinParts(agent), child + ': ' + joinParts(client),
                    new List<String>{ 'Dob__c', 'Minded_From__c', 'Minded_To__c' });
            }
        }
    }

    private static void bank(Basic__c b, List<Item> items) {
        if (isBlank(b.Bank_Account_Owner_Name__c)) {
            add(items, G_BANK, 'Bank: account holder name', 'The name on a bank account, exactly as it is on your bank statement (it can be a new / empty account)',
                new List<String>{ 'Bank_Account_Owner_Name__c' });
        }
        if (isBlank(b.Owns_This_Account__c)) {
            add(items, G_BANK, 'Bank: whose account it is', 'Whose account the pension should be paid into: yours, a joint account, or a relative\'s',
                new List<String>{ 'Owns_This_Account__c' });
        }
        List<String> branch = new List<String>();
        if (isBlank(b.Bank_Address__c)) branch.add('street');
        if (isBlank(b.Bank_City__c)) branch.add('town');
        if (isBlank(b.Bank_Post_Code__c)) branch.add(postcodeWord(b.Bank_Country__c));
        if (isBlank(b.Bank_Country_Code__c)) branch.add('country');
        Boolean noName = isBlank(b.Bank_Name__c);
        if (noName || !branch.isEmpty()) {
            String agent = 'Bank: ' + (noName ? 'name' : '') + (noName && !branch.isEmpty() ? ', ' : '') + (branch.isEmpty() ? '' : 'branch ' + joinParts(branch));
            String client = noName && branch.size() >= 2 ? 'Your bank\'s name and branch address'
                : noName && branch.isEmpty() ? 'Your bank\'s name'
                : noName ? 'Your bank\'s name and the ' + joinParts(branch) + ' of the branch'
                : branch.size() >= 3 ? 'Your bank branch\'s address'
                : 'The ' + joinParts(branch) + ' of your bank branch';
            add(items, G_BANK, agent, client, new List<String>{ 'Bank_Name__c', 'Bank_Address__c', 'Bank_City__c', 'Bank_Post_Code__c', 'Bank_Country_Code__c' });
        }
        if (isAustralianBank(b)) {
            List<String> parts = new List<String>();
            if (isBlank(b.Bank_Sort_Code__c)) parts.add('BSB');
            if (isBlank(b.Bank_Account__c)) parts.add('account number');
            if (!parts.isEmpty()) {
                add(items, G_BANK, 'Bank: ' + joinParts(parts), 'Your ' + joinParts(parts) + '. You\'ll find ' + (parts.size() > 1 ? 'both' : 'it') + ' on your bank statement or in your online banking',
                    new List<String>{ 'Bank_Sort_Code__c', 'Bank_Account__c' });
            }
        } else if (isCanadianBank(b)) {
            // Canada: institution (3 digits) + transit (5 digits) in Bank_Sort_Code__c, and the account number. No IBAN.
            List<String> parts = new List<String>();
            if (XpCanadaBank.parts(b.Bank_Sort_Code__c) == null) parts.add('institution and transit numbers');
            if (isBlank(b.Bank_Account__c)) parts.add('account number');
            if (!parts.isEmpty()) {
                add(items, G_BANK, 'Bank: ' + joinParts(parts), 'Your ' + joinParts(parts)
                    + '. They are on a cheque (the 5-digit transit number, the 3-digit institution number, then the account number) and in your online banking',
                    new List<String>{ 'Bank_Sort_Code__c', 'Bank_Account__c' });
            }
        } else {
            List<String> parts = new List<String>();
            if (isBlank(b.Bank_IBAN__c)) parts.add('IBAN');
            if (isBlank(b.Bank_BIC__c)) parts.add('BIC (SWIFT) code');
            if (!parts.isEmpty()) {
                add(items, G_BANK, 'Bank: ' + joinParts(parts).replace(' (SWIFT) code', ''),
                    'Your ' + joinParts(parts) + '. ' + (parts.size() > 1 ? 'Both are' : 'It is') + ' on your bank statement and in your online banking',
                    new List<String>{ 'Bank_IBAN__c', 'Bank_BIC__c' });
            }
        }
    }

    // ------------------------------------------------------------------ what the callers get

    /** Items that block the claim (everything except the optional ones), as agent lines. */
    public static List<String> agentTexts(List<Item> items) {
        List<String> out = new List<String>();
        for (Item i : items) {
            if (i.optional != true) out.add(i.agentText);
        }
        return out;
    }

    /** Value for Missing_Info__c. */
    public static String fieldValue(List<Item> items) {
        List<String> lines = agentTexts(items);
        return lines.isEmpty() ? COMPLETE : String.join(lines, '; ');
    }

    public static List<Item> clientItems(List<Item> items) {
        List<Item> out = new List<Item>();
        for (Item i : items) {
            if (i.clientText != null) out.add(i);
        }
        return out;
    }

    /** The items without the ones the agent left unticked (matched by agent line). Null: nothing left out. */
    public static List<Item> without(List<Item> items, List<String> leaveOut) {
        if (leaveOut == null || leaveOut.isEmpty()) return items;
        Set<String> skip = new Set<String>(leaveOut);
        List<Item> out = new List<Item>();
        for (Item i : items) {
            if (!skip.contains(i.agentText)) out.add(i);
        }
        return out;
    }

    public static List<GroupView> grouped(Basic__c b, List<Item> items) {
        Map<String, GroupView> byKey = new Map<String, GroupView>();
        for (Item i : items) {
            GroupView g = byKey.get(i.groupKey);
            if (g == null) {
                g = new GroupView();
                g.label = i.groupKey == G_SPOUSE ? 'Your ' + spouseNoun(b) : i.groupKey;
                byKey.put(i.groupKey, g);
            }
            g.items.add(i);
        }
        List<GroupView> out = new List<GroupView>();
        for (String key : GROUP_ORDER) {
            if (byKey.containsKey(key)) out.add(byKey.get(key));
        }
        return out;
    }

    /** Grupos do painel: os mesmos do email, e o que só o agente resolve num grupo próprio, por último (como no Sales). */
    public static List<GroupView> panelGroups(Basic__c b, List<Item> items) {
        List<Item> forClient = new List<Item>();
        GroupView agentOnly = new GroupView();
        agentOnly.label = G_AGENT;
        for (Item i : items) {
            if (i.clientText == null) agentOnly.items.add(i);
            else forClient.add(i);
        }
        List<GroupView> out = grouped(b, forClient);
        if (!agentOnly.items.isEmpty()) out.add(agentOnly);
        return out;
    }

    // ------------------------------------------------------------------ panel (xpMissingInfo, via XpMissingInfoPanel)

    /**
     * Current list for the panel. Keeps Missing_Info__c in step with the record: it is rewritten when
     * it differs and the claim is still being completed (or always, when the agent presses refresh).
     * Same keys as XpMissingInfo.refresh (Sales), plus blocking and name.
     */
    @AuraEnabled
    public static Map<String, Object> refresh(Id basicId, Boolean force) {
        Basic__c b = load(basicId);
        List<Item> items = check(b);
        String value = fieldValue(items);
        Boolean write = force == true || EDITABLE_STATUSES.contains(b.Status__c);
        if (write && b.Missing_Info__c != value) {
            update new Basic__c(Id = b.Id, Missing_Info__c = value);
        }
        Integer missing = 0, optional = 0, checks = 0;
        for (Item i : items) {
            if (i.clientText == null) checks++;
            else if (i.optional == true) optional++;
            else missing++;
        }
        return new Map<String, Object>{
            'groups' => panelGroups(b, items),
            'missing' => missing,
            'optional' => optional,
            'checks' => checks,
            'blocking' => agentTexts(items).size(),
            'clientCount' => missing + optional,
            'hasEmail' => !isBlank(b.Email__c),
            'inStage' => STAGES.contains(b.Status__c),
            'step' => stepLine(b),
            'lastAsked' => lastAsked(b),
            'name' => b.Name
        };
    }

    @AuraEnabled
    public static Map<String, Object> preview(Id basicId, String note) {
        return previewLeavingOut(basicId, note, null);
    }

    @AuraEnabled
    public static String sendEmail(Id basicId, String note) {
        return sendLeavingOut(basicId, note, null);
    }

    /** The email and the WhatsApp text without the items the agent left unticked (XpMissingInfoPanel). */
    public static Map<String, Object> previewLeavingOut(Id basicId, String note, List<String> leaveOut) {
        return previewAsking(basicId, note, leaveOut, null);
    }

    public static String sendLeavingOut(Id basicId, String note, List<String> leaveOut) {
        return sendAsking(basicId, note, leaveOut, null);
    }

    /**
     * The same, with the validation agent's own questions for the client (call of 11/11/2026 17h13: "Hi, I have to clarify
     * some information on your application. I have some questions around X, Y and Z"), one per line. With questions the
     * email can go even when nothing is missing or nothing is ticked.
     */
    public static Map<String, Object> previewAsking(Id basicId, String note, List<String> leaveOut, String questions) {
        Basic__c b = load(basicId);
        List<Item> forClient = without(clientItems(check(b)), leaveOut);
        List<String> asked = questionLines(questions);
        String sender = senderName();
        return new Map<String, Object>{
            'to' => b.Email__c,
            'cc' => ccAddress(b),
            'subject' => subject(b),
            'html' => html(b, forClient, note, sender, asked),
            'whatsapp' => whatsApp(b, forClient, note, sender, asked),
            'count' => forClient.size(),
            'questions' => asked.size()
        };
    }

    public static String sendAsking(Id basicId, String note, List<String> leaveOut, String questions) {
        Basic__c b = load(basicId);
        if (!STAGES.contains(b.Status__c)) throw new AuraHandledException('The claim is past QC Approved: nothing is sent from here.');
        List<String> asked = questionLines(questions);
        List<Item> all = clientItems(check(b));
        if (all.isEmpty() && asked.isEmpty()) throw new AuraHandledException('There is nothing to ask the client: the form is complete. Type your questions to send them.');
        List<Item> forClient = without(all, leaveOut);
        if (forClient.isEmpty() && asked.isEmpty()) throw new AuraHandledException('Nothing is ticked: tick at least one item to ask the client, or type a question.');
        if (isBlank(b.Email__c)) throw new AuraHandledException('This claim has no client email.');

        String htmlBody = html(b, forClient, note, senderName(), asked);
        String textBody = text(b, forClient, note, senderName(), asked);
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setSubject(subject(b));
        mail.setHtmlBody(htmlBody);
        mail.setPlainTextBody(textBody);
        List<OrgWideEmailAddress> owea = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :CLIENTS_EMAIL LIMIT 1];
        if (!owea.isEmpty()) mail.setOrgWideEmailAddressId(owea[0].Id);
        String cc = ccAddress(b);
        if (cc != null) mail.setCcAddresses(new List<String>{ cc });

        // With a contact the email is saved on the claim by Salesforce; without one it is logged below.
        Boolean logged = false;
        if (b.Contact__c != null) {
            List<Contact> contacts = [SELECT Email FROM Contact WHERE Id = :b.Contact__c LIMIT 1];
            mail.setTargetObjectId(b.Contact__c);
            mail.setWhatId(b.Id);
            mail.setSaveAsActivity(true);
            Boolean sameAddress = !contacts.isEmpty() && contacts[0].Email != null && contacts[0].Email.equalsIgnoreCase(b.Email__c);
            if (!sameAddress) {
                mail.setTreatTargetObjectAsRecipient(false);
                mail.setToAddresses(new List<String>{ b.Email__c });
            }
            logged = true;
        } else {
            mail.setToAddresses(new List<String>{ b.Email__c });
        }
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        if (!logged) {
            insert new EmailMessage(
                RelatedToId = b.Id, Subject = subject(b), HtmlBody = htmlBody, TextBody = textBody,
                ToAddress = b.Email__c, CcAddress = cc, FromAddress = CLIENTS_EMAIL, FromName = 'XtraPension',
                Incoming = false, Status = '3', MessageDate = System.now()
            );
        }
        return 'Sent to ' + b.Email__c + (cc != null ? ' (copy to ' + cc + ')' : '') + '.';
    }

    /**
     * Onde o cliente está no formulário, só em Form In Progress e Validation Call:
     * 'The client is on step 4 of 9, "Have you ever claimed".' Nunca mostra o Step__c cru.
     */
    @TestVisible
    private static String stepLine(Basic__c b) {
        if (b.Status__c != 'Form In Progress' && b.Status__c != 'Validation Call') return null;
        Integer page = isBlank(b.Step__c) ? 0 : STEP_PAGE.get(b.Step__c);
        if (page == null) return null;
        Integer last = PAGE_NAMES.size();
        String line = page == 0
            ? (b.Is_envelope_created__c == true ? 'The client has not opened the form yet' : 'The short form has not been done yet')
            : page > last ? 'The client has sent the form'
            : 'The client is on step ' + page + ' of ' + last + ', "' + PAGE_NAMES[page - 1] + '"';
        // O formulário do agente não move o Step__c: mostra quando ele está mais adiante.
        Integer agentPage = isBlank(b.Agent_Form_Step__c) ? null : STEP_PAGE.get(b.Agent_Form_Step__c);
        if (agentPage != null && agentPage > page) {
            line += agentPage > last ? ' (agent form: sent)' : ' (agent form: step ' + agentPage + ')';
        }
        return line + '.';
    }

    /** "Last asked 30 Oct 2026 by Ciara": o pedido mais novo saído de clients@ (não há email automático no Claims). */
    private static String lastAsked(Basic__c b) {
        String mark = '%' + SUBJECT_MARK + '%';
        List<EmailMessage> mails = [
            SELECT MessageDate, CreatedBy.FirstName FROM EmailMessage
            WHERE RelatedToId = :b.Id AND FromAddress = :CLIENTS_EMAIL AND Subject LIKE :mark
            ORDER BY MessageDate DESC NULLS LAST LIMIT 1
        ];
        if (mails.isEmpty() || mails[0].MessageDate == null) return null;
        String who = mails[0].CreatedBy == null ? null : mails[0].CreatedBy.FirstName;
        return 'Last asked ' + mails[0].MessageDate.format('d MMM yyyy') + (isBlank(who) ? '' : ' by ' + who);
    }

    // ------------------------------------------------------------------ the email

    public static String subject(Basic__c b) {
        return b.Name + ': ' + SUBJECT_MARK;
    }

    /** The agent's questions, one per line: blank lines, bullets and numbering dropped; at most 15. */
    @TestVisible
    private static List<String> questionLines(String raw) {
        List<String> out = new List<String>();
        if (isBlank(raw)) return out;
        for (String line : raw.split('\n')) {
            String q = line.replaceFirst('^\\s*(?:[-*\u2022]+|\\d+[.)])\\s*', '').trim();
            if (q.length() > 0 && out.size() < 15) out.add(q.abbreviate(400));
        }
        return out;
    }

    public static String html(Basic__c b, List<Item> forClient, String note, String sender) {
        return html(b, forClient, note, sender, null);
    }

    public static String html(Basic__c b, List<Item> forClient, String note, String sender, List<String> questions) {
        Boolean asking = questions != null && !questions.isEmpty();
        String p = '<p style="margin:0 0 14px 0;">';
        String h = '<div style="font-family:Arial,Helvetica,sans-serif;font-size:15px;line-height:1.5;color:#222222;max-width:620px;">';
        h += p + (isBlank(b.First_Name__c) ? 'Hello,' : 'Hi ' + b.First_Name__c.trim().escapeHtml4() + ',') + '</p>';
        if (!isBlank(note)) h += p + note.trim().escapeHtml4().replace('\n', '<br/>') + '</p>';
        if (asking) {
            h += p + 'Before we can send your claim to the UK Department for Work and Pensions (DWP), I have to clarify some information on your application. I have some questions:</p>';
            h += '<ul style="margin:0 0 6px 0;padding-left:22px;">';
            for (String q : questions) h += '<li style="margin:0 0 6px 0;">' + q.escapeHtml4() + '</li>';
            h += '</ul>';
            if (!forClient.isEmpty()) h += '<p style="margin:18px 0 6px 0;">We also need a few more details from you:</p>';
        } else {
            h += p + 'Before we can send your claim to the UK Department for Work and Pensions (DWP), we need a few more details from you:</p>';
        }
        for (GroupView g : grouped(b, forClient)) {
            h += '<p style="margin:18px 0 6px 0;font-weight:bold;">' + g.label.escapeHtml4() + '</p>';
            h += '<ul style="margin:0 0 6px 0;padding-left:22px;">';
            for (Item i : g.items) h += '<li style="margin:0 0 6px 0;">' + i.clientText.escapeHtml4() + '.</li>';
            h += '</ul>';
        }
        h += '<p style="margin:18px 0 14px 0;">You can simply reply to this email with the details, or send them by WhatsApp to ' + WHATSAPP + '.<br/>' + CLOSING + '</p>';
        h += p + 'Kind regards,<br/><br/>' + sender.escapeHtml4() + '<br/>XtraPension Client Support</p>';
        h += '<p style="margin:22px 0 0 0;font-size:13px;color:#666666;">XtraPension Ltd, Galway, Ireland<br/>'
            + 'Ireland: +353 (0)91 335 583 &nbsp;|&nbsp; Australia: +61 1300 339 559<br/>'
            + 'WhatsApp: ' + WHATSAPP + ' (messages only)<br/>' + CLIENTS_EMAIL + '</p>';
        return h + '</div>';
    }

    public static String text(Basic__c b, List<Item> forClient, String note, String sender) {
        return text(b, forClient, note, sender, null);
    }

    public static String text(Basic__c b, List<Item> forClient, String note, String sender, List<String> questions) {
        Boolean asking = questions != null && !questions.isEmpty();
        String t = (isBlank(b.First_Name__c) ? 'Hello,' : 'Hi ' + b.First_Name__c.trim() + ',') + '\n\n';
        if (!isBlank(note)) t += note.trim() + '\n\n';
        if (asking) {
            t += 'Before we can send your claim to the UK Department for Work and Pensions (DWP), I have to clarify some information on your application. I have some questions:\n';
            for (String q : questions) t += '- ' + q + '\n';
            if (!forClient.isEmpty()) t += '\nWe also need a few more details from you:\n';
        } else {
            t += 'Before we can send your claim to the UK Department for Work and Pensions (DWP), we need a few more details from you:\n';
        }
        for (GroupView g : grouped(b, forClient)) {
            t += '\n' + g.label + '\n';
            for (Item i : g.items) t += '- ' + i.clientText + '.\n';
        }
        t += '\nYou can simply reply to this email with the details, or send them by WhatsApp to ' + WHATSAPP + '.\n' + CLOSING + '\n\n';
        t += 'Kind regards,\n\n' + sender + '\nXtraPension Client Support\n\n';
        t += 'XtraPension Ltd, Galway, Ireland\nIreland: +353 (0)91 335 583 | Australia: +61 1300 339 559\nWhatsApp: ' + WHATSAPP + ' (messages only)\n' + CLIENTS_EMAIL + '\n';
        return t;
    }

    /** O mesmo pedido para o WhatsApp, no formato do Sales: títulos em *negrito*, sem rodapé, assinado com o C0xxxx. */
    public static String whatsApp(Basic__c b, List<Item> forClient, String note, String sender) {
        return whatsApp(b, forClient, note, sender, null);
    }

    public static String whatsApp(Basic__c b, List<Item> forClient, String note, String sender, List<String> questions) {
        Boolean asking = questions != null && !questions.isEmpty();
        String given = isBlank(b.First_Name__c) ? null : b.First_Name__c.trim().split('\\s+')[0];
        String t = (given == null ? 'Hello,' : 'Hi ' + given + ',') + ' ' + (isBlank(note) ? '' : note.trim() + ' ');
        if (asking) {
            t += 'Before we can send your claim to the DWP, I have to clarify some information on your application. I have some questions:\n';
            for (String q : questions) t += '- ' + q + '\n';
            if (!forClient.isEmpty()) t += '\nWe also need a few more details from you:\n';
        } else {
            t += 'Before we can send your claim to the DWP, we need a few more details from you:\n';
        }
        for (GroupView g : grouped(b, forClient)) {
            t += '\n*' + g.label + '*\n';
            for (Item i : g.items) t += '- ' + i.clientText + '.\n';
        }
        return t + '\nYou can reply here with the details. ' + CLOSING + '\n\n'
            + sender + ', XtraPension (' + b.Name + ')';
    }

    // ------------------------------------------------------------------ wording helpers

    // Single only (a blank status still asks about the spouse): rows and answers about a spouse left from an earlier
    // status are kept on the claim but not asked for (12/11/2026 audit)
    private static Boolean isSingle(Basic__c b) {
        return b.Claimant_marital_Status__c == 'Single';
    }

    private static Boolean hasSpouse(Basic__c b) {
        return !isBlank(b.Claimant_marital_Status__c) && b.Claimant_marital_Status__c != 'Single';
    }

    // "Partner: State Pension" = "Is your husband getting a UK State Pension now?" (Short Form) and "Getting Pension"
    // (long form); "Partner: Claiming UK Pension" is the long form's spouse question. Is_Your_Partner_Currently_Get_Pension__c
    // is left out: it asks about any pension or benefit of either of them, where they live now.
    private static Boolean needsSpouseEmployers(Basic__c b) {
        if (isSingle(b)) return false;
        if (b.Track__c != 'B' && b.Track__c != 'C') return false;
        // "Forgot" from the Short Form stays set after the NINO is found: a NINO on the claim ends the trace
        if ((b.Partner_Has_Nino_values__c == 'Forgot' && isBlank(b.Partner_Nino__c)) || b.Claimant_marital_Status__c == 'Widowed') return true;
        if (b.Claimant_marital_Status__c == 'Remarried' && b.Previous_Marriage_Ended__c == 'Widowed') return true;
        // On a UK pension the DWP already holds the record: with the NINO on the claim the employers add nothing
        // (John and Fernando, 17/11/2026). Without the NINO they are still what finds it.
        return (b.Partner_State_Pension__c == true || b.Partner_Claiming_UK_Pension__c == true) && isBlank(b.Partner_Nino__c);
    }

    // The spouse's sex from their own title, else the opposite of the claimant's, else neutral.
    private static String spouseSex(Basic__c b) {
        String partner = normaliseTitle(b.Partner_Title__c);
        if (partner == 'mr') return 'm';
        if (partner == 'mrs' || partner == 'ms' || partner == 'miss') return 'f';
        String own = normaliseTitle(b.Claimant_title__c);
        if (own == 'mrs' || own == 'ms' || own == 'miss') return 'm';
        if (own == 'mr') return 'f';
        return 'n';
    }

    private static String spouseBase(Basic__c b) {
        String sex = spouseSex(b);
        return sex == 'm' ? 'husband' : sex == 'f' ? 'wife' : 'husband or wife';
    }

    private static String spouseNoun(Basic__c b) {
        String status = b.Claimant_marital_Status__c;
        if (status == 'Civil Partner') return 'civil partner';
        if (status == 'Widowed') return 'late ' + spouseBase(b);
        if (status == 'Divorced' || status == 'Separated') return 'former ' + spouseBase(b);
        if (status == 'Remarried') return (b.Previous_Marriage_Ended__c == 'Widowed' ? 'late ' : 'former ') + spouseBase(b);
        return spouseBase(b);
    }

    private static String spousePronoun(Basic__c b) {
        String sex = b.Claimant_marital_Status__c == 'Civil Partner' ? 'n' : spouseSex(b);
        return sex == 'm' ? 'he' : sex == 'f' ? 'she' : 'they';
    }

    private static String spousePossessive(Basic__c b) {
        String sex = b.Claimant_marital_Status__c == 'Civil Partner' ? 'n' : spouseSex(b);
        return sex == 'm' ? 'his' : sex == 'f' ? 'her' : 'their';
    }

    private static String agentPrefix(Basic__c b, Boolean partner) {
        return partner ? capitalise(spouseNoun(b)) + ', ' : '';
    }

    private static String normaliseTitle(String title) {
        return isBlank(title) ? '' : title.toLowerCase().replace('.', '').trim();
    }

    private static String taxNumberName(Claimant_Country_lived__c c) {
        String code = isBlank(c.Country_Type__c) ? '' : c.Country_Type__c.trim().toUpperCase();
        String name = isBlank(c.Name) ? '' : c.Name.trim().toLowerCase();
        if (code == 'IE' || name.contains('ireland')) return 'PPS number';
        if (code == 'AU' || name.contains('australia')) return 'Tax File Number (TFN)';
        if (code == 'NZ' || name.contains('new zealand')) return 'IRD number';
        if (code == 'CA' || name.contains('canada')) return 'Social Insurance Number';
        if (code == 'US' || name.contains('united states') || name == 'usa') return 'Social Security number';
        return 'social security or tax number';
    }

    private static String postcodeWord(String country) {
        return !isBlank(country) && country.trim().toLowerCase().contains('ireland') ? 'Eircode' : 'postcode';
    }

    private static Boolean isAustralianBank(Basic__c b) {
        return (b.Bank_Country_Code__c != null && b.Bank_Country_Code__c.trim().toUpperCase() == 'AU')
            || (b.Bank_Country__c != null && b.Bank_Country__c.trim().toLowerCase() == 'australia');
    }

    private static Boolean isCanadianBank(Basic__c b) {
        return (b.Bank_Country_Code__c != null && b.Bank_Country_Code__c.trim().toUpperCase() == 'CA')
            || (b.Bank_Country__c != null && b.Bank_Country__c.trim().toLowerCase() == 'canada');
    }

    private static String fromTo(Boolean noFrom, Boolean noTo) {
        return noFrom && noTo ? 'dates' : noFrom ? 'start date' : 'end date';
    }

    // Helper sempre em cópia quando tem e-mail e não é o mesmo do cliente (Fernando, 04/11/2026); a caixa
    // CC_Helper_on_All_Comms__c deixou de decidir (o portal já a marca sempre que há e-mail do helper).
    private static String ccAddress(Basic__c b) {
        if (isBlank(b.Friend_Email__c)) return null;
        String cc = b.Friend_Email__c.trim();
        return cc.equalsIgnoreCase(isBlank(b.Email__c) ? '' : b.Email__c.trim()) ? null : cc;
    }

    private static String senderName() {
        String first = UserInfo.getFirstName();
        return isBlank(first) ? 'The XtraPension team' : first;
    }

    @TestVisible
    private static String joinParts(List<String> parts) {
        if (parts.isEmpty()) return '';
        if (parts.size() == 1) return parts[0];
        List<String> head = new List<String>();
        for (Integer i = 0; i < parts.size() - 1; i++) head.add(parts[i]);
        return String.join(head, ', ') + ' and ' + parts[parts.size() - 1];
    }

    private static String capitalise(String s) {
        return isBlank(s) ? s : s.substring(0, 1).toUpperCase() + s.substring(1);
    }

    private static Boolean isBlank(String s) {
        return String.isBlank(s);
    }

    private static void add(List<Item> items, String groupKey, String agentText, String clientText, List<String> fields) {
        items.add(new Item(groupKey, agentText, clientText, fields, false));
    }
}