/**
 * Canada in the Claims pack (16/11/2026): bank numbers, Missing Info, the IPC1394, the debit agreement,
 * GoCardless pre-authorized debit, the fee in CAD and the bank lookup.
 */
@IsTest
private class XpClaimCanadaTest {

    private static Basic__c claim(Map<String, Object> fields) {
        Contact c = new Contact(LastName = 'Snow', Email = 'john.snow@example.com');
        insert c;
        Basic__c b = BP_TestDataFactory.createBasic(c.Id, false);
        b.Email__c = 'john.snow@example.com';
        b.Bank_Country_Code__c = 'CA';
        b.Bank_Country__c = 'Canada';
        b.Bank_IBAN__c = null;
        b.Bank_BIC__c = null;
        b.Bank_Sort_Code__c = '003-12345';
        b.Bank_Account__c = '1234 567';
        for (String f : fields.keySet()) b.put(f, fields.get(f));
        insert b;
        return b;
    }

    private static String clientLines(Id basicId) {
        List<String> out = new List<String>();
        for (BP_MissingInfo.Item i : BP_MissingInfo.clientItems(BP_MissingInfo.check(BP_MissingInfo.load(basicId)))) out.add(i.clientText);
        return String.join(out, ' | ');
    }

    @IsTest
    static void readsTheTwoNumbersHoweverTheyWereTyped() {
        for (String typed : new List<String>{ '003-12345', '00312345', '12345-003', '000312345', '0003-12345', ' 003 12345 ' }) {
            XpCanadaBank.Parts p = XpCanadaBank.parts(typed);
            System.assertNotEquals(null, p, typed);
            System.assertEquals('003', p.institution, typed);
            System.assertEquals('12345', p.transit, typed);
        }
        for (String typed : new List<String>{ null, '', '12-34-56', '123-456', 'IE29AIBK93115212345678', '1234567890' }) {
            System.assertEquals(null, XpCanadaBank.parts(typed), 'typed: ' + typed);
        }
        System.assertEquals('1234567', XpCanadaBank.accountNumber('1234-567 '));
        System.assertEquals(null, XpCanadaBank.accountNumber(null));
    }

    @IsTest
    static void missingInfoDoesNotAskACanadianForAnIban() {
        Basic__c b = claim(new Map<String, Object>());
        String client = clientLines(b.Id);
        System.assert(!client.contains('IBAN'), client);
        System.assert(!client.contains('BIC'), client);
        System.assert(!client.contains('transit'), client);
    }

    @IsTest
    static void missingInfoAsksForInstitutionAndTransit() {
        Basic__c b = claim(new Map<String, Object>{ 'Bank_Sort_Code__c' => '12-34-56', 'Bank_Account__c' => null });
        String client = clientLines(b.Id);
        System.assert(client.contains('institution and transit numbers'), client);
        System.assert(client.contains('account number'), client);
        System.assert(!client.contains('IBAN'), client);
    }

    @IsTest
    static void ipc1394CarriesBankNumberAndTransit() {
        Basic__c b = claim(new Map<String, Object>{ 'Bank_BIC__c' => 'ROYCCAT2' });
        BP_IPC1394_Wrapper.ApplicationDataWrapper w = new BP_IPC1394_Wrapper.ApplicationDataWrapper(BP_PortalUtils.getApplication(b.Id)[0]);
        System.assertEquals('CA', w.bankCountryCode);
        System.assertEquals('0003', w.Q17a, 'bank number: zero + institution');
        System.assertEquals('12345', w.Q17b, 'transit number');
        System.assertEquals('1234567', w.Q16, 'account number, bare');
        System.assertEquals(null, w.Q17, 'no IBAN for Canada');
        System.assertEquals('ROYCCAT2', w.Q18);
    }

    @IsTest
    static void debitAgreementCarriesTheCanadianNumbers() {
        Basic__c b = claim(new Map<String, Object>{ 'CurrencyIsoCode' => 'CAD', 'Bank_Name__c' => 'Royal Bank of Canada' });
        Basic__c loaded = BP_PortalUtils.getDDMandateBasicData(b.Id)[0];
        BP_RequestWrappers.DDMandateDataWrapper w = new BP_RequestWrappers.DDMandateDataWrapper(loaded);
        System.assertEquals('003', w.institution);
        System.assertEquals('12345', w.transit);
        System.assertEquals('Royal Bank of Canada', w.bankName);
        System.assertEquals(null, w.bsb1, 'the 3 + 3 boxes are for the Australian BSB');
        System.assert(BP_DirectDebitManadatePdfService.canadaUrl().endsWith('/fill-dd-mandate-canada'));

        Test.startTest();
        BP_DirectDebitManadatePdfService.generatePdf(b.Id); // the PDF call is skipped in tests; this is the CAD branch
        Test.stopTest();
    }

