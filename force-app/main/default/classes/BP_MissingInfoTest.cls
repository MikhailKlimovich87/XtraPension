@IsTest
private class BP_MissingInfoTest {

    private static Basic__c claim(Map<String, Object> fields) {
        Contact c = new Contact(LastName = 'Snow', Email = 'john.snow@example.com');
        insert c;
        Basic__c b = BP_TestDataFactory.createBasic(c.Id, false);
        b.Email__c = 'john.snow@example.com';
        for (String f : fields.keySet()) b.put(f, fields.get(f));
        insert b;
        return b;
    }

    private static String agentLines(Id basicId) {
        return String.join(BP_MissingInfo.agentTexts(BP_MissingInfo.check(BP_MissingInfo.load(basicId))), ' | ');
    }

    private static String clientLines(Id basicId) {
        List<String> out = new List<String>();
        for (BP_MissingInfo.Item i : BP_MissingInfo.clientItems(BP_MissingInfo.check(BP_MissingInfo.load(basicId)))) out.add(i.clientText);
        return String.join(out, ' | ');
    }

    @IsTest
    static void namesWhatIsMissingInPlainWords() {
        Basic__c b = claim(new Map<String, Object>{ 'Claimant_hasNino__c' => true, 'Claimant_nino__c' => null, 'Eircode__c' => null, 'Bank_BIC__c' => null });
        String client = clientLines(b.Id);
        System.assert(client.contains('UK National Insurance number'), client);
        System.assert(client.contains('we will trace it'), client);
        System.assert(client.contains('Eircode of your home address'), client);
        System.assert(client.contains('BIC (SWIFT) code'), client);
        System.assert(!client.contains('Bank:'), 'no field headings: ' + client);
        System.assert(agentLines(b.Id).contains('NINO'));
    }

    @IsTest
    static void widowIsNeverAskedAboutHerPartner() {
        Basic__c b = claim(new Map<String, Object>{
            'Claimant_title__c' => 'Mrs', 'Claimant_marital_Status__c' => 'Widowed', 'Claimant_date_Of_Bereavement__c' => null,
            'Partner_Title__c' => null, 'Partner_Surname__c' => null, 'Partner_DOB__c' => null, 'Partner_Address1__c' => null
        });
        String client = clientLines(b.Id);
        System.assert(client.contains('late husband'), client);
        System.assert(client.contains('The date your husband passed away'), client);
        System.assert(!client.toLowerCase().contains('partner'), client);
        System.assert(client.contains('The last home address of your late husband'), client);
    }

    @IsTest
    static void australianBankAsksForBsbNotIban() {
        Basic__c b = claim(new Map<String, Object>{ 'Bank_Country__c' => 'Australia', 'Bank_Country_Code__c' => 'AU', 'Bank_Sort_Code__c' => null, 'Bank_IBAN__c' => null, 'Bank_BIC__c' => null });
        String client = clientLines(b.Id);
        System.assert(client.contains('BSB'), client);
        System.assert(!client.contains('IBAN'), client);
    }

    @IsTest
    static void ibanCountryIsNotAskedForSortCode() {
        Basic__c b = claim(new Map<String, Object>{ 'Bank_Country__c' => 'Ireland', 'Bank_Country_Code__c' => 'IE', 'Bank_Sort_Code__c' => null, 'Bank_Account__c' => null, 'Bank_BIC__c' => 'AIBKIE2D' });
        String agent = agentLines(b.Id);
        System.assert(!agent.contains('BSB') && !agent.contains('account number'), agent);
    }

