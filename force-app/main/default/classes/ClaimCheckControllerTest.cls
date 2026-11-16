@IsTest
private class ClaimCheckControllerTest {
    @TestSetup
    static void setupTestData() {
        insert new List<Basic__c>{
            new Basic__c(First_Name__c = 'Posted', Last_Name__c = 'Claim', Status__c = 'Posted to DWP'),
            new Basic__c(First_Name__c = 'Early', Last_Name__c = 'Claim', Status__c = 'Form In Progress')
        };
    }

    private static Basic__c postedClaim() {
        return [SELECT Id, Name FROM Basic__c WHERE First_Name__c = 'Posted' LIMIT 1];
    }

    private static ClaimCheckController.CheckRequest request(String claimName) {
        ClaimCheckController.CheckRequest req = new ClaimCheckController.CheckRequest();
        req.appName = claimName;
        req.notReceived = false;
        req.received = true;
        req.processing = true;
        req.moreInfo = false;
        req.approved = false;
        req.rejected = false;
        req.lumpSum = false;
        req.paymentStarted = false;
        req.calledDwp = true;
        req.notes = 'DWP has the claim, being processed';
        req.pdfLink = 'https://drive.google.com/test';
        return req;
    }

    @IsTest
    static void listsOnlyClaimsSentToTheDwp() {
        Test.startTest();
        List<Basic__c> claims = ClaimCheckController.getClaims();
        Test.stopTest();
        System.assertEquals(1, claims.size(), 'the claim still in Form In Progress is not listed');
        System.assertEquals('Posted', claims[0].First_Name__c);
    }

    @IsTest
    static void savesChecksByClaimNumberWithOrWithoutTheLetter() {
        Basic__c claim = postedClaim();
        ClaimCheckController.CheckRequestWrapper wrapper = new ClaimCheckController.CheckRequestWrapper();
        wrapper.checkAgent = 'Daniel';
        wrapper.checkReplies = new List<ClaimCheckController.CheckRequest>{
            request(claim.Name.replaceFirst('^C0*', '')),
            request(claim.Name)
        };

        Test.startTest();
        List<Claim_Check__c> result = ClaimCheckController.createClaimCheckRecords(wrapper);
        Test.stopTest();

        System.assertEquals(2, result.size());
        Claim_Check__c saved = [
            SELECT Basic__c, Check_Agents__c, Check_Date__c, Received_by_DWP__c, Processing__c, Called_DWP__c,
                Colour_Label__c, Priority_Request__c, First_Name__c
            FROM Claim_Check__c
            WHERE Id = :result[0].Id
        ];
        System.assertEquals(claim.Id, saved.Basic__c);
        System.assertEquals('Daniel', saved.Check_Agents__c);
        System.assertEquals(Date.today(), saved.Check_Date__c);
        System.assert(saved.Received_by_DWP__c && saved.Processing__c && saved.Called_DWP__c);
        System.assertEquals('GREEN', saved.Colour_Label__c);
        System.assertEquals('Processing', saved.Priority_Request__c);
        System.assertEquals('Posted', saved.First_Name__c);
        System.assertEquals(2, [SELECT Claim_Checks_Count__c FROM Basic__c WHERE Id = :claim.Id].Claim_Checks_Count__c);
    }

    @IsTest
    static void unknownClaimFails() {
        ClaimCheckController.CheckRequestWrapper wrapper = new ClaimCheckController.CheckRequestWrapper();
        wrapper.checkAgent = 'Vince';
        wrapper.checkReplies = new List<ClaimCheckController.CheckRequest>{ request('C99999') };
        Boolean failed = false;
        try {
            ClaimCheckController.createClaimCheckRecords(wrapper);
        } catch (AuraHandledException e) {
            failed = true;
        }
        System.assert(failed, 'a claim that does not exist cannot get a check');
        System.assertEquals(null, ClaimCheckController.createClaimCheckRecords(null));
    }

    @IsTest
    static void requestCheckStampsTheClaim() {
        Basic__c claim = postedClaim();
        Test.startTest();
        ClaimCheckController.addRequestCheckData(claim.Id);
        ClaimCheckController.addRequestCheckData(null);
        Test.stopTest();
        Basic__c updated = [SELECT Check_Request_by__c, Request_Check_Date__c FROM Basic__c WHERE Id = :claim.Id];
        System.assertEquals(Date.today(), updated.Request_Check_Date__c);
        System.assertNotEquals(null, updated.Check_Request_by__c);
    }

    @IsTest
    static void numberKeyIgnoresLetterAndZeros() {
        System.assertEquals('123', ClaimCheckController.numberKey('C00123'));
        System.assertEquals('123', ClaimCheckController.numberKey(' 0123 '));
        System.assertEquals('', ClaimCheckController.numberKey(null));
    }
}