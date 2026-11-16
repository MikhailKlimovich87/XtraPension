@IsTest
private class XpMissingInfoTest {

    @TestSetup
    static void makeData() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Id contactId = [SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1].Id;
        TestDataFactory.createApplication(contactId, true);
        TestDataFactory.createXtraPensionDataCustomSetting(true);
    }

    /** The test application with a finished form, plus the given changes. */
    private static Application__c app(Map<String, Object> fields) {
        Application__c a = [SELECT Id FROM Application__c LIMIT 1];
        Map<String, Object> base = new Map<String, Object>{
            'Step__c' => 'Documents', 'Salutation__c' => 'Mr', 'Date_Of_Birth__c' => Date.newInstance(1960, 5, 1),
            'National_Insurance_Number__c' => 'AB123456C', 'Are_You_Single__c' => true,
            'Current_Address_Abroad__Street__s' => '1 Main Street', 'Current_Address_Abroad__City__s' => 'Galway',
            'Current_Address_Abroad__PostalCode__s' => 'H91 E2K3', 'Current_Address_Abroad__CountryCode__s' => 'IE',
            'Last_UK_Home_Address__Street__s' => '2 High Street', 'Last_UK_Home_Address__City__s' => 'London', 'Last_UK_Home_Address__PostalCode__s' => 'E1 6AN',
            'Date_Of_Leaving_Last_UK__c' => Date.newInstance(2008, 6, 30), 'Years_Of_Work_In_The_UK__c' => 12,
            'Type_Of_Employment__c' => 'Employed', 'Last_UK_Employer_Name__c' => 'Ford Motor Company',
            'Last_UK_Employer_Start_Date__c' => Date.newInstance(2000, 1, 1), 'Last_UK_Employer_End_Date__c' => Date.newInstance(2008, 6, 30),
            'Last_UK_Employer_Address__Street__s' => 'Kent Avenue', 'Last_UK_Employer_Address__City__s' => 'Dagenham', 'Last_UK_Employer_Address__PostalCode__s' => 'RM9 6SA',
            'Date_of_Last_Pay_Contributions__c' => Date.newInstance(2008, 6, 30), 'Pay_Voluntary_Contribution_At__c' => 'Class 2',
            'Abroad_Employer_Name1__c' => 'Galway Clinic', 'SelfEmployment_Employment_Abroad__c' => 'Employed'
        };
        base.putAll(fields);
        for (String f : base.keySet()) a.put(f, base.get(f));
        update a;
        return a;
    }

    private static Employer__c job(Id appId, String kind, String name, Date startDate, Date endDate) {
        return new Employer__c(Application__c = appId, Type__c = 'Work After UK', Type_Of_After_UK_Employment__c = kind, Employer_Name__c = name,
            Start_Date__c = startDate, End_Date__c = endDate, Current_Work__c = endDate == null ? 'Yes' : 'No',
            Employers_Address__Street__s = name == null ? null : 'Doughiska Road', Employers_Address__CountryCode__s = name == null ? null : 'IE');
    }

    private static void upload(Id appId) {
        insert new ContentVersion(Title = 'John_Snow_A00001_UPLOAD_ForSignature', PathOnClient = 'u.pdf', VersionData = Blob.valueOf('pdf'), FirstPublishLocationId = appId);
    }

    private static List<XpMissingInfo.Item> items(Id appId) {
        return XpMissingInfo.check(XpMissingInfo.load(appId), XpMissingInfo.fileTitles(appId));
    }

    private static String agentLines(Id appId) {
        List<String> out = new List<String>();
        for (XpMissingInfo.Item i : items(appId)) out.add(i.agentText);
        return String.join(out, ' | ');
    }

    private static String clientLines(Id appId) {
        List<String> out = new List<String>();
        for (XpMissingInfo.Item i : XpMissingInfo.clientItems(items(appId))) out.add(i.clientText);
        return String.join(out, ' | ');
    }

    @IsTest
    static void finishedApplicationHasNothingMissing() {
        Application__c a = app(new Map<String, Object>());
        insert job(a.Id, 'Employed', 'Galway Clinic', Date.newInstance(2008, 9, 1), null);
        upload(a.Id);
        System.assertEquals('', agentLines(a.Id));
        Map<String, Object> view = XpMissingInfo.refresh(a.Id);
        System.assertEquals(0, (Integer) view.get('missing'));
        System.assertEquals(true, view.get('inStage'));
    }

    @IsTest
    static void asksInPlainWordsAndNamesTheEmployer() {
        Application__c a = app(new Map<String, Object>{
            'National_Insurance_Number__c' => null, 'Salutation__c' => null, 'Last_UK_Employer_Address__Street__s' => null,
            'Last_UK_Employer_Address__PostalCode__s' => null, 'Last_UK_Employer_End_Date__c' => null
        });
        String client = clientLines(a.Id);
        System.assert(client.contains('UK National Insurance number'), client);
        System.assert(client.contains('https://xpen.uk/5ways'), client);
        System.assert(client.contains('Your title (Mr, Mrs, Ms, Miss or Dr)'), client);
        System.assert(client.contains('Ford Motor Company: the address where you worked'), client);
        System.assert(client.contains('Ford Motor Company: roughly when you left'), client);
        System.assert(client.contains('What you have done since you left the UK'), 'no work after the UK: ' + client);
        System.assert(client.contains('PRSI contribution statement'), 'Irish Class 2 without an UPLOAD file: ' + client);
        System.assert(!client.contains('CF83'), 'no form references for the client: ' + client);
    }

    @IsTest
    static void evidenceDependsOnCountryAndClass() {
        Application__c a = app(new Map<String, Object>{ 'Current_Address_Abroad__CountryCode__s' => 'AU', 'Current_Address_Abroad__PostalCode__s' => '2000' });
        System.assert(clientLines(a.Id).contains('A document for each year from 2019 to 2024'), clientLines(a.Id));
        a = app(new Map<String, Object>{ 'Current_Address_Abroad__CountryCode__s' => 'ZA', 'Current_Address_Abroad__PostalCode__s' => '8001' });
        System.assert(clientLines(a.Id).contains('statement of your social security contributions'), clientLines(a.Id));
        a = app(new Map<String, Object>{ 'Pay_Voluntary_Contribution_At__c' => 'Class 3' });
        System.assert(!agentLines(a.Id).contains('evidence'), 'Class 3 needs no evidence: ' + agentLines(a.Id));
        a = app(new Map<String, Object>{ 'Pay_Voluntary_Contribution_At__c' => 'Class 2' });
        upload(a.Id);
        System.assert(!agentLines(a.Id).contains('evidence'), 'the UPLOAD file is the evidence: ' + agentLines(a.Id));
    }

    @IsTest
    static void findsGapsAndUnfinishedRows() {
        Application__c a = app(new Map<String, Object>());
        insert new List<Employer__c>{
            job(a.Id, 'Employed', 'Galway Clinic', Date.newInstance(2008, 9, 1), Date.newInstance(2018, 12, 31)),
            job(a.Id, 'Career Break', null, Date.newInstance(2021, 3, 1), null),
            new Employer__c(Application__c = a.Id, Type__c = 'Work After UK', Type_Of_After_UK_Employment__c = 'Employed', Start_Date__c = Date.newInstance(2022, 1, 1), Current_Work__c = 'No')
        };
        String client = clientLines(a.Id);
        System.assert(client.contains('What you were doing between January 2019 and March 2021'), client);
        System.assert(client.contains('The name and address of the employer you worked for from January 2022'), client);
        System.assert(client.contains('Job from January 2022: when it ended'), client);
        System.assert(!client.contains('Career break from March 2021: when it ended'), 'current rows need no end: ' + client);
    }

    @IsTest
    static void agentChecksNeverReachTheClient() {
        Application__c a = app(new Map<String, Object>{
            'National_Insurance_Number__c' => 'AS1234578A', 'Current_Address_Abroad__PostalCode__s' => 'GALWAY',
            'Abroad_Employer_Name1__c' => null, 'Date_of_Last_Pay_Contributions__c' => null
        });
        insert job(a.Id, 'Employed', 'Galway Clinic', Date.newInstance(2007, 1, 1), null);
        String agent = agentLines(a.Id);
        System.assert(agent.contains('NINO looks wrong'), agent);
        System.assert(agent.contains('Eircode looks wrong'), agent);
        System.assert(agent.contains('CF83 Q18'), agent);
        System.assert(agent.contains('CF83 Q14'), agent);
        System.assert(agent.contains('before the date left the UK'), agent);
        String client = clientLines(a.Id);
        System.assert(!client.contains('NINO') && !client.contains('Eircode looks'), client);

        a = app(new Map<String, Object>{ 'Pay_Voluntary_Contribution_At__c' => 'Class 2' });
        delete [SELECT Id FROM Employer__c WHERE Application__c = :a.Id];
        insert job(a.Id, 'Retired', null, Date.newInstance(2008, 9, 1), null);
        System.assert(agentLines(a.Id).contains('check whether it should be Class 3'), agentLines(a.Id));
        a = app(new Map<String, Object>{ 'Pay_Voluntary_Contribution_At__c' => 'Class 3', 'Freeform_RichText_Line1__c' => '<p>eligibility to pay Class 2 contributions</p>' });
        System.assert(agentLines(a.Id).contains('Cover letter still asks HMRC about Class 2'), agentLines(a.Id));
    }

    @IsTest
    static void relationshipFollowsTheAnswers() {
        Application__c a = app(new Map<String, Object>{ 'Are_You_Single__c' => false, 'Date_Of_Marriage_Or_Civil_Partnership__c' => null, 'Did_You_Change_Name__c' => true });
        String client = clientLines(a.Id);
        System.assert(client.contains('The date of your marriage'), client);
        System.assert(client.contains('Your former name'), client);
        a = app(new Map<String, Object>{ 'Step__c' => 'Personal Details', 'Are_You_Single__c' => false, 'Did_You_Change_Name__c' => false });
        System.assert(clientLines(a.Id).contains('Whether you are single, married, divorced or widowed'), clientLines(a.Id));
        a = app(new Map<String, Object>{ 'Are_You_Single__c' => false, 'Are_You_Divorced__c' => true, 'Date_Of_Marriage_Or_Civil_Partnership__c' => Date.newInstance(1985, 1, 1), 'Divorce_Date__c' => null });
        System.assert(clientLines(a.Id).contains('the date your husband or wife passed away'), clientLines(a.Id));
    }

    @IsTest
    static void unknownPostcodesAreAskedSoftly() {
        Application__c a = app(new Map<String, Object>{ 'Last_UK_Employer_Address__PostalCode__s' => null, 'Last_UK_Home_Address__PostalCode__s' => null, 'Previous_UK_Address_1__PostalCode__s' => null });
        insert job(a.Id, 'Employed', 'Galway Clinic', Date.newInstance(2008, 9, 1), null);
        upload(a.Id);
        Map<String, Object> view = XpMissingInfo.refresh(a.Id);
        System.assertEquals(0, (Integer) view.get('missing'), agentLines(a.Id));
        System.assertEquals(2, (Integer) view.get('optional'), agentLines(a.Id));
    }

    @IsTest
    static void previewAndSendLogTheEmail() {
        Application__c a = app(new Map<String, Object>{ 'National_Insurance_Number__c' => null, 'First_Name__c' => 'John Paul' });
        Map<String, Object> p = XpMissingInfo.preview(a.Id, 'Following our call today,');
        String html = (String) p.get('html');
        System.assert(((String) p.get('subject')).endsWith(XpMissingInfo.SUBJECT_MARK), p.get('subject'));
        System.assert(html.contains('Hi John,'), 'first given name only');
        System.assert(html.contains('Following our call today,'));
        System.assert(html.contains('<a href="https://xpen.uk/5ways"'), html);
        System.assert(!html.contains('go.xtrapension.com'), 'never the form link');
        System.assert(((String) p.get('whatsapp')).contains('*About you*'), p.get('whatsapp'));
        Test.startTest();
        String result = XpMissingInfo.sendEmail(a.Id, null);
        Test.stopTest();
        System.assert(result.startsWith('Sent to'), result);
    }

    // Call of 11/11/2026: every Sales item starts ticked; one the agent unticks is not asked.
    @IsTest
    static void untickedItemsStayOutOfTheEmail() {
        Application__c a = app(new Map<String, Object>{ 'National_Insurance_Number__c' => null, 'Salutation__c' => null });
        List<String> everything = new List<String>();
        XpMissingInfo.Item nino;
        for (XpMissingInfo.Item i : XpMissingInfo.clientItems(XpMissingInfo.check(XpMissingInfo.load(a.Id), XpMissingInfo.fileTitles(a.Id)))) {
            System.assertEquals(true, i.askByDefault, i.agentText);
            everything.add(i.agentText);
            if (i.agentText.contains('NINO') || i.agentText.contains('National Insurance')) nino = i;
        }
        System.assert(nino != null && everything.size() > 1, everything);
        Map<String, Object> all = XpMissingInfo.previewLeavingOut(a.Id, null, null);
        Map<String, Object> p = XpMissingInfo.previewLeavingOut(a.Id, null, new List<String>{ nino.agentText });
        System.assertEquals((Integer) all.get('count') - 1, (Integer) p.get('count'));
        System.assert(((String) all.get('html')).contains('old UK payslips'), all.get('html'));
        System.assert(!((String) p.get('html')).contains('old UK payslips'), p.get('html'));
        System.assert(!((String) p.get('whatsapp')).contains('old UK payslips'), p.get('whatsapp'));
        Boolean threw = false;
        try { XpMissingInfo.sendLeavingOut(a.Id, null, everything); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'nothing ticked: refused');
    }

    @IsTest
    static void emailWithoutContactIsLoggedOnTheApplication() {
        Application__c a = app(new Map<String, Object>{ 'National_Insurance_Number__c' => null, 'Contact__c' => null });
        Test.startTest();
        XpMissingInfo.sendEmail(a.Id, null);
        Test.stopTest();
        // Only this request: the creation flow also logs its Welcome email.
        String mark = '%' + XpMissingInfo.SUBJECT_MARK + '%';
        System.assertEquals(1, [SELECT COUNT() FROM EmailMessage WHERE RelatedToId = :a.Id AND Subject LIKE :mark]);
        System.assert(((String) XpMissingInfo.refresh(a.Id).get('lastAsked')).startsWith('Last asked'), 'the panel shows the request');
    }

    @IsTest
    static void refusesWhenThereIsNothingToAskOrPastQc() {
        Application__c a = app(new Map<String, Object>());
        insert job(a.Id, 'Employed', 'Galway Clinic', Date.newInstance(2008, 9, 1), null);
        upload(a.Id);
        Boolean threw = false;
        try { XpMissingInfo.sendEmail(a.Id, null); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'nothing to ask: refused');
        System.assertEquals('a, b and c', XpMissingInfo.joinParts(new List<String>{ 'a', 'b', 'c' }));
        System.assert(XpMissingInfo.validNino('AB123456C') && !XpMissingInfo.validNino('GB123456A') && !XpMissingInfo.validNino('AB123456E'));
        System.assert(XpMissingInfo.validEircode('D6W 1234') && XpMissingInfo.validEircode('h91e2k3') && !XpMissingInfo.validEircode('Galway'));
    }
}