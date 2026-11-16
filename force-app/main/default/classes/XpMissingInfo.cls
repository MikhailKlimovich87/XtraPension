/**
 * What is still missing on a sales application before it can go to HMRC, written for two readers:
 * a short line for the agent (the Missing Information panel, xpMissingInfo, from Form In Progress to
 * QC Approved) and a plain sentence for the client (the email the agent sends from the panel after a preview).
 *
 * The checks follow what the documents print (the CF83 reads the flat fields of the application, not the
 * Employer__c rows; the 64-8; the cover letter) and what the team asks clients for in practice.
 * Rules and the data behind them: docs/sales-missing-info/README.md (Claude XP repo).
 *
 * Rules worth knowing:
 *  - Parts of one thing are one item (an address, an employer, from/to dates), and employers are named.
 *  - Class 2 needs evidence of work abroad, an UPLOAD file: the PRSI statement in Ireland, a document per
 *    year from 2019 to 2024 in Australia and New Zealand, a social security statement elsewhere. Class 3 needs none.
 *  - The work history abroad must cover 2019 (or the date the client left the UK, if later) to today:
 *    gaps of more than a year are asked.
 *  - Postcodes and towns the client may not know are asked softly and do not block.
 *  - Checks only an agent can act on (formats, CF83 fields out of step, the Class) are never sent to the client.
 *  - The client form link is never put in the email: opening it moves the application back to Form In Progress.
 */