    @IsTest
    static void recordsAreNamedAndSpouseRowsGoUnderTheSpouse() {
        Basic__c b = claim(new Map<String, Object>{ 'Claimant_title__c' => 'Mr', 'Claimant_marital_Status__c' => 'Married', 'Claimant_date_Of_Marriage__c' => Date.newInstance(1970, 6, 1),
            'Partner_Title__c' => 'Mrs', 'Partner_Surname__c' => 'Snow', 'Partner_DOB__c' => Date.newInstance(1950, 1, 1), 'Partner_City__c' => 'Cork', 'Partner_Postcode__c' => 'T12', 'Partner_Country__c' => 'Ireland' });
        insert new Claimant_Country_lived__c(Basic__c = b.Id, Name = 'Ireland', Country_Type__c = 'IE', From_date__c = Date.newInstance(1990, 1, 1), Is_Live_Here_Now__c = true);
        insert new Claimant_Country_lived__c(Basic__c = b.Id, Name = 'Australia', Country_Type__c = 'AU', Is_Partner__c = true, Social_Security_Number__c = '123');
        insert new Claimant_Company__c(Basic__c = b.Id, Name = 'Ford Motor Company', City__c = 'Dagenham', Postcode__c = 'RM9', Country__c = 'UK', Address1__c = 'x', From_Date__c = Date.newInstance(1965, 1, 1));
        String client = clientLines(b.Id);
        System.assert(client.contains('Ireland: your PPS number'), client);
        System.assert(client.contains('Australia: the years she lived there'), client);
        System.assert(client.contains('Ford Motor Company: the year you left'), client);
        List<BP_MissingInfo.GroupView> groups = BP_MissingInfo.grouped(BP_MissingInfo.load(b.Id), BP_MissingInfo.check(BP_MissingInfo.load(b.Id)));
        Boolean spouseGroup = false;
        for (BP_MissingInfo.GroupView g : groups) spouseGroup = spouseGroup || g.label == 'Your wife';
        System.assert(spouseGroup, 'the spouse group is called "Your wife"');
    }

    @IsTest
    static void pensionStartDateIsForTheAgentOnly() {
        Basic__c b = claim(new Map<String, Object>{ 'Pension_Claiming_from_Today__c' => false, 'Pension_Start_Date__c' => null });
        System.assert(agentLines(b.Id).contains('Pension start date'));
        System.assert(!clientLines(b.Id).contains('Pension'), clientLines(b.Id));
    }

    @IsTest
    static void noHelperIsOptionalAndDoesNotBlock() {
        Basic__c b = claim(new Map<String, Object>{ 'Friend_First_Name__c' => null, 'Friend_Last_Name__c' => null, 'Friend_Phone__c' => null, 'Friend_Email__c' => null, 'Relationship__c' => null });
        System.assert(!agentLines(b.Id).contains('Helper'), agentLines(b.Id));
        System.assert(clientLines(b.Id).contains('If no one helps you, just tell us'));
    }

    // Call of 11/11/2026: no helper given starts unticked in the email; whatever the agent leaves unticked is not asked.
    @IsTest
    static void noHelperStartsUntickedAndUntickedItemsStayOut() {
        Basic__c b = claim(new Map<String, Object>{ 'Bank_BIC__c' => null,
            'Friend_First_Name__c' => null, 'Friend_Last_Name__c' => null, 'Friend_Phone__c' => null, 'Friend_Email__c' => null, 'Relationship__c' => null });
        BP_MissingInfo.Item none, bank;
        List<String> everything = new List<String>();
        for (BP_MissingInfo.Item i : BP_MissingInfo.clientItems(BP_MissingInfo.check(BP_MissingInfo.load(b.Id)))) {
            everything.add(i.agentText);
            if (i.agentText == 'Helper: none given (optional)') none = i;
            if (i.agentText.startsWith('Bank')) bank = i;
        }
        System.assertEquals(false, none.askByDefault, 'no helper: unticked');
        System.assertEquals(true, bank.askByDefault, 'the rest: ticked');

        System.assert(((String) BP_MissingInfo.previewLeavingOut(b.Id, null, null).get('html')).contains('If no one helps you'), 'null leaves nothing out');
        Map<String, Object> p = BP_MissingInfo.previewLeavingOut(b.Id, null, new List<String>{ none.agentText });
        System.assert(!((String) p.get('html')).contains('If no one helps you'), p.get('html'));
        System.assert(!((String) p.get('whatsapp')).contains('If no one helps you'), p.get('whatsapp'));
        System.assert(((String) p.get('html')).contains('BIC (SWIFT) code'), p.get('html'));
        System.assertEquals(everything.size() - 1, (Integer) p.get('count'));

        Boolean threw = false;
        try { BP_MissingInfo.sendLeavingOut(b.Id, null, everything); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'nothing ticked: refused');
        Test.startTest();
        String result = BP_MissingInfo.sendLeavingOut(b.Id, null, new List<String>{ none.agentText });
        Test.stopTest();
        System.assert(result.startsWith('Sent to'), result);
    }