    private class PadMock implements HttpCalloutMock {
        public Map<String, Object> bankAccount;
        public Map<String, Object> mandate;
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(201);
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(req.getBody());
            if (req.getEndpoint().endsWith('/customer_bank_accounts')) {
                bankAccount = (Map<String, Object>) root.get('customer_bank_accounts');
                res.setBody('{"customer_bank_accounts":{"id":"BA-CA"}}');
            } else {
                mandate = (Map<String, Object>) root.get('mandates');
                res.setBody('{"mandates":{"id":"MD-CA","status":"pending_submission"}}');
            }
            return res;
        }
    }

    @IsTest
    static void goCardlessGetsAPreAuthorizedDebitAccountAndMandate() {
        Basic__c b = claim(new Map<String, Object>{ 'Current_Address_Abroad__CountryCode__s' => 'CA' });
        Basic__c loaded = [
            SELECT Id, First_Name__c, Last_Name__c, Current_Address_Abroad__CountryCode__s, Current_Address_Abroad_Country__c,
                   Bank_IBAN__c, Bank_Account__c, Bank_Sort_Code__c, CurrencyIsoCode
            FROM Basic__c WHERE Id = :b.Id
        ];
        PadMock mock = new PadMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        GocardlessApiService service = new GocardlessApiService(loaded);
        String bankAccountId = service.createCustomerBankAccount('CU-TEST');
        String mandateId = service.createMandateWithBankAccount('CU-TEST', bankAccountId);
        Test.stopTest();

        System.assertEquals('BA-CA', bankAccountId);
        System.assertEquals('MD-CA', mandateId);
        System.assertEquals('003', mock.bankAccount.get('bank_code'));
        System.assertEquals('12345', mock.bankAccount.get('branch_code'));
        System.assertEquals('1234567', mock.bankAccount.get('account_number'));
        System.assertEquals('CA', mock.bankAccount.get('country_code'));
        System.assertEquals('CAD', mock.bankAccount.get('currency'));
        System.assert(!mock.bankAccount.containsKey('iban'));
        System.assertEquals('pad', mock.mandate.get('scheme'));
    }

    @IsTest
    static void goCardlessRefusesACanadianAccountWithoutItsNumbers() {
        Basic__c b = claim(new Map<String, Object>{ 'Current_Address_Abroad__CountryCode__s' => 'CA', 'Bank_Sort_Code__c' => '12-34-56' });
        Basic__c loaded = [
            SELECT Id, First_Name__c, Last_Name__c, Current_Address_Abroad__CountryCode__s, Current_Address_Abroad_Country__c,
                   Bank_IBAN__c, Bank_Account__c, Bank_Sort_Code__c, CurrencyIsoCode
            FROM Basic__c WHERE Id = :b.Id
        ];
        Test.setMock(HttpCalloutMock.class, new PadMock());
        Test.startTest();
        String bankAccountId = new GocardlessApiService(loaded).createCustomerBankAccount('CU-TEST');
        Test.stopTest();
        System.assertEquals(null, bankAccountId, 'no call is made with a UK-shaped sort code');
    }

    @IsTest
    static void feeIsConvertedToCanadianDollars() {
        insert new Daily_Exchange_Rate__c(Rate_Date__c = Date.today(), Date_Key__c = String.valueOf(Date.today()),
            GBP_to_EUR__c = 1.2, GBP_to_AUD__c = 1.9, GBP_to_CAD__c = 1.85, Fetched_At__c = Datetime.now());
        Map<String, Object> info = BP_GoCardlessPaymentSchedulerController.getGbpExchangeInfo('CAD');
        System.assertEquals(1.85, (Decimal) info.get('rate'));
        System.assertEquals('CAD', info.get('targetCurrency'));
    }

    private class LookupMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            System.assert(req.getEndpoint().endsWith('/bank_details_lookups'), req.getEndpoint());
            Map<String, Object> sent = (Map<String, Object>) ((Map<String, Object>) JSON.deserializeUntyped(req.getBody())).get('bank_details_lookups');
            System.assertEquals('CA', sent.get('country_code'));
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            if (sent.get('branch_code') == '12345') {
                res.setStatusCode(200);
                res.setBody('{"bank_details_lookups":{"bank_name":"ROYAL BANK OF CANADA","available_debit_schemes":["pad"],"bic":null}}');
            } else {
                res.setStatusCode(422);
                res.setBody('{"error":{"message":"Validation failed","type":"validation_failed","code":422,"errors":['
                    + '{"field":"account_number","message":"is the wrong length (should be 7..12 characters)"},'
                    + '{"field":"branch_code","message":"branch code does not exist"}]}}');
            }
            return res;
        }
    }

    private static BP_RequestWrappers.ApplicationDetailsDataWrapper bankRequest(Id claimId, String sortCode, String account) {
        Map<String, Object> bank = new Map<String, Object>{ 'account' => account, 'sortCode' => sortCode, 'country' => 'CA', 'bic' => '' };
        return new BP_RequestWrappers.ApplicationDetailsDataWrapper(JSON.serialize(
            new Map<String, Object>{ 'applicationId' => claimId, 'application' => new Map<String, Object>{ 'bank' => bank } }));
    }

    @IsTest
    static void getBankInfoNamesACanadianBank() {
        Basic__c b = claim(new Map<String, Object>());
        Test.setMock(HttpCalloutMock.class, new LookupMock());
        Test.startTest();
        Map<String, Object> result = BP_PortalApplicationHelper.validateBank(bankRequest(b.Id, '12345-003', '1234-567'));
        Test.stopTest();
        System.assertEquals('success', result.get('status'), 'message: ' + result.get('message'));
        BP_CheckBank.BankAccountValidationResponseWrapper r = (BP_CheckBank.BankAccountValidationResponseWrapper) result.get('response');
        System.assertEquals('Royal Bank of Canada', r.ShortBankName);
        System.assertEquals('003-12345', r.SortCode, 'institution first, however it was typed');
        System.assertEquals('1234567', r.AccountNumber);
        System.assertEquals('ROYCCAT2', r.BICCode, 'known for the big banks');
        System.assert(!result.containsKey('message'), 'pre-authorized debit is available');
    }

    @IsTest
    static void getBankInfoSaysWhatIsWrongWithACanadianAccount() {
        Basic__c b = claim(new Map<String, Object>());
        Test.setMock(HttpCalloutMock.class, new LookupMock());
        Test.startTest();
        Map<String, Object> wrongNumbers = BP_PortalApplicationHelper.validateBank(bankRequest(b.Id, '003-99999', '12'));
        Map<String, Object> wrongShape = BP_PortalApplicationHelper.validateBank(bankRequest(b.Id, '12-34-56', '1234567'));
        Test.stopTest();
        System.assertEquals('error', wrongNumbers.get('status'));
        String said = (String) wrongNumbers.get('message');
        System.assert(said.contains('7 to 12 digits'), said);
        System.assert(!said.contains('99999'), 'one problem at a time: ' + said);
        System.assertEquals('error', wrongShape.get('status'));
        System.assert(((String) wrongShape.get('message')).contains('003-12345'), 'no call is made for a UK-shaped sort code');
        System.assertEquals('Bank of Montreal', XpCanadaBank.properCase('BANK OF MONTREAL'));
        System.assertEquals('The Toronto-Dominion Bank', XpCanadaBank.properCase('THE TORONTO-DOMINION BANK'));
    }

    @IsTest
    static void feeScheduleIsInCanadianDollars() {
        Basic__c b = claim(new Map<String, Object>{ 'CurrencyIsoCode' => 'CAD' });
        insert new Product2(Name = 'Claim - Direct Debit', CurrencyIsoCode = 'EUR', IsActive = true);
        insert new Daily_Exchange_Rate__c(Rate_Date__c = Date.today(), Date_Key__c = String.valueOf(Date.today()),
            GBP_to_EUR__c = 1.2, GBP_to_AUD__c = 1.9, GBP_to_CAD__c = 1.85, Fetched_At__c = Datetime.now());
        BP_GoCardlessPaymentSchedulerController.MandateWrapper w = new BP_GoCardlessPaymentSchedulerController.MandateWrapper();
        w.claimId = b.Id;
        w.awardAmount = 4000;
        w.feeAmount = 1000;
        w.installments = 2;
        w.firstChargeDate = Date.today().addDays(7);
        w.dwpPaymentDate = Date.today();

        Test.startTest();
        BP_GoCardlessPaymentSchedulerController.createDDPayments(w);
        Test.stopTest();

        Decimal total = 0;
        for (Basic_Payment__c pay : [SELECT Amount__c, CurrencyIsoCode FROM Basic_Payment__c WHERE Basic__c = :b.Id AND Product__r.Name = 'Claim - Direct Debit']) {
            System.assertEquals('CAD', pay.CurrencyIsoCode);
            total += pay.Amount__c;
        }
        System.assertEquals(1850, total, 'a fee of GBP 1,000 at 1.85 is CAD 1,850, not CAD 1,000');
    }
}