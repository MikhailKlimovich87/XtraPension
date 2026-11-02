/**
 * AA_ApplicationFieldSyncTest — covers AA_ApplicationFieldSync, exercised
 * through the real AA_AnswerTrigger (after insert/update/delete) so the tests
 * prove the production path, not just the class in isolation.
 *
 * Primary purpose (2026-08-27 address data-flow fix): prove that a client's
 * CORRECTED postcode — written by the Form Link as the `home-address-manual-postcode`
 * answer — now lands in the Application's Postcode__c scalar. Before the fix,
 * Postcode__c was sourced from the DWP lookup id `home-address-postcode`, which
 * the Form Link never writes, so a client's correction never reached the scalar
 * (nor, downstream, the fill worker's engine answer). The rep address has no
 * scalar target on the object, so there is nothing to assert there.
 */
@isTest
private class AA_ApplicationFieldSyncTest {

    private static AA_Application__c makeApp() {
        // Mirrors AA_AllTests.makeApp — required minimums per AA_ApplicationTrigger.
        // Postcode__c seeded with the "intake" value so we can prove a later
        // manual correction overwrites it (the exact bug the fix targets).
        AA_Application__c a = new AA_Application__c(
            First_Name__c = 'Field',
            Last_Name__c  = 'Sync' + Math.mod(Math.abs(Crypto.getRandomInteger()), 100000),
            Phone__c      = '+441234567890',
            Postcode__c   = 'OLD1 1AA',
            Stage__c      = 'New'
        );
        insert a;
        return a;
    }

    private static AA_Answer__c ans(Id appId, String fieldId, String value) {
        return new AA_Answer__c(
            Application__c = appId,
            Field_Id__c    = fieldId,
            Value__c       = value,
            Source__c      = 'form'
        );
    }

    private static AA_Application__c reload(Id appId) {
        return [
            SELECT Address_Line1__c, Address_Line2__c, City__c, County__c,
                   Postcode__c, First_Name__c, Last_Name__c, Email__c, Phone__c, DOB__c
              FROM AA_Application__c WHERE Id = :appId
        ];
    }

    /**
     * THE FIX: a client's corrected manual postcode must mirror into Postcode__c.
     * This is the row a CLIENT_REROUTE-driven Form Link actually writes.
     */
    @isTest static void manualPostcode_writes_Postcode() {
        AA_Application__c a = makeApp();

        Test.startTest();
        insert ans(a.Id, 'home-address-manual-postcode', 'M1 2AB');
        Test.stopTest();

        System.assertEquals('M1 2AB', reload(a.Id).Postcode__c,
            'home-address-manual-postcode must mirror into Postcode__c (overwriting the stale intake value)');
    }

    /** Updating the manual postcode answer must re-flow into Postcode__c. */
    @isTest static void manualPostcode_update_refreshes_Postcode() {
        AA_Application__c a = makeApp();
        AA_Answer__c row = ans(a.Id, 'home-address-manual-postcode', 'M1 2AB');
        insert row;
        System.assertEquals('M1 2AB', reload(a.Id).Postcode__c, 'precondition: first correction landed');

        Test.startTest();
        row.Value__c = 'LS1 4DY';
        update row;
        Test.stopTest();

        System.assertEquals('LS1 4DY', reload(a.Id).Postcode__c,
            'a re-corrected manual postcode must refresh Postcode__c');
    }

    /**
     * The full manual address page mirrors line/town/county/postcode together —
     * regression guard that the existing line mappings still work alongside the
     * new postcode mapping.
     */
    @isTest static void manualAddress_mirrors_all_scalars() {
        AA_Application__c a = makeApp();

        Test.startTest();
        insert new List<AA_Answer__c>{
            ans(a.Id, 'home-address-manual-line-one', '10 Downing Street'),
            ans(a.Id, 'home-address-manual-line-two', 'Westminster'),
            ans(a.Id, 'home-address-manual-town',     'London'),
            ans(a.Id, 'home-address-manual-county',   'Greater London'),
            ans(a.Id, 'home-address-manual-postcode', 'SW1A 2AA')
        };
        Test.stopTest();

        AA_Application__c after = reload(a.Id);
        System.assertEquals('10 Downing Street', after.Address_Line1__c, 'line1 mirror');
        System.assertEquals('Westminster',       after.Address_Line2__c, 'line2 mirror');
        System.assertEquals('London',            after.City__c,          'town → City__c mirror');
        System.assertEquals('Greater London',    after.County__c,        'county mirror');
        System.assertEquals('SW1A 2AA',          after.Postcode__c,      'manual postcode → Postcode__c mirror');
    }