    @IsTest
    static void noHelperIsTickedWhenTheClientWantsOne() {
        Basic__c b = claim(new Map<String, Object>{ 'Wants_Helper__c' => 'Yes',
            'Friend_First_Name__c' => null, 'Friend_Last_Name__c' => null, 'Friend_Phone__c' => null, 'Friend_Email__c' => null, 'Relationship__c' => null });
        Integer helpers = 0;
        for (BP_MissingInfo.Item i : BP_MissingInfo.check(BP_MissingInfo.load(b.Id))) {
            if (i.agentText.startsWith('Helper')) {
                helpers++;
                System.assertEquals(true, i.askByDefault, i.agentText);
            }
        }
        System.assertEquals(1, helpers);
    }

    @IsTest
    static void childrenAndUkDatesAreAsked() {
        Basic__c b = claim(new Map<String, Object>{ 'Claimant_Minded_Kids__c' => true, 'Claimant_ever_Lived_UK__c' => true, 'Claimant_lived_UK_From__c' => null, 'Claimant_lived_UK_to__c' => null,
            'Claimant_Ever_Worked_UK__c' => true, 'Claimant_worked_UK_From__c' => Date.newInstance(1960, 1, 1), 'Claimant_worked_UK_To__c' => null });
        insert new Claimant_Child__c(Basic__c = b.Id, Name = 'Mary', Dob__c = null);
        String client = clientLines(b.Id);
        System.assert(client.contains('Mary: date of birth and the years you stayed at home'), client);
        System.assert(client.contains('the year you arrived and the year you left'), client);
        System.assert(client.contains('The year you stopped working in the UK'), client);
    }

    @IsTest
    static void refreshKeepsTheFieldCurrentAndPortalUtilsDelegates() {
        Basic__c b = claim(new Map<String, Object>{ 'Status__c' => 'Validation Call', 'Bank_BIC__c' => null, 'Missing_Info__c' => 'stale' });
        Map<String, Object> view = BP_MissingInfo.refresh(b.Id, false);
        System.assert(((Integer) view.get('blocking')) > 0);
        String stored = [SELECT Missing_Info__c FROM Basic__c WHERE Id = :b.Id].Missing_Info__c;
        System.assert(stored.contains('Bank: BIC'), stored);
        System.assertEquals(BP_MissingInfo.agentTexts(BP_MissingInfo.check(BP_MissingInfo.load(b.Id))), BP_PortalUtils.getMissing(b.Id));
        System.assertEquals(BP_PortalUtils.getMissing(b.Id), BP_PortalUtils.generateValidationEmail(b.Id));
        BP_PortalUtils.setMissing(b.Id);
        System.assertEquals(stored, [SELECT Missing_Info__c FROM Basic__c WHERE Id = :b.Id].Missing_Info__c);
    }

    @IsTest
    static void completeFormIsMarkedComplete() {
        System.assertEquals(BP_MissingInfo.COMPLETE, BP_MissingInfo.fieldValue(new List<BP_MissingInfo.Item>()));
        System.assertEquals('a, b and c', BP_MissingInfo.joinParts(new List<String>{ 'a', 'b', 'c' }));
    }

    @IsTest
    static void emailIsPreviewedSentAndLogged() {
        Basic__c b = claim(new Map<String, Object>{ 'Bank_BIC__c' => null, 'Claimant_hasNino__c' => true, 'Claimant_nino__c' => null });
        Map<String, Object> p = BP_MissingInfo.preview(b.Id, 'Following our call today,');
        String html = (String) p.get('html');
        System.assert(((String) p.get('subject')).startsWith([SELECT Name FROM Basic__c WHERE Id = :b.Id].Name), p.get('subject'));
        System.assert(html.contains('Following our call today,'));
        System.assert(html.contains('Your bank account'));
        System.assert(!html.contains('URGENT'));
        Test.startTest();
        String result = BP_MissingInfo.sendEmail(b.Id, null);
        Test.stopTest();
        System.assert(result.startsWith('Sent to'), result);
    }

    @IsTest
    static void helperIsAlwaysCopied() {
        Basic__c b = claim(new Map<String, Object>{ 'Bank_BIC__c' => null, 'Friend_Email__c' => 'ann@example.com', 'CC_Helper_on_All_Comms__c' => false });
        System.assertEquals('ann@example.com', BP_MissingInfo.preview(b.Id, null).get('cc'), 'helper in copy even with the box unticked');
        b.Friend_Email__c = 'John.Snow@example.com';
        update b;
        System.assertEquals(null, BP_MissingInfo.preview(b.Id, null).get('cc'), 'same address as the client: no copy');
    }

