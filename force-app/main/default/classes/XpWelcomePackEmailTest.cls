@IsTest
private class XpWelcomePackEmailTest {

    private static Basic__c newClaim(String email, String helper) {
        Basic__c claim = new Basic__c(Email__c = email, Friend_Email__c = helper);
        insert claim;
        return claim;
    }

    @IsTest
    static void notPostedYetUntilTheDateIsSet() {
        Basic__c claim = newClaim('client@test.com', null);
        System.assertEquals(true, XpWelcomePackEmail.notPostedYet(claim.Id));

        update new Basic__c(Id = claim.Id, Big_Envelop_Posted_Date__c = Date.today());
        System.assertEquals(false, XpWelcomePackEmail.notPostedYet(claim.Id), 'A re-post does not send again');
    }

    @IsTest
    static void helperGoesInCcUnlessEmptyOrTheSame() {
        System.assertEquals('helper@test.com', XpWelcomePackEmail.helperCc(new Basic__c(Email__c = 'client@test.com', Friend_Email__c = ' helper@test.com ')));
        System.assertEquals(null, XpWelcomePackEmail.helperCc(new Basic__c(Email__c = 'client@test.com', Friend_Email__c = 'CLIENT@test.com')));
        System.assertEquals(null, XpWelcomePackEmail.helperCc(new Basic__c(Email__c = 'client@test.com', Friend_Email__c = null)));
    }

    @IsTest
    static void australianClaimsGetTheSydneyTemplate() {
        System.assertEquals(XpWelcomePackEmail.TEMPLATE_AU, XpWelcomePackEmail.templateFor('AUD'));
        System.assertEquals(XpWelcomePackEmail.TEMPLATE, XpWelcomePackEmail.templateFor('EUR'));
        System.assertEquals(XpWelcomePackEmail.TEMPLATE, XpWelcomePackEmail.templateFor(null));
    }

    @IsTest
    static void claimWithoutEmailIsLoggedNotThrown() {
        Basic__c claim = newClaim(null, null);

        Test.startTest();
        XpWelcomePackEmail.send(claim.Id);
        Test.stopTest();

        System.assertEquals(0, XpWelcomePackEmail.prepared);
        List<Application_Form_Error__c> errors = [SELECT Error_Body__c FROM Application_Form_Error__c];
        System.assertEquals(1, errors.size());
        System.assert(errors[0].Error_Body__c.startsWith('Welcome pack e-mail not sent'), errors[0].Error_Body__c);
    }

    @IsTest
    static void claimWithEmailGetsIt() {
        insert new Contact(LastName = 'Client', Email = 'client@test.com');
        Basic__c claim = newClaim('client@test.com', 'helper@test.com');

        Test.startTest();
        XpWelcomePackEmail.send(claim.Id);
        Test.stopTest();

        System.assertEquals(1, XpWelcomePackEmail.prepared, String.valueOf([SELECT Error_Body__c FROM Application_Form_Error__c]));
    }
}