    /**
     * Guard the fix's key semantic: the DWP lookup id `home-address-postcode`
     * (seeded at intake, never written by the Form Link) must NOT drive
     * Postcode__c — otherwise a stale seeded lookup answer could re-freeze the
     * scalar. Writing ONLY that id must leave the existing Postcode__c untouched.
     */
    @isTest static void lookupPostcodeAnswer_doesNotDrive_Postcode() {
        AA_Application__c a = makeApp();   // Postcode__c = 'OLD1 1AA'

        Test.startTest();
        insert ans(a.Id, 'home-address-postcode', 'ZZ9 9ZZ');
        Test.stopTest();

        System.assertEquals('OLD1 1AA', reload(a.Id).Postcode__c,
            'home-address-postcode (lookup id) is no longer a scalar source — Postcode__c stays as-is');
    }

    /**
     * Deleting the manual postcode answer clears Postcode__c (it is not a
     * required parent), keeping the delete-propagation semantics intact for the
     * newly-mapped id.
     */
    @isTest static void manualPostcode_delete_clears_Postcode() {
        AA_Application__c a = makeApp();
        AA_Answer__c row = ans(a.Id, 'home-address-manual-postcode', 'M1 2AB');
        insert row;
        System.assertEquals('M1 2AB', reload(a.Id).Postcode__c, 'precondition: correction landed');

        Test.startTest();
        delete row;
        Test.stopTest();

        System.assertEquals(null, reload(a.Id).Postcode__c,
            'deleting the manual postcode answer clears the (non-required) Postcode__c scalar');
    }

    /**
     * Broad coverage of the rest of the mirror (name/email/phone/DOB triplet) so
     * this class carries AA_ApplicationFieldSync without leaning on AA_AllTests.
     */
    @isTest static void otherScalars_and_dob_mirror() {
        AA_Application__c a = makeApp();

        Test.startTest();
        insert new List<AA_Answer__c>{
            ans(a.Id, 'first-name',           'Aoife'),
            ans(a.Id, 'middle-name',          'Mary'),
            ans(a.Id, 'last-name',            'Nolan'),
            ans(a.Id, 'contact-by-email',     'aoife@example.com'),
            ans(a.Id, 'main-contact-number',  '+441611234567'),
            ans(a.Id, 'birth-date-day',       '3'),
            ans(a.Id, 'birth-date-month',     '4'),
            ans(a.Id, 'birth-date-year',      '1950')
        };
        Test.stopTest();

        AA_Application__c after = reload(a.Id);
        System.assertEquals('Aoife',             after.First_Name__c);
        System.assertEquals('Nolan',             after.Last_Name__c);
        System.assertEquals('aoife@example.com', after.Email__c);
        System.assertEquals('+441611234567',     after.Phone__c);
        System.assertEquals(Date.newInstance(1950, 4, 3), after.DOB__c,
            'birth-date-day/-month/-year triplet must recombine into DOB__c');
    }

    // audit: a raw typed phone must be normalised to E.164 for Phone__c (dialing
    // + caller-id recognition), and an unparseable one must NOT overwrite Phone__c.
    @isTest static void phone_raw_normalised_to_e164() {
        AA_Application__c a = makeApp();
        Test.startTest();
        insert ans(a.Id, 'main-contact-number', '07476 900311');
        Test.stopTest();
        System.assertEquals('+447476900311', reload(a.Id).Phone__c, 'raw main-contact-number must normalise to E.164');
    }

