@isTest
public class ClaimsPriorityQueueControllerTest {
    static final Date TODAY = Date.today();
    static Integer seq = 0;

    static String fakeId(Schema.SObjectType type) {
        seq++;
        return type.getDescribe().getKeyPrefix() + String.valueOf(seq).leftPad(12, '0');
    }

    // records built from JSON so read-only fields (CreatedDate, formulas, Last Contact) can be set
    static Basic__c claim(String status, Map<String, Object> extra) {
        Map<String, Object> m = new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'Basic__c' },
            'Id' => fakeId(Basic__c.SObjectType),
            'Name' => 'C0' + String.valueOf(5000 + seq),
            'First_Name__c' => 'Ross',
            'Last_Name__c' => 'Cooper',
            'Status__c' => status,
            'Validation_Agent__c' => 'Sean B',
            'CreatedDate' => Datetime.now().addDays(-30),
            'Deposit_Payment_Date__c' => TODAY.addDays(-30),
            // big envelope sent and posted, signed pages back: no pack action unless a test changes it
            'FTP_Claim_Created_Send_Date__c' => TODAY.addDays(-29),
            'Big_Envelop_Posted_Date__c' => TODAY.addDays(-28),
            'Claim_Full_Form_ZIP_for_UPLOAD__c' => true,
            'Missing_Info__c' => 'Form Fully Completed'
        };
        if (extra != null) m.putAll(extra);
        return (Basic__c) JSON.deserialize(JSON.serialize(m), Basic__c.class);
    }

    static Basic__c freshSale(String status, Integer saleDaysAgo, Map<String, Object> extra) {
        Map<String, Object> m = new Map<String, Object>{
            'Deposit_Payment_Date__c' => TODAY.addDays(-saleDaysAgo),
            'FTP_Claim_Created_Send_Date__c' => null,
            'Big_Envelop_Posted_Date__c' => null,
            'Claim_Full_Form_ZIP_for_UPLOAD__c' => false
        };
        if (extra != null) m.putAll(extra);
        return claim(status, m);
    }

    static EmailMessage email(Boolean incoming, Integer daysAgo, String processed) {
        Map<String, Object> m = new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'EmailMessage' },
            'Id' => fakeId(EmailMessage.SObjectType),
            'Incoming' => incoming,
            'MessageDate' => Datetime.now().addDays(-daysAgo),
            'CreatedDate' => Datetime.now().addDays(-daysAgo),
            'FromAddress' => incoming ? 'ross@example.com' : 'clients@xtrapension.com',
            'Subject' => 'My bank details',
            'Has_message_been_processed__c' => processed
        };
        return (EmailMessage) JSON.deserialize(JSON.serialize(m), EmailMessage.class);
    }

    static Call_Log__c call(String direction, String outcome, Integer daysAgo) {
        return (Call_Log__c) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'Call_Log__c' },
            'Id' => fakeId(Call_Log__c.SObjectType),
            'Direction__c' => direction,
            'Outcome__c' => outcome,
            'Started_At__c' => Datetime.now().addDays(-daysAgo)
        }), Call_Log__c.class);
    }

    static Claim_Check__c check(String flag, Integer daysAgo) {
        return (Claim_Check__c) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'Claim_Check__c' },
            'Id' => fakeId(Claim_Check__c.SObjectType),
            'CreatedDate' => Datetime.now().addDays(-daysAgo),
            'Check_Date__c' => TODAY.addDays(-daysAgo),
            'Check_Agents__c' => 'Vince',
            'Notes__c' => 'DWP wants a copy of the marriage certificate',
            'More_Info_Requested__c' => flag == 'More_Info_Requested__c',
            'Rejected__c' => flag == 'Rejected__c'
        }), Claim_Check__c.class);
    }

    static ClaimsPriorityQueueController.Item run(Basic__c b, Integer enteredDaysAgo) {
        return ClaimsPriorityQueueController.evaluate(b, TODAY.addDays(-enteredDaysAgo), null, null, null, TODAY);
    }

    static Integer days(String key) {
        return ClaimsPriorityQueueController.DAYS.get(key);
    }

    // ------------------------------------------------------------------ problem: the big envelope

    @isTest
    static void zipErrorIsAProblemFromTheSaleDay() {
        Basic__c b = freshSale('Form In Progress', 2, new Map<String, Object>{
            'FTP_Claim_Created_ZIP_Error__c' => 'Pink Page.pdf file is missing.', 'Val_Call_Booked_Date__c' => callText(TODAY.addDays(2))
        });
        ClaimsPriorityQueueController.Item item = run(b, 2);
        System.assertEquals('problem', item.lane);
        System.assertEquals('Big envelope not sent: fix the ZIP error', item.actions[0].text);
        System.assert(item.actions[0].why.contains('Pink Page.pdf'), item.actions[0].why);
        System.assertEquals(TODAY.addDays(-2), item.due);
        System.assertEquals(2, item.daysOverdue);
        // the call booked in 2 days is listed too, as upcoming
        System.assertEquals(2, item.actions.size());
        System.assertEquals('Do the validation call', item.actions[1].text);
        System.assertEquals(-2, item.actions[1].daysOverdue);
    }

    @isTest
    static void uploadErrorAndStuckZip() {
        ClaimsPriorityQueueController.Item failed = run(freshSale('Form In Progress', 1, new Map<String, Object>{ 'FTP_Claim_Created_Error__c' => 'SFTP timeout' }), 1);
        System.assertEquals('Big envelope not sent: the upload to the printer failed', failed.actions[0].text);

        ClaimsPriorityQueueController.Item waiting = run(freshSale('Pending Client', 3, new Map<String, Object>{ 'Claim_Created_ZIP_for_UPLOAD__c' => true }), 3);
        System.assertEquals('Big envelope not sent to the printer yet', waiting.actions[0].text);
        System.assert(waiting.actions[0].why.contains('waits for the hourly upload'));
        System.assertEquals(3 - days('stage1Send'), waiting.actions[0].daysOverdue);

        ClaimsPriorityQueueController.Item none = run(freshSale('Pending Client', 3, null), 3);
        System.assert(none.actions[0].why.contains('Collect Stage 1'), none.actions[0].why);
    }

    @isTest
    static void printerHasNotPostedTheBigEnvelope() {
        Basic__c b = freshSale('Form completed', 6, new Map<String, Object>{ 'FTP_Claim_Created_Send_Date__c' => TODAY.addDays(-5) });
        ClaimsPriorityQueueController.Item item = run(b, 0);
        System.assertEquals('problem', item.lane);
        System.assertEquals('The printer has not posted the big envelope: ask WDM', item.actions[0].text);
        System.assertEquals(5 - days('printerPost'), item.daysOverdue);
        // Form completed today is our next move too, due tomorrow
        System.assertEquals('next', item.actions[1].lane);
    }

    // ------------------------------------------------------------------ pack: the signed pages coming back

    @isTest
    static void signedPackNotBackAfterPosting() {
        Map<String, Object> posted = new Map<String, Object>{
            'Big_Envelop_Posted_Date__c' => TODAY.addDays(-15), 'Claim_Full_Form_ZIP_for_UPLOAD__c' => false, 'Big_Envelop_Tracking_Number__c' => 'RR123IE'
        };
        ClaimsPriorityQueueController.Item ie = run(claim('Sent for eSignature', posted), 1);
        // the pack is due; the 1st DocuSign follow-up call comes in 2 days
        System.assertEquals('pack', ie.lane);
        System.assertEquals('esign', ie.actions[1].lane);
        ClaimsPriorityQueueController.Action pack = ie.actions[0];
        System.assertEquals('Signed pack not back 14 days after posting: call the client', pack.text);
        System.assertEquals(15 - days('signedPack'), pack.daysOverdue);
        System.assert(pack.why.contains('RR123IE'));

        Map<String, Object> au = posted.clone();
        au.put('Current_Address_Abroad_Country__c', 'AU');
        ClaimsPriorityQueueController.Item far = run(claim('Signed - Waiting Docs at WDM', au), 1);
        System.assertEquals(15 - days('signedPackFar'), far.actions[0].daysOverdue);
        System.assertEquals('pack', far.lane); // not due yet, but within the upcoming window

        Map<String, Object> called = posted.clone();
        called.put('Last_Contact_At__c', Datetime.now().addDays(-2));
        called.put('Contact_Type__c', 'Phone Chat');
        called.put('Who__c', 'Sean Byrne');
        ClaimsPriorityQueueController.Item again = run(claim('Signed - Waiting Docs at WDM', called), 1);
        System.assertEquals(2 - days('signedPackEvery'), again.actions[0].daysOverdue);
        System.assert(again.actions[0].why.contains('Phone Chat, Sean Byrne'), again.actions[0].why);
    }

    @isTest
    static void stageTwoAtThePrinter() {
        ClaimsPriorityQueueController.Item resend = run(claim('Signed - Waiting Docs at WDM', null), 2);
        System.assertEquals('next', resend.lane);
        System.assert(resend.actions[0].text.contains('Resend Big Envelope (Stage 2)'));
        System.assertEquals(2 - days('nextStep'), resend.daysOverdue);

        ClaimsPriorityQueueController.Item notPosted = run(claim('Signed - Waiting Docs at WDM', new Map<String, Object>{
            'FTP_Claim_Full_Form_Created_Send_Date__c' => TODAY.addDays(-4)
        }), 6);
        System.assertEquals('The printer has not posted the claim to the DWP: ask WDM', notPosted.actions[0].text);
        System.assertEquals(4 - days('stage2Post'), notPosted.daysOverdue);

        ClaimsPriorityQueueController.Item zip = run(claim('Signed - Waiting Docs at WDM', new Map<String, Object>{
            'FTP_Claim_Full_Form_ZIP_Error__c' => 'IPCBR1.pdf file is missing.'
        }), 1);
        System.assertEquals('Stage 2 pack not sent: fix the error', zip.actions[0].text);
        System.assertEquals('problem', zip.lane);

        // signed and nothing back yet, big envelope posted 5 days ago: nothing due within the window
        System.assertEquals(null, run(claim('Signed - Waiting Docs at WDM', new Map<String, Object>{
            'Big_Envelop_Posted_Date__c' => TODAY.addDays(-5), 'Claim_Full_Form_ZIP_for_UPLOAD__c' => false
        }), 1));
    }

    // ------------------------------------------------------------------ reply

    @isTest
    static void unansweredEmailIsDueTheDayItCame() {
        Basic__c b = claim('Posted to DWP', null);
        List<EmailMessage> mails = new List<EmailMessage>{ email(true, 1, 'Not Done'), email(true, 3, null), email(false, 5, null) };
        ClaimsPriorityQueueController.Item item = ClaimsPriorityQueueController.evaluate(b, TODAY.addDays(-10), null, mails, null, TODAY);
        System.assertEquals('reply', item.lane);
        System.assertEquals(3, item.daysOverdue); // waiting since the older of the two
        System.assert(item.actions[0].why.contains('2 emails waiting'), item.actions[0].why);
        System.assertEquals(3, item.actions[0].daysWaiting);

        // marked Done, or answered after it, or our reply is the newest: nothing to do
        System.assertEquals(null, ClaimsPriorityQueueController.evaluate(b, TODAY, null, new List<EmailMessage>{ email(true, 1, 'Done') }, null, TODAY));
        System.assertEquals(null, ClaimsPriorityQueueController.evaluate(b, TODAY, null, new List<EmailMessage>{ email(false, 0, null), email(true, 1, null) }, null, TODAY));
        EmailMessage ourCopy = email(true, 0, null);
        ourCopy.FromAddress = 'seanb@xtrapension.com';
        System.assertEquals(null, ClaimsPriorityQueueController.evaluate(b, TODAY, null, new List<EmailMessage>{ ourCopy, email(true, 1, null) }, null, TODAY));
        Basic__c answered = claim('Posted to DWP', new Map<String, Object>{ 'Last_Contact_At__c' => Datetime.now().addHours(-1), 'Contact_Type__c' => 'Email Sent' });
        System.assertEquals(null, ClaimsPriorityQueueController.evaluate(answered, TODAY, null, new List<EmailMessage>{ email(true, 1, null) }, null, TODAY));
        // a call nobody picked up is not an answer
        Basic__c noAnswer = claim('Posted to DWP', new Map<String, Object>{ 'Last_Contact_At__c' => Datetime.now().addHours(-1), 'Contact_Type__c' => 'No Answer' });
        System.assertEquals('reply', ClaimsPriorityQueueController.evaluate(noAnswer, TODAY, null, new List<EmailMessage>{ email(true, 1, null) }, null, TODAY).lane);
    }

    @isTest
    static void missedCallNotReturned() {
        Basic__c b = claim('Posted to DWP', null);
        ClaimsPriorityQueueController.Item item = ClaimsPriorityQueueController.evaluate(b, TODAY.addDays(-10), null, null,
            new List<Call_Log__c>{ call('Inbound', 'Missed', 1), call('Outbound', 'Answered', 4) }, TODAY);
        System.assertEquals('reply', item.lane);
        System.assert(item.actions[0].text.startsWith('Call the client back: missed call on'));
        System.assertEquals(1, item.daysOverdue);
        // spoke to the client after the missed call
        System.assertEquals(null, ClaimsPriorityQueueController.evaluate(b, TODAY.addDays(-10), null, null,
            new List<Call_Log__c>{ call('Outbound', 'Answered', 0), call('Inbound', 'Missed', 1) }, TODAY));
    }

    @isTest
    static void closedClaimOnlyShowsForAnEmail() {
        System.assertEquals(null, run(claim('Closed', null), 100));
        System.assertEquals(null, run(freshSale('Deposit Refund', 40, null), 5));
        ClaimsPriorityQueueController.Item item = ClaimsPriorityQueueController.evaluate(claim('Closed Won', null), TODAY.addDays(-100), null,
            new List<EmailMessage>{ email(true, 0, 'Not Done') }, null, TODAY);
        System.assertEquals('reply', item.lane);
        System.assertEquals(1, item.actions.size());
    }

    // ------------------------------------------------------------------ call

    @isTest
    static void validationCall() {
        Basic__c none = claim('Form In Progress', new Map<String, Object>{ 'Deposit_Payment_Date__c' => TODAY.addDays(-3) });
        ClaimsPriorityQueueController.Item book = run(none, 3);
        System.assertEquals('call', book.lane);
        System.assertEquals('Book the validation call', book.actions[0].text);
        System.assertEquals(3 - days('bookCall'), book.daysOverdue);

        Basic__c onTheDay = claim('Form In Progress', new Map<String, Object>{ 'Val_Call_Booked_Date__c' => callText(TODAY) });
        ClaimsPriorityQueueController.Item doIt = run(onTheDay, 1);
        System.assertEquals('Do the validation call', doIt.actions[0].text);
        System.assertEquals(0, doIt.daysOverdue);

        Basic__c later = claim('Form In Progress', new Map<String, Object>{ 'Val_Call_Booked_Date__c' => callText(TODAY.addDays(20)) });
        System.assertEquals(null, run(later, 1));

        Basic__c past = claim('Validation Call', new Map<String, Object>{ 'Val_Call_Booked_Date__c' => callText(TODAY.addDays(-3)) });
        ClaimsPriorityQueueController.Item finish = run(past, 5);
        System.assertEquals('Finish the form and press Send to Validation', finish.actions[0].text);
        System.assertEquals(3 - days('afterCall'), finish.daysOverdue);
    }

    static String callText(Date d) {
        return String.valueOf(d.day()).leftPad(2, '0') + '/' + String.valueOf(d.month()).leftPad(2, '0') + '/' + d.year() + ' 10:00 (Irish time) - Sean B';
    }

    // ------------------------------------------------------------------ chase and next

    @isTest
    static void pendingClientIsChasedThenEveryFewDays() {
        Basic__c b = claim('Pending Client', new Map<String, Object>{
            'Missing_Info__c' => 'Countries lived: none listed; Bank: account holder name; Bank: IBAN and BIC'
        });
        ClaimsPriorityQueueController.Item first = run(b, 5);
        System.assertEquals('chase', first.lane);
        System.assertEquals('Chase the client for: countries lived, bank details', first.actions[0].text);
        System.assertEquals(5 - days('chaseFirst'), first.daysOverdue);
        System.assert(first.actions[0].why.contains('no contact since'));

        b.Last_Contact_At__c = Datetime.now().addDays(-1);
        b.Contact_Type__c = 'No Answer';
        ClaimsPriorityQueueController.Item next = run(b, 5);
        System.assertEquals(1 - days('chaseEvery'), next.daysOverdue);

        Basic__c complete = claim('Pending Client', null);
        ClaimsPriorityQueueController.Item send = run(complete, 2);
        System.assertEquals('next', send.lane);
        System.assertEquals('Everything is in: press Send to Validation on the claim', send.actions[0].text);
        System.assert(send.actions[0].why.contains('as saved on the claim'), send.actions[0].why);
    }

    @isTest
    static void liveMissingInfoWinsOverTheSavedOne() {
        // saved list says complete, the live one does not: chase for the live items
        Basic__c b = claim('Pending Client', null);
        ClaimsPriorityQueueController.Item item = ClaimsPriorityQueueController.evaluate(b, TODAY.addDays(-2), null, null, null,
            'Bank: IBAN and BIC; UK employers: none listed', null, TODAY);
        System.assertEquals('chase', item.lane);
        System.assertEquals('Chase the client for: bank details, UK employers', item.actions[0].text);
        System.assert(!item.actions[0].why.contains('as saved'), item.actions[0].why);

        // saved list is stale, the live one is complete
        Basic__c stale = claim('QC Approved', new Map<String, Object>{ 'Missing_Info__c' => 'Countries lived: none listed' });
        ClaimsPriorityQueueController.Item ready = ClaimsPriorityQueueController.evaluate(stale, TODAY.addDays(-2), null, null, null,
            'Form Fully Completed', null, TODAY);
        System.assertEquals('Send the DocuSign', ready.actions[0].text);

        // a claim that cannot be read keeps its saved list (nothing in the map)
        Id missingClaim = fakeId(Basic__c.SObjectType);
        System.assertEquals(0, ClaimsPriorityQueueController.liveMissing(new List<Id>{ missingClaim }).size());
    }

    @isTest
    static void ourMoveAfterTheFormIsComplete() {
        ClaimsPriorityQueueController.Item formDone = run(claim('Form completed', null), 3);
        System.assertEquals('next', formDone.lane);
        System.assertEquals('Check the forms and move the claim to Agent Check', formDone.actions[0].text);
        System.assertEquals(3 - days('nextStep'), formDone.daysOverdue);

        System.assertEquals(null, formDone.actions[0].owner); // the validation agent's

        ClaimsPriorityQueueController.Item qc = run(claim('Agent Check', null), 2);
        System.assertEquals('QC the claim and move it to QC Approved', qc.actions[0].text);
        System.assertEquals(ClaimsPriorityQueueController.QC_OWNER, qc.actions[0].owner); // the QC person's, whoever the validation agent is
        System.assertEquals('Sean B', qc.agent);
        ClaimsPriorityQueueController.Item docuSign = run(claim('QC Approved', null), 2);
        System.assertEquals('Send the DocuSign', docuSign.actions[0].text);
        System.assertEquals(ClaimsPriorityQueueController.QC_OWNER, docuSign.actions[0].owner); // QC sends the DocuSign (call of 11/11/2026 17h13)

        ClaimsPriorityQueueController.Item blocked = run(claim('QC Approved', new Map<String, Object>{ 'Missing_Info__c' => 'UK employers: none listed' }), 2);
        System.assertEquals('chase', blocked.lane);
        System.assertEquals('Chase the client for: UK employers (the DocuSign is blocked until then)', blocked.actions[0].text);
        System.assertEquals(null, blocked.actions[0].owner); // chasing what is missing stays with the validation agent
    }

    // ------------------------------------------------------------------ esign

    @isTest
    static void docuSignFollowUpsCountFromTheLastContact() {
        ClaimsPriorityQueueController.Item first = run(claim('Sent for eSignature', null), 4);
        System.assertEquals('esign', first.lane);
        System.assertEquals('DocuSign not signed: follow up with the client (or ask the validation agent to chase)', first.actions[0].text);
        System.assertEquals(4 - days('esignFirst'), first.daysOverdue);
        System.assertEquals(ClaimsPriorityQueueController.QC_OWNER, first.actions[0].owner); // QC chases the DocuSign
        System.assert(first.actions[0].why.contains('no contact with the client since'), first.actions[0].why);

        // spoke 2 days ago: the next follow-up is 3 days after that
        ClaimsPriorityQueueController.Item spoke = run(claim('Sent for eSignature', new Map<String, Object>{
            'Last_Contact_At__c' => Datetime.now().addDays(-2), 'Contact_Type__c' => 'Phone Chat', 'Who__c' => 'Ciara'
        }), 6);
        System.assertEquals('DocuSign not signed: follow up again (or ask the validation agent to chase)', spoke.actions[0].text);
        System.assertEquals(2 - days('esignEvery'), spoke.daysOverdue);
        System.assert(spoke.actions[0].why.contains('(Phone Chat, Ciara)'), spoke.actions[0].why);

        // a call nobody answered, or a contact from before the DocuSign, does not move the follow-up
        ClaimsPriorityQueueController.Item noAnswer = run(claim('Sent for eSignature', new Map<String, Object>{
            'Last_Contact_At__c' => Datetime.now().addDays(-2), 'Contact_Type__c' => 'No Answer'
        }), 6);
        System.assertEquals('DocuSign not signed: follow up with the client (or ask the validation agent to chase)', noAnswer.actions[0].text);
        System.assertEquals(6 - days('esignFirst'), noAnswer.daysOverdue);
        ClaimsPriorityQueueController.Item older = run(claim('Sent for eSignature', new Map<String, Object>{
            'Last_Contact_At__c' => Datetime.now().addDays(-8), 'Contact_Type__c' => 'Email Sent'
        }), 6);
        System.assertEquals('DocuSign not signed: follow up with the client (or ask the validation agent to chase)', older.actions[0].text);

        // 3 answered calls since it went out: decide, a week after the last contact
        Basic__c b = claim('Sent for eSignature', new Map<String, Object>{
            'Last_Contact_At__c' => Datetime.now().addDays(-8), 'Contact_Type__c' => 'Phone Chat'
        });
        ClaimsPriorityQueueController.Item decide = ClaimsPriorityQueueController.evaluate(b, TODAY.addDays(-15), null, null, null,
            null, days('esignFollowUps'), TODAY);
        System.assertEquals('Not signed after 3 follow-up calls: decide what to do (call again or On Hold)', decide.actions[0].text);
        System.assertEquals(8 - days('esignDecide'), decide.daysOverdue);
        System.assert(decide.actions[0].why.contains('3 answered calls since it went out'), decide.actions[0].why);
        ClaimsPriorityQueueController.Item two = ClaimsPriorityQueueController.evaluate(b, TODAY.addDays(-15), null, null, null, null, 2, TODAY);
        System.assertEquals('DocuSign not signed: follow up again (or ask the validation agent to chase)', two.actions[0].text);
    }

    // ------------------------------------------------------------------ dwp and hold

    @isTest
    static void dwpOnlyWhenTheCheckAsksSomethingOfUs() {
        Basic__c b = claim('Posted to DWP', null);
        System.assertEquals(null, ClaimsPriorityQueueController.evaluate(b, TODAY.addDays(-20), null, null, null, TODAY));
        System.assertEquals(null, ClaimsPriorityQueueController.evaluate(b, TODAY.addDays(-20), check('Approved__c', 2), null, null, TODAY));

        ClaimsPriorityQueueController.Item more = ClaimsPriorityQueueController.evaluate(b, TODAY.addDays(-20), check('More_Info_Requested__c', 2), null, null, TODAY);
        System.assertEquals('dwp', more.lane);
        System.assertEquals('The DWP asked for more information: get it from the client', more.actions[0].text);
        System.assertEquals(2, more.daysOverdue);
        System.assert(more.actions[0].why.contains('marriage certificate'));

        ClaimsPriorityQueueController.Item rejected = ClaimsPriorityQueueController.evaluate(claim('45D Check', null), TODAY.addDays(-20), check('Rejected__c', 1), null, null, TODAY);
        System.assertEquals('The DWP rejected the claim: call the client', rejected.actions[0].text);

        ClaimsPriorityQueueController.Item agentCall = run(claim('Agent Call', null), 2);
        System.assertEquals('Call the client about the DWP decision', agentCall.actions[0].text);
        System.assertEquals(2 - days('agentCall'), agentCall.daysOverdue);

        ClaimsPriorityQueueController.Item dd = run(claim('Charge DD', null), 3);
        System.assertEquals('dwp', dd.lane);
        System.assert(dd.actions[0].text.contains('no direct debit mandate'));
        System.assertEquals(3 - days('chargeDd'), dd.daysOverdue);
        System.assertEquals('Charge our fee by direct debit', run(claim('Charge DD', new Map<String, Object>{ 'GoCardless_Mandate_Id__c' => 'MD01' }), 3).actions[0].text);
    }

    @isTest
    static void onHoldIsReviewedAfterAWhile() {
        ClaimsPriorityQueueController.Item item = run(claim('On Hold', new Map<String, Object>{ 'Blocker__c' => 'Waiting for the death certificate' }), 40);
        System.assertEquals('hold', item.lane);
        System.assertEquals(40 - days('onHoldReview'), item.daysOverdue);
        System.assert(item.actions[0].why.contains('death certificate'));
        System.assertEquals(null, run(claim('On Hold', null), 10));
        // the big envelope rules do not apply while on hold
        System.assertEquals(null, run(freshSale('On Hold', 10, null), 10));
    }

    @isTest
    static void unknownStageIsFlagged() {
        ClaimsPriorityQueueController.Item item = run(claim('Brand New Stage', null), 1);
        System.assertEquals('problem', item.lane);
        System.assert(item.actions[0].text.contains('new to this queue'));
        System.assertEquals('The claim has no stage: set one', run(claim(null, null), 1).actions[0].text);
    }

    @isTest
    static void everyStageHasARule() {
        Set<String> known = new Set<String>(ClaimsPriorityQueueController.CALL_STAGES);
        known.add('Pending Client');
        known.addAll(ClaimsPriorityQueueController.NEXT_STEPS.keySet());
        known.addAll(ClaimsPriorityQueueController.PACK_STAGES);
        known.addAll(ClaimsPriorityQueueController.DWP_STAGES);
        known.addAll(new Set<String>{ 'Agent Call', 'Charge DD', 'On Hold' });
        known.addAll(ClaimsPriorityQueueController.IGNORED_STAGES.keySet());
        // the stages of 11/11/2026; a stage added later shows in the queue as "new to this queue" instead of failing here
        for (String stage : new List<String>{ 'Form In Progress', 'Validation Call', 'Form completed', 'Pending Client', 'Agent Check',
                'QC Approved', 'Sent for eSignature', 'Signed - Waiting Docs at WDM', 'Posted to DWP', '45D Check', 'Awaiting Lump Sum Letter',
                'Agent Call', 'Decision Posted to DWP', 'Awaiting DWP Payment', 'Charge DD', 'Closed Won', 'On Hold', 'Deposit Refund', 'Closed' }) {
            System.assert(known.contains(stage), 'no rule for ' + stage);
            ClaimsPriorityQueueController.Item item = run(claim(stage, null), 60);
            System.assert(item == null || !item.actions[0].text.contains('new to this queue'), stage);
        }
    }

    // ------------------------------------------------------------------ order and helpers

    @isTest
    static void orderIsLaneThenLongestOverdue() {
        List<ClaimsPriorityQueueController.Item> items = new List<ClaimsPriorityQueueController.Item>{
            run(claim('Form completed', null), 2),         // next, 1 day overdue
            run(claim('Pending Client', new Map<String, Object>{ 'Missing_Info__c' => 'Bank: IBAN and BIC' }), 9), // chase, 9 days
            run(claim('Form completed', null), 6),         // next, 5 days overdue
            ClaimsPriorityQueueController.evaluate(claim('Closed', null), TODAY, null, new List<EmailMessage>{ email(true, 0, null) }, null, TODAY), // reply
            run(claim('Form In Progress', new Map<String, Object>{ 'Val_Call_Booked_Date__c' => callText(TODAY.addDays(3)) }), 1) // upcoming call
        };
        items.sort();
        System.assertEquals('reply', items[0].lane);
        System.assertEquals('next', items[1].lane);
        System.assertEquals(5, items[1].daysOverdue);
        System.assertEquals(1, items[2].daysOverdue);
        System.assertEquals('chase', items[3].lane);
        System.assertEquals('call', items[4].lane); // not due yet: last
        System.assertEquals(-3, items[4].daysOverdue);
    }

    @isTest
    static void missingInfoInAFewWords() {
        System.assertEquals(null, ClaimsPriorityQueueController.missingWords('Form Fully Completed'));
        System.assertEquals(null, ClaimsPriorityQueueController.missingWords(null));
        System.assertEquals('bank details, UK employers', ClaimsPriorityQueueController.missingWords('Bank: IBAN and BIC; Bank: name; UK employers: none listed'));
        System.assertEquals('husband\'s details, wife\'s UK employers, Belgium',
            ClaimsPriorityQueueController.missingWords('Husband: NINO; Wife, UK employers: none listed; Belgium: social security number'));
        System.assertEquals('name, title, date of birth, phone number and 2 more',
            ClaimsPriorityQueueController.missingWords('Name: first name; Title; Date of birth; Phone; Marital status; NINO'));
    }

    @isTest
    static void readsTheBookedCallAndMapsTheUser() {
        System.assertEquals(Date.newInstance(2026, 11, 12), ClaimsPriorityQueueController.callDate('12/11/2026 10:00 (Irish time) - Becky'));
        System.assertEquals(null, ClaimsPriorityQueueController.callDate('soon'));
        System.assertEquals(null, ClaimsPriorityQueueController.callDate(''));

        List<String> agents = new List<String>{ 'Sean B', 'Ciara', 'Becky' };
        System.assertEquals('Sean B', ClaimsPriorityQueueController.agentFor('Sean', 'Sean Byrne', agents));
        System.assertEquals(null, ClaimsPriorityQueueController.agentFor('Sean', 'Sean Bedford', agents));
        System.assertEquals('Becky', ClaimsPriorityQueueController.agentFor('becky', 'Becky McAllister', agents));
        System.assertEquals(null, ClaimsPriorityQueueController.agentFor('Fernando', 'Fernando Rampon', agents));
        System.assertEquals(null, ClaimsPriorityQueueController.agentFor(null, null, agents));
    }

    // ------------------------------------------------------------------ the real query

    @isTest
    static void getQueueReadsClaimsAndLeavesOutTestOnes() {
        Basic__c real = new Basic__c(First_Name__c = 'Real', Last_Name__c = 'Client', Status__c = 'Pending Client', Validation_Agent__c = 'Ciara',
            Missing_Info__c = 'Bank: IBAN and BIC', FTP_Claim_Created_Send_Date__c = TODAY, Big_Envelop_Posted_Date__c = TODAY);
        Basic__c testClaim = new Basic__c(First_Name__c = 'Test', Last_Name__c = 'Claim', Status__c = 'Pending Client', Is_Test_Claim__c = true,
            Missing_Info__c = 'Bank: IBAN and BIC');
        Basic__c closed = new Basic__c(First_Name__c = 'Old', Last_Name__c = 'Client', Status__c = 'Closed');
        Basic__c closedQuiet = new Basic__c(First_Name__c = 'Quiet', Last_Name__c = 'Client', Status__c = 'Closed');
        Basic__c signing = new Basic__c(First_Name__c = 'Slow', Last_Name__c = 'Signer', Status__c = 'Sent for eSignature', Validation_Agent__c = 'Becky',
            FTP_Claim_Created_Send_Date__c = TODAY, Big_Envelop_Posted_Date__c = TODAY, Claim_Full_Form_ZIP_for_UPLOAD__c = true);
        insert new List<Basic__c>{ real, testClaim, closed, closedQuiet, signing };
        List<Call_Log__c> calls = new List<Call_Log__c>();
        for (Integer i = 0; i < 3; i++) {
            calls.add(new Call_Log__c(Claim__c = signing.Id, Direction__c = 'Outbound', Outcome__c = 'Answered', Started_At__c = Datetime.now(),
                Call_Key__c = 'test-' + i + '|' + signing.Id));
        }
        calls.add(new Call_Log__c(Claim__c = signing.Id, Direction__c = 'Outbound', Outcome__c = 'No answer', Started_At__c = Datetime.now(),
            Call_Key__c = 'test-x|' + signing.Id));
        insert calls;
        insert new List<EmailMessage>{
            new EmailMessage(Incoming = true, Claim__c = closed.Id, FromAddress = 'old.client@example.com', ToAddress = 'clients@xtrapension.com',
                Subject = 'Any news?', TextBody = 'Hi, any news?', MessageDate = Datetime.now(), Status = '0'),
            new EmailMessage(Incoming = true, Claim__c = testClaim.Id, FromAddress = 'test@example.com', ToAddress = 'clients@xtrapension.com',
                Subject = 'Test', TextBody = 'Test', MessageDate = Datetime.now(), Status = '0')
        };
        Test.startTest();
        ClaimsPriorityQueueController.QueueResult result = ClaimsPriorityQueueController.getQueue();
        Test.stopTest();
        System.assertEquals(3, result.items.size(), JSON.serialize(result.items));
        System.assertEquals(3, result.claimsLooked); // never the test claim; a closed one only when the client wrote
        Map<String, ClaimsPriorityQueueController.Item> byClient = new Map<String, ClaimsPriorityQueueController.Item>();
        for (ClaimsPriorityQueueController.Item i : result.items) byClient.put(i.client, i);

        ClaimsPriorityQueueController.Item reply = byClient.get('Old Client');
        System.assertEquals('reply', reply.lane);
        System.assertEquals('Closed', reply.stage);

        // Missing Info recomputed live by BP_MissingInfo: the claim has much more missing than its saved "Bank: IBAN and BIC"
        ClaimsPriorityQueueController.Item item = byClient.get('Real Client');
        System.assertEquals('chase', item.lane);
        System.assert(item.actions[0].text.startsWith('Chase the client for: '), item.actions[0].text);
        System.assertNotEquals('Chase the client for: bank details', item.actions[0].text);
        System.assert(!item.actions[0].why.contains('as saved'), item.actions[0].why);
        System.assertEquals(0, item.daysOverdue);
        System.assertEquals('Ciara', item.agent);
        System.assertEquals(1, result.liveMissingCount);
        System.assertEquals(0, result.savedMissingCount);

        // 3 answered calls since the DocuSign went out (the unanswered one does not count)
        ClaimsPriorityQueueController.Item slow = byClient.get('Slow Signer');
        System.assertEquals('esign', slow.lane);
        System.assert(slow.actions[0].text.startsWith('Not signed after 3 follow-up calls'), slow.actions[0].text);
        System.assertEquals(ClaimsPriorityQueueController.QC_OWNER, result.qcOwner);
        System.assert(result.agents.contains('Becky'));
        System.assertEquals(ClaimsPriorityQueueController.LANES, result.lanes);
        System.assertEquals(1, result.days.get('stage1Send'));
        System.assertEquals(false, result.truncated);
    }
}