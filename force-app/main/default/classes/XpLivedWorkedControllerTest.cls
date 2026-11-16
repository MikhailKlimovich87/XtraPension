/**
 * Testes do XpLivedWorkedController (quadro Lived & Worked). Só dados inventados.
 * Roda como um usuário com Claim_Permission_Access: é ele que dá o isFullForm__c, gravado em user mode.
 */
@IsTest
private class XpLivedWorkedControllerTest {

    private static final Date DOB = Date.newInstance(1945, 3, 12);

    @TestSetup
    static void setup() {
        insert new List<Country__c>{
            new Country__c(Name = 'Ireland', Country_Code__c = 'IE'),
            new Country__c(Name = 'Australia', Country_Code__c = 'AU'),
            new Country__c(Name = 'Spain', Country_Code__c = 'ES')
        };
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
            User u = new User(
                LastName = 'Livedworked', Alias = 'lwtest', Email = 'lived.worked@example.com',
                Username = 'lived.worked.' + System.currentTimeMillis() + '@example.com.test',
                ProfileId = p.Id, LocaleSidKey = 'en_GB', LanguageLocaleKey = 'en_US',
                TimeZoneSidKey = 'Europe/London', EmailEncodingKey = 'UTF-8'
            );
            insert u;
            for (PermissionSet ps : [SELECT Id FROM PermissionSet WHERE Name = 'Claim_Permission_Access']) {
                insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
            }
        }
    }

    private static User agent() {
        return [SELECT Id FROM User WHERE Alias = 'lwtest' LIMIT 1];
    }

    private static Basic__c claim(String status, String track) {
        Basic__c b = new Basic__c(
            Status__c = status, Track__c = track, First_Name__c = 'Test', Last_Name__c = 'Person',
            Claimant_title__c = 'Mr', Claimant_dob__c = DOB, Claimant_marital_Status__c = 'Married', Partner_Title__c = 'Mrs',
            Partner_DOB__c = Date.newInstance(1947, 6, 1), Has_Nino__c = 'Forgot', Is_envelope_created__c = true,
            Claimant_ever_Lived_UK__c = true, Claimant_lived_UK_From__c = Date.newInstance(1950, 1, 1), Claimant_lived_UK_to__c = Date.newInstance(1979, 9, 30),
            Claimant_Ever_Worked_UK__c = true, Claimant_worked_UK_From__c = Date.newInstance(1961, 9, 1), Claimant_worked_UK_To__c = Date.newInstance(1979, 9, 30),
            Current_Address_Abroad_Country_Name__c = 'Ireland'
        );
        insert b;
        return b;
    }

    private static String texts(List<XpLivedWorkedController.Check> checks) {
        List<String> out = new List<String>();
        for (XpLivedWorkedController.Check c : checks) out.add(c.text);
        return String.join(out, ' | ');
    }

    @IsTest
    static void readsTheListsAndFindsWhatDwpWouldQuery() {
        System.runAs(agent()) {
            Basic__c b = claim('Form In Progress', 'A');
            insert new List<Claimant_Company__c>{
                new Claimant_Company__c(Basic__c = b.Id, Name = 'United Kingdom', Is_Addresses__c = true, Address1__c = '1 Test Street', City__c = 'Testford',
                    Postcode__c = 'TE1 1ST', Country__c = 'United Kingdom', From_Date__c = Date.newInstance(1974, 9, 1), To_Date__c = Date.newInstance(1977, 8, 31)),
                new Claimant_Company__c(Basic__c = b.Id, Name = 'Reversed Works', From_Date__c = Date.newInstance(1970, 1, 1), To_Date__c = Date.newInstance(1965, 1, 1)),
                new Claimant_Company__c(Basic__c = b.Id, Name = 'Child Labour Ltd', From_Date__c = Date.newInstance(1955, 1, 1), To_Date__c = Date.newInstance(1956, 1, 1)),
                new Claimant_Company__c(Basic__c = b.Id, Name = 'Late Mill', From_Date__c = Date.newInstance(1990, 1, 1), To_Date__c = Date.newInstance(1995, 1, 1)),
                new Claimant_Company__c(Basic__c = b.Id, Name = 'Her Shop', Is_Partner__c = true, From_Date__c = Date.newInstance(1940, 1, 1), To_Date__c = Date.newInstance(1960, 1, 1)),
                new Claimant_Company__c(Basic__c = b.Id, Name = 'United Kingdom', Is_Partner__c = true, Is_Addresses__c = true, City__c = 'Elsewhere',
                    From_Date__c = Date.today().addYears(1))
            };
            insert new List<Claimant_Country_lived__c>{
                new Claimant_Country_lived__c(Basic__c = b.Id, Name = 'Spain', Country_Type__c = 'ES', From_date__c = Date.newInstance(1970, 1, 1),
                    To_Date__c = Date.newInstance(1975, 1, 1), Social_Security_Number__c = 'X1'),
                new Claimant_Country_lived__c(Basic__c = b.Id, Name = 'Australia', Country_Type__c = 'AU', From_date__c = Date.newInstance(1979, 10, 1),
                    To_Date__c = Date.newInstance(1985, 3, 31), Social_Security_Number__c = '123456782'),
                new Claimant_Country_lived__c(Basic__c = b.Id, Name = 'Ireland', Country_Type__c = 'IE', From_date__c = Date.newInstance(1990, 3, 1),
                    Is_Live_Here_Now__c = true)
            };
            insert new List<Claimant_Child__c>{
                new Claimant_Child__c(Basic__c = b.Id, Name = 'Kid One', Dob__c = Date.newInstance(1982, 5, 4),
                    Minded_From__c = Date.newInstance(1994, 5, 4), Minded_To__c = Date.newInstance(1982, 5, 4)),
                new Claimant_Child__c(Basic__c = b.Id, Name = 'Kid Two', Dob__c = Date.newInstance(1984, 5, 4), Minded_From__c = Date.newInstance(1983, 1, 1)),
                new Claimant_Child__c(Basic__c = b.Id, Name = 'Kid Three', Dob__c = Date.today().addDays(10))
            };

            Test.startTest();
            XpLivedWorkedController.CardData d = XpLivedWorkedController.getData(b.Id);
            Test.stopTest();

            System.assertEquals(6, d.companies.size());
            System.assertEquals(3, d.countries.size());
            System.assertEquals('Spain', d.countries[0].Name, 'countries come by From date');
            System.assertEquals(3, d.children.size());
            System.assertEquals(5, d.checks.size(), 'at most 5 on the card');
            System.assert(d.moreChecks > 0);
            System.assert(d.editable);
            System.assert(d.clientCanEdit);
            System.assert(!d.regenerates);
            System.assertEquals(null, d.lockReason);
            System.assertEquals(null, d.ipcbr1Id);
            System.assertEquals(String.valueOf(Date.today()), d.today);

            String all = texts(XpLivedWorkedController.checks(d.claim, d.companies, d.countries, d.children, Date.today()));
            System.assert(all.contains('Reversed Works: end date before start date'), all);
            System.assert(all.contains('Child Labour Ltd: starts before age 14'), all);
            System.assert(all.contains('Late Mill: outside the UK years'), all);
            System.assert(all.contains('Her Shop (her): date before birth'), all);
            System.assert(all.contains('Elsewhere (her): date in the future'), all);
            System.assert(all.contains('Spain: overlaps the UK years'), all);
            System.assert(all.contains('not accounted for between Australia and Ireland'), all);
            System.assert(all.contains('Ireland: PPS number missing'), all);
            System.assert(all.contains('Kid One: minded dates reversed'), all);
            System.assert(all.contains('Kid Two: minded from before born'), all);
            System.assert(all.contains('Kid Three: date in the future'), all);
            System.assert(!all.contains('1 Test Street'), 'no gap or overlap checks between UK addresses: ' + all);
            System.assert(all.indexOf('end date before start date') < all.indexOf('PPS number missing'), 'most serious first');
        }
    }

    @IsTest
    static void currentCountryAndHoles() {
        Basic__c b = new Basic__c(Claimant_lived_UK_to__c = Date.newInstance(1970, 1, 1), Current_Address_Abroad_Country_Name__c = 'Australia',
            Claimant_dob__c = DOB, Track__c = 'C');
        Date today = Date.newInstance(2026, 11, 4);
        List<Claimant_Company__c> none = new List<Claimant_Company__c>();
        List<Claimant_Child__c> noKids = new List<Claimant_Child__c>();

        // Nenhum "now", buraco depois do UK e nada desde o último país.
        List<Claimant_Country_lived__c> past = new List<Claimant_Country_lived__c>{
            new Claimant_Country_lived__c(Name = 'Ireland', Country_Type__c = 'IE', From_date__c = Date.newInstance(1975, 1, 1),
                To_Date__c = Date.newInstance(1980, 1, 1), Social_Security_Number__c = '1'),
            new Claimant_Country_lived__c(Name = 'Spain', Country_Type__c = 'ES', From_date__c = Date.newInstance(1979, 1, 1))
        };
        String t = texts(XpLivedWorkedController.checks(b, none, past, noKids, today));
        System.assert(t.contains('No country is marked "now"'), t);
        System.assert(t.contains('not accounted for between leaving the UK (01 Jan 1970) and Ireland'), t);
        System.assert(t.contains('Nothing listed since Ireland (01 Jan 1980)'), t);
        System.assert(t.contains('Spain: social security number missing'), t);

        // Dois "now".
        List<Claimant_Country_lived__c> two = new List<Claimant_Country_lived__c>{
            new Claimant_Country_lived__c(Name = 'Ireland', Country_Type__c = 'IE', From_date__c = Date.newInstance(1970, 6, 1), Is_Live_Here_Now__c = true, Social_Security_Number__c = '1'),
            new Claimant_Country_lived__c(Name = 'Australia', Country_Type__c = 'AU', From_date__c = Date.newInstance(1971, 1, 1), Is_Live_Here_Now__c = true, Social_Security_Number__c = '2')
        };
        System.assert(texts(XpLivedWorkedController.checks(b, none, two, noKids, today)).contains('2 countries are marked "now"'));

        // Um "now" que não é o país do endereço; e o país do cônjuge não conta para isso.
        List<Claimant_Country_lived__c> other = new List<Claimant_Country_lived__c>{
            new Claimant_Country_lived__c(Name = 'Ireland', Country_Type__c = 'IE', From_date__c = Date.newInstance(1970, 6, 1), Is_Live_Here_Now__c = true, Social_Security_Number__c = '1'),
            new Claimant_Country_lived__c(Name = 'Spain', Country_Type__c = 'ES', Is_Partner__c = true, From_date__c = Date.newInstance(1990, 1, 1), To_Date__c = Date.newInstance(1980, 1, 1))
        };
        String o = texts(XpLivedWorkedController.checks(b, none, other, noKids, today));
        System.assert(o.contains('Ireland is "now", but the address (Q6) is in Australia'), o);
        System.assert(o.contains('Spain (her): end date before start date'), o);

        // Faixas do UK trocadas ou antes do nascimento.
        Basic__c bad = new Basic__c(Claimant_dob__c = DOB, Claimant_lived_UK_From__c = Date.newInstance(1940, 1, 1), Claimant_lived_UK_to__c = Date.newInstance(1939, 1, 1),
            Claimant_worked_UK_From__c = Date.newInstance(1960, 1, 1), Claimant_worked_UK_To__c = Date.newInstance(1959, 1, 1));
        String u = texts(XpLivedWorkedController.checks(bad, none, new List<Claimant_Country_lived__c>(), noKids, today));
        System.assert(u.contains('In UK: end date before start date'), u);
        System.assert(u.contains('Worked in UK: end date before start date'), u);
        System.assert(u.contains('UK years: date before birth'), u);
    }

    @IsTest
    static void wordingHelpers() {
        System.assertEquals('his', XpLivedWorkedController.possessive(new Basic__c(Track__c = 'B')));
        System.assertEquals('her', XpLivedWorkedController.possessive(new Basic__c(Track__c = 'C')));
        System.assertEquals('his', XpLivedWorkedController.possessive(new Basic__c(Partner_Title__c = 'Mr.')));
        System.assertEquals('her', XpLivedWorkedController.possessive(new Basic__c(Partner_Title__c = 'Ms')));
        System.assertEquals('his', XpLivedWorkedController.possessive(new Basic__c(Claimant_title__c = 'Mrs')));
        System.assertEquals('her', XpLivedWorkedController.possessive(new Basic__c(Claimant_title__c = 'Mr')));
        System.assertEquals('spouse', XpLivedWorkedController.possessive(new Basic__c()));
        for (String code : new List<String>{ 'IE', 'AU', 'NZ', 'CA', 'US', 'ES' }) {
            System.assertNotEquals(null, XpLivedWorkedController.numberName(new Claimant_Country_lived__c(Country_Type__c = code)));
        }
        System.assertEquals('2 y', XpLivedWorkedController.span(800));
        System.assertEquals('4 months', XpLivedWorkedController.span(120));
        System.assertEquals('06 Oct 2026', XpLivedWorkedController.day(Date.newInstance(2026, 10, 6)));
        System.assertEquals('', XpLivedWorkedController.day(null));
        System.assertEquals(null, XpLivedWorkedController.lockReason('QC Approved'));
        System.assertEquals(null, XpLivedWorkedController.lockReason(null));
        System.assert(XpLivedWorkedController.lockReason('Sent for eSignature').contains('void the DocuSign envelope first'));
        System.assert(XpLivedWorkedController.lockReason('Signed - Waiting Docs at WDM').startsWith('Signed'));
        System.assert(XpLivedWorkedController.lockReason('45D Check').startsWith('Posted'));
        System.assert(XpLivedWorkedController.lockReason('On Hold').contains('On Hold'));
    }

    @IsTest
    static void addsRowsWithTheFlagsOfTheirList() {
        System.runAs(agent()) {
            Basic__c b = claim('Validation Call', 'B');
            Test.startTest();
            XpLivedWorkedController.SaveResult r = XpLivedWorkedController.saveRow(b.Id, 'ownAddress', null, new Map<String, Object>{
                'Address1__c' => '1 Test Street', 'City__c' => 'Testford', 'Postcode__c' => 'TE1 1ST', 'Country__c' => 'Isle of Man',
                'From_Date__c' => '1960-01-01', 'To_Date__c' => '1965-01-01', 'Is_Partner__c' => true });
            XpLivedWorkedController.saveRow(b.Id, 'spouseAddress', null, new Map<String, Object>{ 'Postcode__c' => 'TE2 2ND', 'Country__c' => 'Narnia' });
            XpLivedWorkedController.saveRow(b.Id, 'ownEmployer', null, new Map<String, Object>{ 'Name' => 'Test Works', 'From_Date__c' => null });
            XpLivedWorkedController.saveRow(b.Id, 'spouseEmployer', null, new Map<String, Object>{ 'Name' => 'His Works', 'City__c' => '  ' });
            XpLivedWorkedController.saveRow(b.Id, 'country', null, new Map<String, Object>{
                'Country_Type__c' => 'ie', 'From_date__c' => '1980-01-01', 'To_Date__c' => '1990-01-01', 'Is_Live_Here_Now__c' => true, 'Social_Security_Number__c' => '1234567T' });
            XpLivedWorkedController.saveRow(b.Id, 'spouseCountry', null, new Map<String, Object>{ 'Country_Type__c' => 'AU', 'Is_Live_Here_Now__c' => 'false' });
            XpLivedWorkedController.saveRow(b.Id, 'child', null, new Map<String, Object>{ 'Name' => 'Kid', 'Dob__c' => '1982-05-04T00:00:00.000Z' });
            Test.stopTest();

            System.assert(!r.regenerating, 'the pack does not exist yet in Validation Call');
            Claimant_Company__c own = [SELECT Name, Country__c, Country_Type__c, Is_Addresses__c, Is_Partner__c, isFullForm__c FROM Claimant_Company__c WHERE Id = :r.rowId];
            System.assertEquals('Isle of Man', own.Name);
            System.assertEquals('IMN', own.Country_Type__c);
            System.assert(own.Is_Addresses__c && !own.Is_Partner__c && !own.isFullForm__c, 'flags come from the list, not from the request');
            Claimant_Company__c spouseAddress = [SELECT Country__c, Country_Type__c, Is_Partner__c FROM Claimant_Company__c WHERE Postcode__c = 'TE2 2ND'];
            System.assertEquals('United Kingdom', spouseAddress.Country__c);
            System.assertEquals('GBR', spouseAddress.Country_Type__c);
            System.assert(spouseAddress.Is_Partner__c);
            Claimant_Company__c employer = [SELECT Country__c, Is_Addresses__c, Is_Partner__c FROM Claimant_Company__c WHERE Name = 'Test Works'];
            System.assertEquals('United Kingdom', employer.Country__c);
            System.assert(!employer.Is_Addresses__c && !employer.Is_Partner__c);
            System.assert([SELECT Is_Partner__c FROM Claimant_Company__c WHERE Name = 'His Works'].Is_Partner__c);
            Claimant_Country_lived__c ie = [SELECT Name, Country_Type__c, To_Date__c, Is_Partner__c FROM Claimant_Country_lived__c WHERE Country_Type__c = 'IE'];
            System.assertEquals('Ireland', ie.Name);
            System.assertEquals(null, ie.To_Date__c, '"now" has no end date');
            System.assert(!ie.Is_Partner__c);
            System.assert([SELECT Is_Partner__c FROM Claimant_Country_lived__c WHERE Country_Type__c = 'AU'].Is_Partner__c);
            System.assertEquals(Date.newInstance(1982, 5, 4), [SELECT Dob__c FROM Claimant_Child__c WHERE Basic__c = :b.Id].Dob__c);
        }
    }

    @IsTest
    static void editingAfterThePackExistsRebuildsIt() {
        System.runAs(agent()) {
            Basic__c b = claim('Agent Check', 'A');
            Claimant_Company__c c = new Claimant_Company__c(Basic__c = b.Id, Name = 'Old Name', Country__c = 'Isle of Man', From_Date__c = Date.newInstance(1965, 1, 1));
            Claimant_Child__c kid = new Claimant_Child__c(Basic__c = b.Id, Name = 'Kid');
            insert c;
            insert kid;
            Test.startTest();
            XpLivedWorkedController.SaveResult r = XpLivedWorkedController.saveRow(b.Id, 'ownEmployer', c.Id, new Map<String, Object>{ 'Name' => 'New Name', 'To_Date__c' => '1970-01-01' });
            XpLivedWorkedController.SaveResult d = XpLivedWorkedController.deleteRow(b.Id, kid.Id);
            Test.stopTest();
            System.assert(r.regenerating);
            System.assert(d.regenerating);
            Claimant_Company__c after = [SELECT Name, Country__c, From_Date__c, To_Date__c, Is_Addresses__c FROM Claimant_Company__c WHERE Id = :c.Id];
            System.assertEquals('New Name', after.Name);
            System.assertEquals('Isle of Man', after.Country__c, 'a country already there is kept');
            System.assertEquals(Date.newInstance(1965, 1, 1), after.From_Date__c, 'fields not sent stay as they were');
            System.assertEquals(0, [SELECT COUNT() FROM Claimant_Child__c WHERE Id = :kid.Id]);
            System.assertEquals(true, XpLivedWorkedController.getData(b.Id).regenerates);
        }
    }

    @IsTest
    static void deletesEachKindAndEditsCountries() {
        System.runAs(agent()) {
            Basic__c b = claim('Form completed', 'C');
            Claimant_Country_lived__c ie = new Claimant_Country_lived__c(Basic__c = b.Id, Name = 'Ireland', Country_Type__c = 'IE', From_date__c = Date.newInstance(1980, 1, 1));
            Claimant_Country_lived__c au = new Claimant_Country_lived__c(Basic__c = b.Id, Name = 'Australia', Country_Type__c = 'AU', Is_Partner__c = true);
            Claimant_Company__c a = new Claimant_Company__c(Basic__c = b.Id, Name = 'United Kingdom', Is_Addresses__c = true, Address1__c = '1 Test Street');
            insert new List<SObject>{ ie, au, a };
            Test.startTest();
            XpLivedWorkedController.saveRow(b.Id, 'country', ie.Id, new Map<String, Object>{ 'Country_Type__c' => 'ES', 'Social_Security_Number__c' => '' });
            XpLivedWorkedController.saveRow(b.Id, 'ownAddress', a.Id, new Map<String, Object>{ 'City__c' => 'Testford' });
            XpLivedWorkedController.deleteRow(b.Id, au.Id);
            XpLivedWorkedController.deleteRow(b.Id, a.Id);
            Test.stopTest();
            System.assertEquals('Spain', [SELECT Name FROM Claimant_Country_lived__c WHERE Id = :ie.Id].Name);
            System.assertEquals(1, [SELECT COUNT() FROM Claimant_Country_lived__c WHERE Basic__c = :b.Id]);
            System.assertEquals(0, [SELECT COUNT() FROM Claimant_Company__c WHERE Basic__c = :b.Id]);
        }
    }

    @IsTest
    static void lockedStatusesRefuseInApex() {
        System.runAs(agent()) {
            Map<String, String> expected = new Map<String, String>{
                'Sent for eSignature' => 'void the DocuSign envelope first',
                'Signed - Waiting Docs at WDM' => 'Signed',
                'Posted to DWP' => 'Posted',
                'Closed' => 'Read-only'
            };
            for (String status : expected.keySet()) {
                Basic__c b = claim(status, 'A');
                Claimant_Child__c kid = new Claimant_Child__c(Basic__c = b.Id, Name = 'Kid');
                insert kid;
                XpLivedWorkedController.CardData d = XpLivedWorkedController.getData(b.Id);
                System.assert(!d.editable, status);
                System.assert(d.lockReason.contains(expected.get(status)), status + ': ' + d.lockReason);
                assertRefused(b.Id, 'child', null, new Map<String, Object>{ 'Name' => 'Kid' }, expected.get(status));
                try {
                    XpLivedWorkedController.deleteRow(b.Id, kid.Id);
                    System.assert(false, 'delete should be refused in ' + status);
                } catch (AuraHandledException e) {
                    System.assert(e.getMessage().contains(expected.get(status)), e.getMessage());
                }
            }
        }
    }

    @IsTest
    static void refusesBadRequests() {
        System.runAs(agent()) {
            Basic__c b = claim('QC Approved', 'A');
            Basic__c other = claim('QC Approved', 'A');
            Claimant_Company__c employer = new Claimant_Company__c(Basic__c = b.Id, Name = 'Test Works');
            Claimant_Child__c otherKid = new Claimant_Child__c(Basic__c = other.Id, Name = 'Kid');
            insert employer;
            insert otherKid;
            assertRefused(b.Id, 'everything', null, null, 'Unknown list');
            assertRefused(b.Id, 'ownEmployer', null, new Map<String, Object>{ 'Name' => ' ' }, 'employer name');
            assertRefused(b.Id, 'child', null, new Map<String, Object>{ 'Name' => null }, 'child');
            assertRefused(b.Id, 'ownAddress', null, new Map<String, Object>{ 'City__c' => 'Testford' }, 'street or the postcode');
            assertRefused(b.Id, 'ownEmployer', null, new Map<String, Object>{ 'Name' => 'X'.repeat(81) }, '80 characters');
            assertRefused(b.Id, 'ownEmployer', null, new Map<String, Object>{ 'Name' => 'X', 'From_Date__c' => '1970-01-01', 'To_Date__c' => '1960-01-01' }, 'before the start date');
            assertRefused(b.Id, 'ownEmployer', null, new Map<String, Object>{ 'Name' => 'X', 'From_Date__c' => 'soon' }, 'Not a date');
            assertRefused(b.Id, 'country', null, new Map<String, Object>{ 'Country_Type__c' => 'ZZ' }, 'Pick the country');
            assertRefused(b.Id, 'country', null, new Map<String, Object>(), 'Pick the country');
            assertRefused(b.Id, 'ownAddress', employer.Id, new Map<String, Object>{ 'Postcode__c' => 'TE1' }, 'not in this list');
            assertRefused(b.Id, 'child', otherKid.Id, new Map<String, Object>{ 'Name' => 'Kid' }, 'not in this list');
            assertRefused(null, 'child', null, null, 'No claim');
            try {
                XpLivedWorkedController.deleteRow(b.Id, null);
                System.assert(false);
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('Nothing to delete'), e.getMessage());
            }
            try {
                XpLivedWorkedController.deleteRow(b.Id, b.Id);
                System.assert(false);
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('not in this list'), e.getMessage());
            }
            // Claim sem filhos: os filhos com lookup obrigatório não deixam apagar.
            Basic__c empty = claim('QC Approved', 'A');
            Id gone = empty.Id;
            delete empty;
            try {
                XpLivedWorkedController.getData(gone);
                System.assert(false);
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('not found'), e.getMessage());
            }
            assertRefused(gone, 'child', null, null, 'not found');
        }
    }

    @IsTest
    static void findsTheIpcbr1AndTheCountries() {
        System.runAs(agent()) {
            Basic__c b = claim('Form completed', 'A');
            insert new List<ContentVersion>{
                new ContentVersion(Title = 'Test Person_C99999_D5_IPCBR1_Wet_Signature', PathOnClient = 'a.pdf', VersionData = Blob.valueOf('a'), FirstPublishLocationId = b.Id),
                new ContentVersion(Title = 'Test Person_C99999_IPCBR1', PathOnClient = 'b.pdf', VersionData = Blob.valueOf('b'), FirstPublishLocationId = b.Id)
            };
            Id br1 = [SELECT ContentDocumentId FROM ContentVersion WHERE Title = 'Test Person_C99999_IPCBR1'].ContentDocumentId;
            System.assertEquals(br1, XpLivedWorkedController.getData(b.Id).ipcbr1Id);
            List<XpLivedWorkedController.Option> options = XpLivedWorkedController.getCountryOptions();
            System.assertEquals(3, options.size());
            System.assertEquals('Australia', options[0].label);
            System.assertEquals('AU', options[0].value);
        }
    }

    private static void assertRefused(Id claimId, String kind, Id rowId, Map<String, Object> fields, String text) {
        try {
            XpLivedWorkedController.saveRow(claimId, kind, rowId, fields);
            System.assert(false, 'should be refused: ' + text);
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains(text), e.getMessage() + ' (expected ' + text + ')');
        }
    }
}