    @isTest static void phone_unparseable_is_skipped() {
        AA_Application__c a = makeApp(); // seeds Phone__c = '+441234567890'
        Test.startTest();
        insert ans(a.Id, 'main-contact-number', 'not a phone number');
        Test.stopTest();
        System.assertEquals('+441234567890', reload(a.Id).Phone__c, 'unparseable number must not overwrite Phone__c');
    }

    /**
     * audit 2026-10-02 F38: an impossible date used to roll over silently
     * (31/02/1948 became DOB 02/03/1948), and an out-of-range year produced a
     * DOB that failed DOB_Reasonable in the parent update, which rolled back
     * the answer insert itself. Both now leave DOB__c alone and keep the
     * answers, so the operator sees and fixes the bad part.
     */
    @isTest static void impossible_dob_is_not_rolled_over() {
        AA_Application__c a = makeApp();
        Test.startTest();
        insert new List<AA_Answer__c>{
            ans(a.Id, 'birth-date-day', '31'), ans(a.Id, 'birth-date-month', '2'), ans(a.Id, 'birth-date-year', '1948')
        };
        Test.stopTest();
        System.assertEquals(null, reload(a.Id).DOB__c, '31 February must not become 2 March');
        System.assertEquals(3, [SELECT COUNT() FROM AA_Answer__c WHERE Application__c = :a.Id AND Field_Id__c LIKE 'birth-date-%'],
            'the answers are kept for correction');
    }

    @isTest static void out_of_range_dob_year_does_not_fail_the_answer_save() {
        AA_Application__c a = makeApp();
        insert new List<AA_Answer__c>{
            ans(a.Id, 'birth-date-day', '3'), ans(a.Id, 'birth-date-month', '4'), ans(a.Id, 'birth-date-year', '1950')
        };
        System.assertEquals(Date.newInstance(1950, 4, 3), reload(a.Id).DOB__c, 'precondition: valid DOB mirrored');

        AA_Answer__c yearRow = [SELECT Id FROM AA_Answer__c WHERE Application__c = :a.Id AND Field_Id__c = 'birth-date-year'];
        Test.startTest();
        update new AA_Answer__c(Id = yearRow.Id, Value__c = '1850');   // threw DOB_Reasonable before the fix
        update new AA_Answer__c(Id = yearRow.Id, Value__c = String.valueOf(Date.today().year() + 4));
        Test.stopTest();

        System.assertEquals(String.valueOf(Date.today().year() + 4),
            [SELECT Value__c FROM AA_Answer__c WHERE Id = :yearRow.Id].Value__c, 'the answer save went through');
        System.assertEquals(Date.newInstance(1950, 4, 3), reload(a.Id).DOB__c, 'an implausible DOB never reaches DOB__c');
    }

    @isTest static void parseDob_unit() {
        System.assertEquals(Date.newInstance(1948, 2, 29), AA_ApplicationFieldSync.parseDob('29', '2', '1948'), 'leap day is real');
        System.assertEquals(null, AA_ApplicationFieldSync.parseDob('29', '2', '1949'), 'not a leap year');
        System.assertEquals(null, AA_ApplicationFieldSync.parseDob('1', '13', '1950'), 'month 13');
        System.assertEquals(null, AA_ApplicationFieldSync.parseDob('x', '1', '1950'), 'not a number');
        System.assertEquals(null, AA_ApplicationFieldSync.parseDob('1', '1', '1899'), 'before 1900');
        System.assertEquals(Date.newInstance(1950, 4, 3), AA_ApplicationFieldSync.parseDob(' 03 ', '04', '1950'), 'padded parts are fine');
    }

    /** Convenience no-context overload is safe to call directly (bulk/manual runs). */
    @isTest static void convenienceOverload_runs() {
        AA_Application__c a = makeApp();
        insert ans(a.Id, 'home-address-manual-postcode', 'M1 2AB');

        Test.startTest();
        AA_ApplicationFieldSync.syncFromAnswers(new Set<Id>{ a.Id });
        Test.stopTest();

        System.assertEquals('M1 2AB', reload(a.Id).Postcode__c,
            'no-context overload still mirrors the manual postcode');
    }
}