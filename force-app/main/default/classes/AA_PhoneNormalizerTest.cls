/**
 * AA_PhoneNormalizerTest — pins the E.164 rules, including the two input
 * shapes audit 2026-10-02 F117 found stored undialable:
 *   '+44 (0)7476 900311' → was '+4407476900311'
 *   '447476900311'       → was bare digits (no '+')
 */
@isTest
private class AA_PhoneNormalizerTest {

    @isTest static void ukTrunkPrefixBecomesPlus44() {
        System.assertEquals('+447476900311', AA_PhoneNormalizer.toE164('07476 900311'));
        System.assertEquals('+441612345678', AA_PhoneNormalizer.toE164('0161 234 5678'));
    }

    @isTest static void internationalPrefixes() {
        System.assertEquals('+447476900311', AA_PhoneNormalizer.toE164('+44 7476 900311'));
        System.assertEquals('+447476900311', AA_PhoneNormalizer.toE164('0044 7476 900311'));
        System.assertEquals('+353871234567', AA_PhoneNormalizer.toE164('+353 87 123 4567'));
    }

    @isTest static void bracketedTrunkZeroIsDropped() {
        System.assertEquals('+447476900311', AA_PhoneNormalizer.toE164('+44 (0)7476 900311'),
            'F117: the bracketed UK trunk 0 must not survive into E.164');
        System.assertEquals('+447476900311', AA_PhoneNormalizer.toE164('0044 (0)7476 900311'));
    }

    @isTest static void countryCodeWithoutPlusGetsPlus() {
        System.assertEquals('+447476900311', AA_PhoneNormalizer.toE164('447476900311'),
            'F117: a 44-prefixed UK number typed without + must be stored as E.164');
    }

    @isTest static void ambiguousAndEmptyInputs() {
        // No country can be inferred: digits only, exactly as before.
        System.assertEquals('7476900311', AA_PhoneNormalizer.toE164('7476900311'));
        System.assertEquals(null, AA_PhoneNormalizer.toE164('   '));
        System.assertEquals(null, AA_PhoneNormalizer.toE164('n/a'));
        System.assertEquals(null, AA_PhoneNormalizer.toE164(null));
    }

    @isTest static void triggerPathNormalizesOnInsert() {
        AA_Application__c a = new AA_Application__c(
            First_Name__c = 'Phone', Last_Name__c = 'Norm', Stage__c = 'New',
            Phone__c = '+44 (0)7476 900311'
        );
        insert a;
        System.assertEquals('+447476900311',
            [SELECT Phone__c FROM AA_Application__c WHERE Id = :a.Id].Phone__c);
    }
}