public with sharing class XpMissingInfo {

    public static final Set<String> STAGES = new Set<String>{
        'Form In Progress', 'Form Completed', 'NINO/Doc Needed', 'Pending Client', 'Fix', 'Agent Check', 'QC Approved'
    };
    public static final String CLIENTS_EMAIL = 'clients@xtrapension.com';
    public static final String WHATSAPP = '+353 (0)83 123 4000';
    public static final String OFFICE = '+353 (0)91 335 583';
    /** In the subject of every email this panel sends; also how the panel finds them again. */
    public static final String SUBJECT_MARK = 'a few details we still need for your UK pension application';
    /** Subject of the automatic "Missing Info" template (ApplicationManagerHandler.sendEmailWithEmptyData). */
    private static final String AUTO_SUBJECT_MARK = 'MISSING INFO REQUIRED';

    // The team's own videos, as in their email templates.
    private static final String NINO_VIDEO = 'https://xpen.uk/5ways';
    private static final String WORK_VIDEO = 'https://xpen.uk/work';
    private static final String PRSI_VIDEO = 'https://xpen.uk/socins';
    private static final String SUPER_VIDEO = 'https://xpen.uk/superdocs';
    private static final String STATEMENT_LINK = 'https://xpen.uk/statement';

    /** Years of evidence the validation agents ask Australian and New Zealand clients for ("First contact email"). */
    private static final Integer EVIDENCE_FROM = 2019;
    private static final Integer EVIDENCE_TO = 2024;
    /** The work history is checked for gaps from here, or from the date the client left the UK when that is later. */
    private static final Date HISTORY_FROM = Date.newInstance(2019, 1, 1);
    private static final Integer GAP_DAYS = 365;

    private static final String G_YOU = 'About you';
    private static final String G_UK = 'Your life in the UK';
    private static final String G_ABROAD = 'Since you left the UK';
    private static final String G_DOCS = 'Documents';
    private static final String G_AGENT = 'For you to check';
    private static final List<String> GROUP_ORDER = new List<String>{ G_YOU, G_UK, G_ABROAD, G_DOCS, G_AGENT };

    public class Item {
        @AuraEnabled public String groupKey;
        @AuraEnabled public String agentText;
        /** What the client is asked; null for checks only the agent can act on (never sent to the client). */
        @AuraEnabled public String clientText;
        /** Asked of the client, but the application can go ahead without it. */
        @AuraEnabled public Boolean optional;
        /** Ticked when the agent opens the email. Every Sales item starts ticked (the agent can untick it). */
        @AuraEnabled public Boolean askByDefault = true;
        Item(String groupKey, String agentText, String clientText, Boolean optional) {
            this.groupKey = groupKey;
            this.agentText = agentText;
            this.clientText = clientText;
            this.optional = optional;
        }
    }

    public class GroupView {
        @AuraEnabled public String label;
        @AuraEnabled public List<Item> items = new List<Item>();
    }

    // ------------------------------------------------------------------ reading the application

    public static Application__c load(Id appId) {
        return [
            SELECT Id, Name, Status__c, Step__c, Contact__c, Email__c, Related_Contact_Phone__c, Missing_Info_Send_Date__c,
                   Salutation__c, First_Name__c, Second_Name__c, Date_Of_Birth__c, National_Insurance_Number__c,
                   Are_You_Single__c, Are_You_Divorced__c, Date_Of_Marriage_Or_Civil_Partnership__c, Divorce_Date__c,
                   Did_You_Change_Name__c, Full_Maiden_Previous_Name__c,
                   Current_Address_Abroad__Street__s, Current_Address_Abroad__PostalCode__s,
                   Current_Address_Abroad__CountryCode__s, Current_Address_Abroad_Country__c,
                   Previous_UK_Address_1__Street__s, Previous_UK_Address_1__City__s, Previous_UK_Address_1__PostalCode__s,
                   Last_UK_Home_Address__Street__s, Last_UK_Home_Address__City__s, Last_UK_Home_Address__PostalCode__s,
                   Date_Of_Leaving_Last_UK__c, Years_Of_Work_In_The_UK__c, Type_Of_Employment__c,
                   Last_UK_Employer_Name__c, Last_UK_Employer_Start_Date__c, Last_UK_Employer_End_Date__c,
                   Last_UK_Employer_Address__Street__s, Last_UK_Employer_Address__City__s, Last_UK_Employer_Address__PostalCode__s,
                   Date_of_Last_Pay_Contributions__c,
                   SelfEmployment_Employment_Abroad__c, Abroad_Employer_Name1__c, Self_Employed_Start_Date1__c, Request_Data__c,
                   Pay_Voluntary_Contribution_At__c, Freeform_RichText_Line1__c, Appeal_Application__c,
                   (SELECT Type_Of_After_UK_Employment__c, Employer_Name__c, Start_Date__c, End_Date__c, Current_Work__c,
                           Employers_Address__Street__s, Employers_Address__CountryCode__s, Employers_Address_Country__c
                    FROM Employers__r WHERE Type__c = 'Work After UK' ORDER BY Start_Date__c ASC NULLS LAST, CreatedDate)
            FROM Application__c
            WHERE Id = :appId
        ];
    }

    /** Titles of the files on the application: in Salesforce and those moved to S3 (AWS_S3_File__c). */
    public static List<String> fileTitles(Id appId) {
        return new Files().titles(appId);
    }

    // Files are read without sharing: an agent who can open the application must see what is on it.
    private without sharing class Files {
        List<String> titles(Id appId) {
            List<String> out = new List<String>();
            for (ContentDocumentLink l : [SELECT ContentDocument.Title FROM ContentDocumentLink WHERE LinkedEntityId = :appId LIMIT 1000]) {
                out.add(l.ContentDocument.Title);
            }
            for (AWS_S3_File__c f : [SELECT Title__c FROM AWS_S3_File__c WHERE Application__c = :appId LIMIT 1000]) {
                out.add(f.Title__c);
            }
            return out;
        }
    }

    // ------------------------------------------------------------------ the checks

    public static List<Item> check(Application__c a, List<String> files) {
        List<Item> items = new List<Item>();
        aboutYou(a, items);
        ukLife(a, items);
        abroad(a, items);
        documents(a, files, items);
        return items;
    }

    private static void aboutYou(Application__c a, List<Item> items) {
        List<String> name = new List<String>();
        if (isBlank(a.First_Name__c)) name.add('first name');
        if (isBlank(a.Second_Name__c)) name.add('surname');
        if (!name.isEmpty()) ask(items, G_YOU, 'Name: ' + joinParts(name), 'Your ' + joinParts(name) + ', as on your passport');
        if (isBlank(a.Salutation__c)) ask(items, G_YOU, 'Title (CF83 Q1)', 'Your title (Mr, Mrs, Ms, Miss or Dr)');
        if (a.Date_Of_Birth__c == null) ask(items, G_YOU, 'Date of birth (CF83 Q2)', 'Your date of birth');

        String nino = isBlank(a.National_Insurance_Number__c) ? '' : a.National_Insurance_Number__c.deleteWhitespace().toUpperCase();
        if (nino == '') {
            ask(items, G_YOU, 'NINO (CF83 Q6 and 64-8)',
                'Your UK National Insurance number. It is on old UK payslips, P45s, P60s and letters from HMRC or the DWP. If you can\'t find it, this short video shows 5 ways to get it: ' + NINO_VIDEO);
        } else if (!validNino(nino)) {
            agent(items, 'NINO looks wrong (' + nino + '): it should be 2 letters, 6 numbers and A, B, C or D');
        }
        if (isBlank(a.Related_Contact_Phone__c)) ask(items, G_YOU, 'Phone', 'A phone number we can reach you on');

        // Home address abroad (CF83 Q7 and Q8, 64-8). The town is often written in the street lines, so it is not asked.
        String code = countryCode(a);
        String postcodeWord = code == 'IE' ? 'Eircode' : 'postcode';
        List<String> address = new List<String>();
        if (isBlank(a.Current_Address_Abroad__Street__s)) address.add('street address');
        if (isBlank(a.Current_Address_Abroad__PostalCode__s)) address.add(postcodeWord);
        if (!hasCountry(a)) address.add('country');
        if (!address.isEmpty()) {
            ask(items, G_YOU, 'Home address: ' + joinParts(address) + ' (CF83 Q8)',
                address.size() >= 2 ? 'Your full home address, including the ' + postcodeWord : 'The ' + address[0] + ' of your home address');
        }
        if (code == 'IE' && !isBlank(a.Current_Address_Abroad__PostalCode__s) && !validEircode(a.Current_Address_Abroad__PostalCode__s)) {
            agent(items, 'Eircode looks wrong (' + a.Current_Address_Abroad__PostalCode__s.trim() + '): Eircodes have no O, I, S, B or L (often typed for 0, 1, 5 or 8)');
        }
        relationship(a, items);
    }

    private static void relationship(Application__c a, List<Item> items) {
        // Until the client has passed the Relationship step, "not single" only means "not answered yet".
        Boolean answered = !(a.Status__c == 'Form In Progress'
            && (isBlank(a.Step__c) || a.Step__c == 'Personal Details' || a.Step__c == 'Relationship'));
        if (a.Are_You_Single__c != true && a.Date_Of_Marriage_Or_Civil_Partnership__c == null) {
            if (!answered && a.Are_You_Divorced__c != true) {
                ask(items, G_YOU, 'Relationship: not answered yet',
                    'Whether you are single, married, divorced or widowed, and the date of your marriage if you married');
            } else {
                ask(items, G_YOU, 'Date of marriage (CF83 Q4)', 'The date of your marriage (or civil partnership)');
            }
        }
        if (a.Are_You_Divorced__c == true && a.Divorce_Date__c == null) {
            ask(items, G_YOU, 'Date of divorce or bereavement (CF83 Q5)',
                'The date of your divorce or separation, or the date your husband or wife passed away');
        }
        if (a.Did_You_Change_Name__c == true && isBlank(a.Full_Maiden_Previous_Name__c)) {
            ask(items, G_YOU, 'Former name (CF83 Q4)', 'Your former name (for example your maiden name), as it was when you lived in the UK');
        }
    }

    private static void ukLife(Application__c a, List<Item> items) {
        // CF83 Q3 prints Previous UK Address 1; the form writes it together with the Last UK Home Address.
        Boolean prevHome = !isBlank(a.Previous_UK_Address_1__Street__s);
        Boolean lastHome = !isBlank(a.Last_UK_Home_Address__Street__s);
        if (!prevHome && !lastHome) {
            ask(items, G_UK, 'Last UK home address (CF83 Q3)', 'Your last home address in the UK, with the town and the postcode if you remember it');
        } else {
            if (!prevHome) agent(items, 'CF83 Q3 prints Previous UK Address 1, which is empty: copy the Last UK Home Address into it');
            List<String> parts = new List<String>();
            if (isBlank(prevHome ? a.Previous_UK_Address_1__City__s : a.Last_UK_Home_Address__City__s)) parts.add('town');
            if (isBlank(prevHome ? a.Previous_UK_Address_1__PostalCode__s : a.Last_UK_Home_Address__PostalCode__s)) parts.add('postcode');
            if (!parts.isEmpty()) {
                softly(items, G_UK, 'Last UK home: ' + joinParts(parts), 'The ' + joinParts(parts) + ' of your last home in the UK, if you remember');
            }
        }
        if (a.Date_Of_Leaving_Last_UK__c == null) {
            ask(items, G_UK, 'Date left the UK (CF83 Q10)',
                'The date you left the UK to live abroad (the month and year are enough if you don\'t remember the day)');
        }
        if (a.Years_Of_Work_In_The_UK__c == null) {
            ask(items, G_UK, 'Years in the UK', 'How many years in total you lived and worked in the UK');
        }

        String ukWork = a.Type_Of_Employment__c;
        Boolean noFrom = a.Last_UK_Employer_Start_Date__c == null;
        Boolean noTo = a.Last_UK_Employer_End_Date__c == null;
        if (isBlank(ukWork)) {
            ask(items, G_UK, 'Work before leaving the UK (CF83 Q13)',
                'What you were doing just before you left the UK: working for an employer, self-employed, unemployed or not working');
        } else if (ukWork == 'Employed') {
            lastUkEmployer(a, items);
        } else if (ukWork == 'Self-Employed' && (noFrom || noTo)) {
            ask(items, G_UK, 'UK self-employment: ' + fromTo(noFrom, noTo),
                noFrom && noTo ? 'Roughly when you started and stopped being self-employed in the UK (month and year)'
                    : noFrom ? 'Roughly when you started being self-employed in the UK (month and year)'
                    : 'Roughly when you stopped being self-employed in the UK (month and year)');
        }
        if ((ukWork == 'Employed' || ukWork == 'Self-Employed') && a.Date_of_Last_Pay_Contributions__c == null && !noTo) {
            agent(items, 'CF83 Q14 (date last paid NI) is empty: it is normally the end date of the last UK job');
        }
    }

    private static void lastUkEmployer(Application__c a, List<Item> items) {
        if (isBlank(a.Last_UK_Employer_Name__c)) {
            ask(items, G_UK, 'Last UK employer: name, address and dates (CF83 Q15)',
                'Your last job in the UK: the employer\'s name and address, and roughly when you started and left (even if the company no longer exists)');
            return;
        }
        String employer = a.Last_UK_Employer_Name__c.trim();
        List<String> parts = new List<String>();
        if (isBlank(a.Last_UK_Employer_Address__Street__s)) parts.add('street');
        if (isBlank(a.Last_UK_Employer_Address__City__s)) parts.add('town');
        if (isBlank(a.Last_UK_Employer_Address__PostalCode__s)) parts.add('postcode');
        if (parts.size() >= 2) {
            ask(items, G_UK, employer + ': address (CF83 Q15)', employer + ': the address where you worked (the town and postcode are enough)');
        } else if (parts.size() == 1) {
            softly(items, G_UK, employer + ': ' + parts[0], employer + ': the ' + parts[0] + ' where you worked, if you know it');
        }
        Boolean noFrom = a.Last_UK_Employer_Start_Date__c == null;
        Boolean noTo = a.Last_UK_Employer_End_Date__c == null;
        if (noFrom || noTo) {
            ask(items, G_UK, employer + ': ' + fromTo(noFrom, noTo),
                noFrom && noTo ? employer + ': roughly when you started and when you left (month and year)'
                    : noFrom ? employer + ': roughly when you started there (month and year)'
                    : employer + ': roughly when you left (month and year)');
        }
    }

    private static void abroad(Application__c a, List<Item> items) {
        List<Employer__c> rows = a.Employers__r;
        if (rows.isEmpty()) {
            ask(items, G_ABROAD, 'Work after the UK: none listed',
                'What you have done since you left the UK, up to today: each job (the employer\'s name and address, and when you started and left), any self-employment, and any time not working, such as a career break, caring for family or retirement. This short video explains it: ' + WORK_VIDEO);
            return;
        }
        Employer__c firstWork;
        Boolean anyWork = false;
        for (Employer__c e : rows) {
            String kind = e.Type_Of_After_UK_Employment__c;
            Boolean job = kind == 'Employed';
            if (job || kind == 'Self-Employed') {
                anyWork = true;
                if (firstWork == null && e.Start_Date__c != null) firstWork = e;
            }
            String label = rowLabel(e);
            if (job && isBlank(e.Employer_Name__c)) {
                ask(items, G_ABROAD, label + ': employer name and address',
                    'The name and address of the employer you worked for' + (e.Start_Date__c == null ? '' : ' from ' + monthYear(e.Start_Date__c, false)));
            } else if (job) {
                List<String> parts = new List<String>();
                if (isBlank(e.Employers_Address__Street__s)) parts.add('address');
                if (isBlank(e.Employers_Address__CountryCode__s) && isBlank(e.Employers_Address_Country__c)) parts.add('country');
                if (!parts.isEmpty()) ask(items, G_ABROAD, label + ': ' + joinParts(parts), label + ': the employer\'s ' + joinParts(parts));
            }
            Boolean noFrom = e.Start_Date__c == null;
            Boolean noTo = e.End_Date__c == null && e.Current_Work__c != 'Yes';
            if (noFrom || noTo) {
                ask(items, G_ABROAD, label + ': ' + fromTo(noFrom, noTo),
                    noFrom && noTo ? label + ': when it started and ended (month and year), or tell us if it is still going on'
                        : noFrom ? label + ': when it started (month and year)'
                        : label + ': when it ended (month and year), or tell us if it is still going on');
            }
        }
        gaps(a, rows, items);

        if (firstWork != null && a.Date_Of_Leaving_Last_UK__c != null && firstWork.Start_Date__c.daysBetween(a.Date_Of_Leaving_Last_UK__c) > 30) {
            agent(items, 'Work abroad starts ' + dayMonthYear(firstWork.Start_Date__c) + ', before the date left the UK ('
                + dayMonthYear(a.Date_Of_Leaving_Last_UK__c) + '): check with the client');
        }
        if (isClass2(a) && !anyWork) {
            agent(items, 'Class 2 chosen, but no job or self-employment abroad is listed: check whether it should be Class 3');
        }
        // The CF83 prints the first job abroad from flat fields. Generate Docs sends them as they are;
        // Redo a Form recomputes them for the PDF only (its payload, Request_Data__c, then names the job).
        if (firstWork != null) {
            Boolean redone = !isBlank(a.Request_Data__c) && !isBlank(firstWork.Employer_Name__c) && a.Request_Data__c.contains(firstWork.Employer_Name__c.trim());
            if (firstWork.Type_Of_After_UK_Employment__c == 'Employed' && isBlank(a.Abroad_Employer_Name1__c) && !redone) {
                agent(items, 'CF83 Q18 (job abroad) fields are empty, so Generate Docs leaves Q18 blank: Redo a Form fills it from ' + rowLabel(firstWork));
            } else if (firstWork.Type_Of_After_UK_Employment__c == 'Self-Employed' && a.Self_Employed_Start_Date1__c == null
                    && a.SelfEmployment_Employment_Abroad__c != 'Employed' && isBlank(a.Request_Data__c)) {
                agent(items, 'CF83 Q19 (self-employed abroad) has no start date, so Generate Docs leaves it blank: Redo a Form fills it');
            }
        }
    }

    /** Periods of more than a year with nothing in the work history, from 2019 (or leaving the UK) to today. */
    private static void gaps(Application__c a, List<Employer__c> rows, List<Item> items) {
        Date todayDate = Date.today();
        Date fromDate = a.Date_Of_Leaving_Last_UK__c != null && a.Date_Of_Leaving_Last_UK__c > HISTORY_FROM ? a.Date_Of_Leaving_Last_UK__c : HISTORY_FROM;
        if (fromDate >= todayDate) return;
        Date covered = fromDate;
        Boolean dated = false;
        for (Employer__c e : rows) {
            if (e.Start_Date__c == null) continue;
            dated = true;
            // An open row (current, or with its end date missing, which is asked above) runs to today.
            Date endDate = e.Current_Work__c == 'Yes' || e.End_Date__c == null ? todayDate : e.End_Date__c;
            if (endDate <= fromDate) continue;
            Date startDate = e.Start_Date__c < fromDate ? fromDate : e.Start_Date__c;
            if (covered.daysBetween(startDate) > GAP_DAYS) {
                ask(items, G_ABROAD, 'Work history: gap ' + monthYear(covered, true) + ' to ' + monthYear(startDate, true),
                    'What you were doing between ' + monthYear(covered, false) + ' and ' + monthYear(startDate, false)
                    + ': working (the employer\'s name and address), self-employed, or not working (for example caring for family or retired)');
            }
            if (endDate > covered) covered = endDate;
        }
        if (dated && covered.daysBetween(todayDate) > GAP_DAYS) {
            ask(items, G_ABROAD, 'Work history: nothing since ' + monthYear(covered, true),
                'What you have been doing since ' + monthYear(covered, false)
                + ', up to today: working (the employer\'s name and address), self-employed, or not working (for example caring for family or retired)');
        }
    }

    private static void documents(Application__c a, List<String> files, List<Item> items) {
        Boolean class2 = isClass2(a);
        if (class2 && !hasFile(files, new List<String>{ 'UPLOAD' })) {
            String code = countryCode(a);
            if (code == 'IE') {
                ask(items, G_DOCS, 'Class 2 evidence: PRSI statement (no UPLOAD file)',
                    'Your PRSI contribution statement from the Department of Social Protection. This short video shows how to ask for it online: '
                    + PRSI_VIDEO + '. You can also ring them on 0818 690 690 with your PPS number ready');
            } else if (code == 'AU' || code == 'NZ') {
                ask(items, G_DOCS, 'Class 2 evidence: a document per year ' + EVIDENCE_FROM + ' to ' + EVIDENCE_TO + ' (no UPLOAD file)',
                    'A document for each year from ' + EVIDENCE_FROM + ' to ' + EVIDENCE_TO
                    + ' showing you were working, such as your tax return statements or superannuation summaries (the summary page for each year is enough). This short video explains it: ' + SUPER_VIDEO);
            } else {
                ask(items, G_DOCS, 'Class 2 evidence: social security statement (no UPLOAD file)',
                    'A statement of your social security contributions, or another record of your work, from the country where you live. This page explains it: ' + STATEMENT_LINK);
            }
        }
        if (a.Appeal_Application__c == true && !hasFile(files, new List<String>{ 'C3', 'C2', 'HMRC', 'REJECT' })) {
            softly(items, G_DOCS, 'C3 appeal: no HMRC letter on file',
                'The letter HMRC sent you about your application (the Class 3 decision or the rejection): a photo or scan of every page');
        }
        if (!class2 && isClass3(a) && !isBlank(a.Freeform_RichText_Line1__c) && a.Freeform_RichText_Line1__c.contains('Class 2')) {
            agent(items, 'Cover letter still asks HMRC about Class 2, but Class 3 is chosen: change the first paragraph in the Doc Editor');
        }
    }

    // ------------------------------------------------------------------ what the callers get

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

    public static List<GroupView> grouped(List<Item> items) {
        Map<String, GroupView> byKey = new Map<String, GroupView>();
        for (Item i : items) {
            GroupView g = byKey.get(i.groupKey);
            if (g == null) {
                g = new GroupView();
                g.label = i.groupKey;
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

    // ------------------------------------------------------------------ panel (xpMissingInfo)

    @AuraEnabled
    public static Map<String, Object> refresh(Id appId) {
        Application__c a = load(appId);
        List<Item> items = check(a, fileTitles(appId));
        Integer missing = 0, optional = 0, checks = 0;
        for (Item i : items) {
            if (i.clientText == null) checks++;
            else if (i.optional == true) optional++;
            else missing++;
        }
        return new Map<String, Object>{
            'groups' => grouped(items),
            'missing' => missing,
            'optional' => optional,
            'checks' => checks,
            'clientCount' => missing + optional,
            'hasEmail' => !isBlank(a.Email__c),
            'inStage' => STAGES.contains(a.Status__c),
            'step' => a.Status__c == 'Form In Progress' ? a.Step__c : null,
            'lastAsked' => lastAsked(a)
        };
    }

    @AuraEnabled
    public static Map<String, Object> preview(Id appId, String note) {
        return previewLeavingOut(appId, note, null);
    }

    @AuraEnabled
    public static String sendEmail(Id appId, String note) {
        return sendLeavingOut(appId, note, null);
    }

    /** The email and the WhatsApp text without the items the agent left unticked (XpMissingInfoPanel). */
    public static Map<String, Object> previewLeavingOut(Id appId, String note, List<String> leaveOut) {
        Application__c a = load(appId);
        List<Item> forClient = without(clientItems(check(a, fileTitles(appId))), leaveOut);
        String sender = senderName();
        return new Map<String, Object>{
            'to' => a.Email__c,
            'subject' => subject(a),
            'html' => html(a, forClient, note, sender),
            'whatsapp' => whatsApp(a, forClient, note, sender),
            'count' => forClient.size()
        };
    }

    public static String sendLeavingOut(Id appId, String note, List<String> leaveOut) {
        Application__c a = load(appId);
        if (!STAGES.contains(a.Status__c)) throw new AuraHandledException('The application is past QC Approved: nothing is sent from here.');
        List<Item> all = clientItems(check(a, fileTitles(appId)));
        if (all.isEmpty()) throw new AuraHandledException('There is nothing to ask the client.');
        List<Item> forClient = without(all, leaveOut);
        if (forClient.isEmpty()) throw new AuraHandledException('Nothing is ticked: tick at least one item to ask the client.');
        if (isBlank(a.Email__c)) throw new AuraHandledException('This application has no client email.');

        String sender = senderName();
        String htmlBody = html(a, forClient, note, sender);
        String textBody = text(a, forClient, note, sender);
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setSubject(subject(a));
        mail.setHtmlBody(htmlBody);
        mail.setPlainTextBody(textBody);
        mail.setUseSignature(false);
        List<OrgWideEmailAddress> owea = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :CLIENTS_EMAIL LIMIT 1];
        if (!owea.isEmpty()) mail.setOrgWideEmailAddressId(owea[0].Id);

        // With a contact the email is saved on the application by Salesforce; without one it is logged below.
        Boolean logged = false;
        if (a.Contact__c != null) {
            List<Contact> contacts = [SELECT Email FROM Contact WHERE Id = :a.Contact__c LIMIT 1];
            mail.setTargetObjectId(a.Contact__c);
            mail.setWhatId(a.Id);
            mail.setSaveAsActivity(true);
            Boolean sameAddress = !contacts.isEmpty() && contacts[0].Email != null && contacts[0].Email.equalsIgnoreCase(a.Email__c);
            if (!sameAddress) {
                mail.setTreatTargetObjectAsRecipient(false);
                mail.setToAddresses(new List<String>{ a.Email__c });
            }
            logged = true;
        } else {
            mail.setToAddresses(new List<String>{ a.Email__c });
        }
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        if (!logged) {
            insert new EmailMessage(
                RelatedToId = a.Id, Subject = subject(a), HtmlBody = htmlBody, TextBody = textBody,
                ToAddress = a.Email__c, FromAddress = CLIENTS_EMAIL, FromName = 'XtraPension Client Support',
                Incoming = false, Status = '3', MessageDate = System.now()
            );
        }
        return 'Sent to ' + a.Email__c + '.';
    }

    /** "Last asked 30 Oct 2026 by Ciara": the newest request sent from clients@, this panel's or the automatic one. */
    private static String lastAsked(Application__c a) {
        String oursLike = '%' + SUBJECT_MARK + '%';
        String autoLike = '%' + AUTO_SUBJECT_MARK + '%';
        List<EmailMessage> mails = [
            SELECT MessageDate, Subject, CreatedBy.FirstName, CreatedBy.Name FROM EmailMessage
            WHERE RelatedToId = :a.Id AND FromAddress = :CLIENTS_EMAIL AND (Subject LIKE :oursLike OR Subject LIKE :autoLike)
            ORDER BY MessageDate DESC LIMIT 1
        ];
        if (!mails.isEmpty() && mails[0].MessageDate != null) {
            EmailMessage m = mails[0];
            Boolean automatic = m.Subject.containsIgnoreCase(AUTO_SUBJECT_MARK) && m.CreatedBy.Name == 'XtraPension Admin';
            return 'Last asked ' + m.MessageDate.format('d MMM yyyy')
                + (automatic ? ' (the automatic Missing Info email)' : isBlank(m.CreatedBy.FirstName) ? '' : ' by ' + m.CreatedBy.FirstName);
        }
        if (a.Missing_Info_Send_Date__c != null) {
            return 'Last asked ' + dayMonthYear(a.Missing_Info_Send_Date__c) + ' (the automatic Missing Info email)';
        }
        return null;
    }

    // ------------------------------------------------------------------ the email

    public static String subject(Application__c a) {
        return a.Name + ': ' + SUBJECT_MARK;
    }

    private static String intro(Application__c a) {
        return a.Status__c == 'Form In Progress'
            ? 'Thank you for starting your UK pension application with us. To finish it, we need a few more details from you:'
            : 'Thank you for your UK pension application. Before we can send it to HMRC, we need a few more details from you:';
    }

    private static final String CLOSING = 'If you don\'t have something, just tell us and we\'ll help you find it.';

    public static String html(Application__c a, List<Item> forClient, String note, String sender) {
        String p = '<p style="margin:0 0 14px 0;">';
        String given = firstName(a);
        String h = '<div style="font-family:Arial,Helvetica,sans-serif;font-size:15px;line-height:1.5;color:#222222;max-width:620px;">';
        h += p + (given == null ? 'Hello,' : 'Hi ' + given.escapeHtml4() + ',') + '</p>';
        if (!isBlank(note)) h += p + note.trim().escapeHtml4().replace('\n', '<br/>') + '</p>';
        h += p + intro(a) + '</p>';
        for (GroupView g : grouped(forClient)) {
            h += '<p style="margin:18px 0 6px 0;font-weight:bold;">' + g.label.escapeHtml4() + '</p>';
            h += '<ul style="margin:0 0 6px 0;padding-left:22px;">';
            for (Item i : g.items) h += '<li style="margin:0 0 6px 0;">' + linkify(i.clientText.escapeHtml4()) + '.</li>';
            h += '</ul>';
        }
        h += '<p style="margin:18px 0 14px 0;">You can simply reply to this email with the details and documents, or send them by WhatsApp to '
            + WHATSAPP + '. ' + CLOSING + '</p>';
        h += p + 'Kind regards,<br/>' + sender.escapeHtml4() + '<br/>XtraPension Client Support</p>';
        h += '<p style="margin:22px 0 0 0;font-size:13px;color:#666666;">XtraPension Ltd, Galway, Ireland<br/>'
            + 'Office: ' + OFFICE + ' &nbsp;|&nbsp; WhatsApp: ' + WHATSAPP + ' (messages only)<br/>' + CLIENTS_EMAIL + '</p>';
        return h + '</div>';
    }

    public static String text(Application__c a, List<Item> forClient, String note, String sender) {
        String given = firstName(a);
        String t = (given == null ? 'Hello,' : 'Hi ' + given + ',') + '\n\n';
        if (!isBlank(note)) t += note.trim() + '\n\n';
        t += intro(a) + '\n';
        for (GroupView g : grouped(forClient)) {
            t += '\n' + g.label + '\n';
            for (Item i : g.items) t += '- ' + i.clientText + '.\n';
        }
        t += '\nYou can simply reply to this email with the details and documents, or send them by WhatsApp to ' + WHATSAPP + '. ' + CLOSING + '\n\n';
        t += 'Kind regards,\n' + sender + '\nXtraPension Client Support\n\n';
        t += 'XtraPension Ltd, Galway, Ireland\nOffice: ' + OFFICE + ' | WhatsApp: ' + WHATSAPP + ' (messages only)\n' + CLIENTS_EMAIL + '\n';
        return t;
    }

    /** The same request for WhatsApp, where many clients answer: *bold* headings, no footer. */
    public static String whatsApp(Application__c a, List<Item> forClient, String note, String sender) {
        String given = firstName(a);
        String t = (given == null ? 'Hello,' : 'Hi ' + given + ',') + ' ' + (isBlank(note) ? '' : note.trim() + ' ') + intro(a) + '\n';
        for (GroupView g : grouped(forClient)) {
            t += '\n*' + g.label + '*\n';
            for (Item i : g.items) t += '- ' + i.clientText + '.\n';
        }
        return t + '\nYou can reply here with the details and documents. ' + CLOSING + '\n\n' + sender + ', XtraPension (' + a.Name + ')';
    }

    // ------------------------------------------------------------------ helpers

    private static String rowLabel(Employer__c e) {
        String kind = e.Type_Of_After_UK_Employment__c;
        String fromText = e.Start_Date__c == null ? '' : ' from ' + monthYear(e.Start_Date__c, false);
        if (kind == 'Employed') return isBlank(e.Employer_Name__c) ? 'Job' + fromText : e.Employer_Name__c.trim();
        Map<String, String> names = new Map<String, String>{
            'Self-Employed' => 'Self-employment', 'Career Break' => 'Career break', 'Unemployed' => 'Time unemployed',
            'Family Carer' => 'Time caring for family', 'Homemaker' => 'Time as a homemaker', 'Disabled' => 'Time not working (disability)',
            'Retired' => 'Retirement', 'Education' => 'Time in education', 'Illness' => 'Time not working (illness)'
        };
        return (names.containsKey(kind) ? names.get(kind) : 'Period') + fromText;
    }

    @TestVisible
    private static Boolean validNino(String nino) {
        return Pattern.matches('(?!BG|GB|NK|KN|TN|NT|ZZ)[A-CEGHJ-PR-TW-Z][A-CEGHJ-NPR-TW-Z][0-9]{6}[A-D]', nino);
    }

    @TestVisible
    private static Boolean validEircode(String code) {
        return Pattern.matches('[ACDEFHKNPRTVWXY][0-9][0-9W][0-9ACDEFHKNPRTVWXY]{4}', code.deleteWhitespace().toUpperCase());
    }

    private static String countryCode(Application__c a) {
        if (!isBlank(a.Current_Address_Abroad__CountryCode__s)) return a.Current_Address_Abroad__CountryCode__s.trim().toUpperCase();
        String name = isBlank(a.Current_Address_Abroad_Country__c) ? '' : a.Current_Address_Abroad_Country__c.trim().toLowerCase();
        if (name.contains('ireland')) return 'IE';
        if (name.contains('australia')) return 'AU';
        if (name.contains('new zealand')) return 'NZ';
        return '';
    }

    private static Boolean hasCountry(Application__c a) {
        return !isBlank(a.Current_Address_Abroad__CountryCode__s) || !isBlank(a.Current_Address_Abroad_Country__c);
    }

    private static Boolean isClass2(Application__c a) {
        return a.Pay_Voluntary_Contribution_At__c != null && a.Pay_Voluntary_Contribution_At__c.contains('Class 2');
    }

    private static Boolean isClass3(Application__c a) {
        return a.Pay_Voluntary_Contribution_At__c != null && a.Pay_Voluntary_Contribution_At__c.contains('Class 3');
    }

    private static Boolean hasFile(List<String> titles, List<String> marks) {
        for (String t : titles) {
            if (t == null) continue;
            String upper = t.toUpperCase();
            for (String m : marks) {
                if (upper.contains(m)) return true;
            }
        }
        return false;
    }

    /** Turns the team's xpen.uk links into links (the text is already escaped). */
    private static String linkify(String escaped) {
        return escaped.replaceAll('https://xpen\\.uk/[A-Za-z0-9]+', '<a href="$0" style="color:#1aa2b0;">$0</a>');
    }

    /** The first given name only: First_Name__c often holds middle names too ("Mark Joseph"). */
    private static String firstName(Application__c a) {
        return isBlank(a.First_Name__c) ? null : a.First_Name__c.trim().split('\\s+')[0];
    }

    private static String monthYear(Date d, Boolean shortForm) {
        return Datetime.newInstanceGmt(d.year(), d.month(), 1).formatGmt(shortForm ? 'MMM yyyy' : 'MMMM yyyy');
    }

    private static String dayMonthYear(Date d) {
        return Datetime.newInstanceGmt(d.year(), d.month(), d.day()).formatGmt('d MMM yyyy');
    }

    private static String fromTo(Boolean noFrom, Boolean noTo) {
        return noFrom && noTo ? 'dates' : noFrom ? 'start date' : 'end date';
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

    private static Boolean isBlank(String s) {
        return String.isBlank(s);
    }

    private static void ask(List<Item> items, String groupKey, String agentText, String clientText) {
        items.add(new Item(groupKey, agentText, clientText, false));
    }

    private static void softly(List<Item> items, String groupKey, String agentText, String clientText) {
        items.add(new Item(groupKey, agentText, clientText, true));
    }

    private static void agent(List<Item> items, String agentText) {
        items.add(new Item(G_AGENT, agentText, null, false));
    }
}