    @IsTest
    static void emailWithoutContactIsLoggedOnTheClaim() {
        Basic__c b = claim(new Map<String, Object>{ 'Bank_BIC__c' => null });
        b.Contact__c = null;
        update b;
        Test.startTest();
        BP_MissingInfo.sendEmail(b.Id, null);
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM EmailMessage WHERE RelatedToId = :b.Id]);
    }

    // ------------------------------------------------------------------ painel xpMissingInfo (mesmas chaves do Sales)

    @IsTest
    static void refreshGivesTheSalesKeysWithAgentItemsLast() {
        Basic__c b = claim(new Map<String, Object>{ 'Bank_BIC__c' => null, 'Pension_Claiming_from_Today__c' => false, 'Pension_Start_Date__c' => null,
            'Friend_First_Name__c' => null, 'Friend_Last_Name__c' => null, 'Friend_Phone__c' => null, 'Friend_Email__c' => null, 'Relationship__c' => null,
            'Step__c' => 'About Partner' });
        Map<String, Object> view = BP_MissingInfo.refresh(b.Id, false);
        Integer missing = (Integer) view.get('missing');
        System.assert(missing > 0, view);
        System.assertEquals(1, (Integer) view.get('optional'), 'no helper is the optional item');
        System.assertEquals(1, (Integer) view.get('checks'), 'the pension start date is for the agent');
        System.assertEquals(missing + 1, (Integer) view.get('clientCount'));
        System.assertEquals(missing + 1, (Integer) view.get('blocking'), 'blocking counts the agent item too, as before');
        System.assertEquals(true, view.get('inStage'));
        System.assertEquals('The client is on step 4 of 9, "Have you ever claimed".', view.get('step'));
        System.assertEquals(null, view.get('lastAsked'));
        System.assertEquals([SELECT Name FROM Basic__c WHERE Id = :b.Id].Name, view.get('name'));
        List<BP_MissingInfo.GroupView> groups = (List<BP_MissingInfo.GroupView>) view.get('groups');
        BP_MissingInfo.GroupView lastGroup = groups[groups.size() - 1];
        System.assertEquals('For you to check', lastGroup.label);
        System.assert(lastGroup.items[0].agentText.startsWith('Pension start date'), lastGroup.items[0].agentText);
        for (BP_MissingInfo.GroupView g : groups) {
            for (BP_MissingInfo.Item i : g.items) System.assert(g.label == 'For you to check' || i.clientText != null, 'agent items only in the last group');
        }
    }

    @IsTest
    static void stepLineFollowsThePortalPages() {
        System.assertEquals('The short form has not been done yet.', BP_MissingInfo.stepLine(new Basic__c(Status__c = 'Form In Progress')));
        System.assertEquals('The client has not opened the form yet.', BP_MissingInfo.stepLine(new Basic__c(Status__c = 'Form In Progress', Is_envelope_created__c = true)));
        System.assertEquals('The client is on step 1 of 9, "Helper".',
            BP_MissingInfo.stepLine(new Basic__c(Status__c = 'Form In Progress', Step__c = 'Friend / Family for Communication')));
        System.assertEquals('The client is on step 5 of 9, "Has your partner ever claimed" (agent form: step 8).',
            BP_MissingInfo.stepLine(new Basic__c(Status__c = 'Form In Progress', Step__c = 'Have you (Claimant) Ever Claimed', Agent_Form_Step__c = 'Benefits')));
        System.assertEquals('The client is on step 9 of 9, "Summary".',
            BP_MissingInfo.stepLine(new Basic__c(Status__c = 'Validation Call', Step__c = 'Bank Details', Agent_Form_Step__c = 'About the Claimant')));
        System.assertEquals('The client is on step 8 of 9, "Bank details" (agent form: sent).',
            BP_MissingInfo.stepLine(new Basic__c(Status__c = 'Validation Call', Step__c = 'Benefits', Agent_Form_Step__c = 'Review')));
        System.assertEquals('The client has sent the form.', BP_MissingInfo.stepLine(new Basic__c(Status__c = 'Validation Call', Step__c = 'Review')));
        System.assertEquals(null, BP_MissingInfo.stepLine(new Basic__c(Status__c = 'Agent Check', Step__c = 'About Partner')), 'only while the form is being filled');
    }

    @IsTest
    static void whatsAppIsTheSameRequestShortAndSigned() {
        Basic__c b = claim(new Map<String, Object>{ 'Bank_BIC__c' => null, 'First_Name__c' => 'John Paul' });
        String name = [SELECT Name FROM Basic__c WHERE Id = :b.Id].Name;
        String wa = (String) BP_MissingInfo.preview(b.Id, 'Following our call today,').get('whatsapp');
        System.assert(wa.startsWith('Hi John, Following our call today, Thank you for filling in your claim form.'), wa);
        System.assert(wa.contains('*Your bank account*'), wa);
        System.assert(wa.contains('BIC (SWIFT) code'), wa);
        System.assert(!wa.contains('Pension start date') && !wa.contains(BP_MissingInfo.CLIENTS_EMAIL), 'no agent items, no footer: ' + wa);
        System.assert(wa.endsWith(', XtraPension (' + name + ')'), wa);
    }

    @IsTest
    static void sendIsRefusedOutsideTheFormStages() {
        Basic__c b = claim(new Map<String, Object>{ 'Bank_BIC__c' => null, 'Status__c' => 'Closed' });
        Boolean threw = false;
        try { BP_MissingInfo.sendEmail(b.Id, null); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'past QC Approved: refused');
        Map<String, Object> view = BP_MissingInfo.refresh(b.Id, false);
        System.assertEquals(false, view.get('inStage'));
        System.assertEquals(null, view.get('step'));
        System.assertEquals(0, [SELECT COUNT() FROM EmailMessage WHERE RelatedToId = :b.Id]);
    }

    @IsTest
    static void lastAskedShowsTheNewestRequest() {
        Basic__c b = claim(new Map<String, Object>{ 'Bank_BIC__c' => null, 'Status__c' => 'QC Approved' });
        b.Contact__c = null;
        update b;
        Test.startTest();
        BP_MissingInfo.sendEmail(b.Id, null);
        Test.stopTest();
        String lastAsked = (String) BP_MissingInfo.refresh(b.Id, false).get('lastAsked');
        System.assert(lastAsked != null && lastAsked.startsWith('Last asked '), lastAsked);
    }

    @IsTest
    static void nothingToAskIsRefused() {
        Basic__c b = claim(new Map<String, Object>{ 'Bank_BIC__c' => 'AIBKIE2D', 'Friend_First_Name__c' => 'Ann', 'Friend_Last_Name__c' => 'Snow', 'Friend_Email__c' => 'ann@example.com',
            'Claimant_dob__c' => Date.newInstance(1945, 1, 1), 'Bank_Country_Code__c' => 'IE', 'Owns_This_Account__c' => 'Claimant' });
        insert new Claimant_Country_lived__c(Basic__c = b.Id, Name = 'Ireland', Country_Type__c = 'IE', From_date__c = Date.newInstance(1990, 1, 1), Is_Live_Here_Now__c = true, Social_Security_Number__c = '1234567T');
        if (BP_MissingInfo.clientItems(BP_MissingInfo.check(BP_MissingInfo.load(b.Id))).isEmpty()) {
            Boolean threw = false;
            try { BP_MissingInfo.sendEmail(b.Id, null); } catch (AuraHandledException e) { threw = true; }
            System.assert(threw, 'nothing to ask: refused');
        }
    }

    // ------------------------------------------------------------------ call of 11/11/2026 17h13 (docs/claims-call-1111b/CONTRACT.md)

    @IsTest
    static void remarriedIsAskedBothMarriagesAndTheCurrentSpouse() {
        Basic__c b = claim(new Map<String, Object>{
            'Claimant_title__c' => 'Mrs', 'Claimant_marital_Status__c' => 'Remarried', 'Partner_Title__c' => 'Mr',
            'Claimant_date_Of_Marriage__c' => null, 'Previous_Marriage_Ended__c' => null, 'Date_Of_Remarriage__c' => null,
            'Partner_Address1__c' => null
        });
        String client = clientLines(b.Id);
        System.assert(client.contains('The date you married your first husband'), client);
        System.assert(client.contains('Whether your first marriage ended in divorce or because your first husband passed away'), client);
        System.assert(client.contains('The date you married again'), client);
        System.assert(client.contains('of your current husband'), client);
        System.assert(client.contains('former husband'), 'the section 3 spouse is the former one: ' + client);

        b.Previous_Marriage_Ended__c = 'Divorced';
        b.Claimant_date_Of_Divorce__c = null;
        update b;
        System.assert(clientLines(b.Id).contains('The date of your divorce from your first husband'), clientLines(b.Id));

        b.Previous_Marriage_Ended__c = 'Widowed';
        b.Claimant_date_Of_Bereavement__c = null;
        b.Claimant_date_Of_Marriage__c = Date.newInstance(1969, 4, 19);
        b.Date_Of_Remarriage__c = Date.newInstance(2016, 5, 1);
        b.Current_Spouse_First_Name__c = 'John';
        b.Current_Spouse_Last_Name__c = 'O\'Brien';
        b.Current_Spouse_DOB__c = Date.newInstance(1944, 1, 2);
        update b;
        client = clientLines(b.Id);
        System.assert(client.contains('The date your first husband passed away'), client);
        System.assert(client.contains('late husband'), client);
        System.assert(!client.contains('married again') && !client.contains('current husband'), 'all given: ' + client);
    }

    @IsTest
    static void aForgottenNinoIsNeverAskedAndAnUnknownAddressIsNotChased() {
        Basic__c b = claim(new Map<String, Object>{
            'Claimant_hasNino__c' => true, 'Claimant_nino__c' => null, 'Has_Nino__c' => 'Forgot',
            'Claimant_title__c' => 'Mrs', 'Claimant_marital_Status__c' => 'Divorced', 'Claimant_date_Of_Divorce__c' => Date.newInstance(1985, 6, 1),
            'Partner_Title__c' => 'Mr', 'Partner_Has_Nino__c' => true, 'Partner_Nino__c' => null, 'Partner_Has_Nino_values__c' => 'Forgot',
            'Partner_Address1__c' => null, 'Partner_City__c' => null, 'Partner_Postcode__c' => null, 'Partner_Country__c' => null,
            'Partner_Address_Unknown__c' => true
        });
        String agent = agentLines(b.Id);
        for (String line : agent.split(' \\| ')) {
            System.assert(line != 'NINO' && !line.endsWith(': NINO'), 'forgotten: traced, not asked: ' + agent);
        }
        System.assert(!agent.contains('address ('), 'address not known: nothing to ask: ' + agent);

        b.Partner_Address_Unknown__c = false;
        update b;
        System.assert(clientLines(b.Id).contains('The last address you know for your former husband'), clientLines(b.Id));
    }

    @IsTest
    static void questionsGoInTheEmailEvenWithNothingMissing() {
        Basic__c b = claim(new Map<String, Object>{ 'Bank_BIC__c' => null });
        String questions = '1. When did you leave the UK?\n\n- Did you get married in London?\n• Do you have your divorce certificate?';
        Map<String, Object> p = BP_MissingInfo.previewAsking(b.Id, null, null, questions);
        String html = (String) p.get('html');
        System.assertEquals(3, p.get('questions'));
        System.assert(html.contains('I have to clarify some information on your application. I have some questions:'), html);
        System.assert(html.contains('<li style="margin:0 0 6px 0;">When did you leave the UK?</li>'), html);
        System.assert(html.contains('Do you have your divorce certificate?'), html);
        System.assert(html.contains('We also need a few more details from you:'), html);
        System.assert(((String) p.get('whatsapp')).contains('- Did you get married in London?'), (String) p.get('whatsapp'));
        System.assert(!((String) BP_MissingInfo.preview(b.Id, null).get('html')).contains('clarify'), 'no questions: the email as before');

        // every item unticked: the questions alone still go
        List<String> leaveOut = new List<String>();
        for (BP_MissingInfo.Item i : BP_MissingInfo.clientItems(BP_MissingInfo.check(BP_MissingInfo.load(b.Id)))) leaveOut.add(i.agentText);
        String onlyQuestions = (String) BP_MissingInfo.previewAsking(b.Id, null, leaveOut, questions).get('html');
        System.assert(!onlyQuestions.contains('We also need'), onlyQuestions);
        Boolean refused = false;
        try { BP_MissingInfo.sendAsking(b.Id, null, leaveOut, '  \n '); } catch (AuraHandledException e) { refused = true; }
        System.assert(refused, 'nothing ticked and no question: refused');
        Test.startTest();
        String result = BP_MissingInfo.sendAsking(b.Id, null, leaveOut, questions);
        Test.stopTest();
        System.assert(result.startsWith('Sent to'), result);
    }
}