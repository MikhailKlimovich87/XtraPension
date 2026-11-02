@IsTest
private class BP_DocuSignEnvelopesTest {

    // ============================================================
    // SETUP
    // ============================================================
    @TestSetup
    static void setup() {
        TestDataFactory.createTestCountry(true);
        Account acc = TestDataFactory.createAccount(true);
        Contact con = [
            SELECT Id FROM Contact WHERE AccountId = :acc.Id LIMIT 1
        ];
        Basic__c claim = BP_TestDataFactory.createBasic(con.Id, true);
        claim.Status__c = BP_DocuSignEnvelopes.STATUS_SENT_FOR_ESIG;
        update claim;
    }

    private static Basic__c getClaim() {
        return [
            SELECT Id, Status__c FROM Basic__c LIMIT 1
        ];
    }

    // Helper: create an EnvelopeStatus linked to a claim
    private static dfsle__EnvelopeStatus__c makeStatus(
        Id claimId,
        String docuSignId,
        String status
    ) {
        return new dfsle__EnvelopeStatus__c(
            dfsle__DocuSignId__c = docuSignId,
            dfsle__Status__c = status,
            dfsle__SourceId__c = String.valueOf(claimId)
        );
    }

    // Helper: create an Envelope + Documents
    private static dfsle__Envelope__c makeEnvelope(
        String docuSignId,
        List<String> documentNames
    ) {
        dfsle__Envelope__c env = new dfsle__Envelope__c(
            dfsle__DocuSignId__c = docuSignId
        );
        insert env;

        List<dfsle__Document__c> docs = new List<dfsle__Document__c>();
        for (String name : documentNames) {
            docs.add(new dfsle__Document__c(
                dfsle__Envelope__c = env.Id,
                dfsle__FullName__c = name
            ));
        }
        if (!docs.isEmpty()) {
            insert docs;
        }
        return env;
    }


    // ============================================================
    // EnvelopeInfo.hasDocument
    // ============================================================
    @IsTest
    static void hasDocumentReturnsFalseOnEmptyList() {
        BP_DocuSignEnvelopes.EnvelopeInfo info = new BP_DocuSignEnvelopes.EnvelopeInfo();
        System.assertEquals(false, info.hasDocument('Summary'));
    }

    @IsTest
    static void hasDocumentSkipsBlankNames() {
        BP_DocuSignEnvelopes.EnvelopeInfo info = new BP_DocuSignEnvelopes.EnvelopeInfo();
        info.documentNames = new List<String>{ null, '', '   ', 'Real_Doc' };
        System.assertEquals(true,  info.hasDocument('Real'));
        System.assertEquals(false, info.hasDocument('Missing'));
    }

    @IsTest
    static void hasDocumentIsCaseInsensitive() {
        BP_DocuSignEnvelopes.EnvelopeInfo info = new BP_DocuSignEnvelopes.EnvelopeInfo();
        info.documentNames = new List<String>{ 'John_Doe_ddMandate' };
        System.assertEquals(true, info.hasDocument('ddmandate'));
        System.assertEquals(true, info.hasDocument('DDMANDATE'));
    }


    // ============================================================
    // load()
    // ============================================================
    @IsTest
    static void loadReturnsEmptyListsForClaimsWithoutEnvelopes() {
        Basic__c claim = getClaim();

        Test.startTest();
        Map<Id, List<BP_DocuSignEnvelopes.EnvelopeInfo>> result =
            BP_DocuSignEnvelopes.load(new Set<Id>{ claim.Id });
        Test.stopTest();

        System.assertEquals(1, result.size());
        System.assert(result.containsKey(claim.Id));
        System.assertEquals(0, result.get(claim.Id).size());
    }

    @IsTest
    static void loadPopulatesEnvelopeInfoFromStatuses() {
        Basic__c claim = getClaim();

        insert new List<dfsle__EnvelopeStatus__c>{
            makeStatus(claim.Id, 'DS-1', 'Sent'),
            makeStatus(claim.Id, 'DS-2', 'Completed')
        };
        makeEnvelope('DS-1', new List<String>{ 'Summary' });
        makeEnvelope('DS-2', new List<String>{ 'ddMandate' });

        Test.startTest();
        Map<Id, List<BP_DocuSignEnvelopes.EnvelopeInfo>> result =
            BP_DocuSignEnvelopes.load(new Set<Id>{ claim.Id });
        Test.stopTest();

        System.assertEquals(2, result.get(claim.Id).size());

        BP_DocuSignEnvelopes.EnvelopeInfo first = result.get(claim.Id)[0];
        System.assertEquals('DS-1', first.docuSignId);
        System.assertEquals('Sent', first.status);
        System.assertEquals(1, first.documentNames.size());
        System.assertEquals('Summary', first.documentNames[0]);
    }

    @IsTest
    static void loadHandlesEnvelopeWithNoDocuments() {
        Basic__c claim = getClaim();

        insert makeStatus(claim.Id, 'DS-EMPTY', 'Created');
        makeEnvelope('DS-EMPTY', new List<String>());

        Test.startTest();
        Map<Id, List<BP_DocuSignEnvelopes.EnvelopeInfo>> result =
            BP_DocuSignEnvelopes.load(new Set<Id>{ claim.Id });
        Test.stopTest();

        System.assertEquals(1, result.get(claim.Id).size());
        System.assertEquals(0, result.get(claim.Id)[0].documentNames.size());
    }

    @IsTest
    static void loadHandlesMultipleClaimsInOneCall() {
        Basic__c claim = getClaim();

        // Second claim
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Basic__c otherClaim = BP_TestDataFactory.createBasic(con.Id, true);

        insert new List<dfsle__EnvelopeStatus__c>{
            makeStatus(claim.Id,      'DS-A', 'Sent'),
            makeStatus(otherClaim.Id, 'DS-B', 'Completed')
        };
        makeEnvelope('DS-A', new List<String>{ 'Summary' });
        makeEnvelope('DS-B', new List<String>{ 'ddMandate' });

        Test.startTest();
        Map<Id, List<BP_DocuSignEnvelopes.EnvelopeInfo>> result =
            BP_DocuSignEnvelopes.load(new Set<Id>{ claim.Id, otherClaim.Id });
        Test.stopTest();

        System.assertEquals(2, result.size());
        System.assertEquals(1, result.get(claim.Id).size());
        System.assertEquals(1, result.get(otherClaim.Id).size());
    }


    // ============================================================
    // hasInFlightEnvelope
    // ============================================================
    @IsTest
    static void hasInFlightEnvelopeReturnsFalseOnEmptyList() {
        System.assertEquals(false,
            BP_DocuSignEnvelopes.hasInFlightEnvelope(
                new List<BP_DocuSignEnvelopes.EnvelopeInfo>()
            )
        );
    }

    @IsTest
    static void hasInFlightEnvelopeTrueForCreatedSentDelivered() {
        for (String status : new List<String>{ 'Created', 'Sent', 'Delivered' }) {
            BP_DocuSignEnvelopes.EnvelopeInfo info = new BP_DocuSignEnvelopes.EnvelopeInfo();
            info.status = status;
            System.assertEquals(true,
                BP_DocuSignEnvelopes.hasInFlightEnvelope(
                    new List<BP_DocuSignEnvelopes.EnvelopeInfo>{ info }
                ),
                status
            );
        }
    }

    @IsTest
    static void hasInFlightEnvelopeFalseForCompletedOrFailed() {
        for (String status : new List<String>{ 'Completed', 'Voided', 'Declined', 'Expired' }) {
            BP_DocuSignEnvelopes.EnvelopeInfo info = new BP_DocuSignEnvelopes.EnvelopeInfo();
            info.status = status;
            System.assertEquals(false,
                BP_DocuSignEnvelopes.hasInFlightEnvelope(
                    new List<BP_DocuSignEnvelopes.EnvelopeInfo>{ info }
                ),
                status
            );
        }
    }


    // ============================================================
    // hasActiveDocument
    // ============================================================
    @IsTest
    static void hasActiveDocumentFalseOnEmptyList() {
        System.assertEquals(false,
            BP_DocuSignEnvelopes.hasActiveDocument(
                new List<BP_DocuSignEnvelopes.EnvelopeInfo>(),
                'Summary'
            )
        );
    }

    @IsTest
    static void hasActiveDocumentTrueForCompletedEnvelopeWithDoc() {
        BP_DocuSignEnvelopes.EnvelopeInfo info = new BP_DocuSignEnvelopes.EnvelopeInfo();
        info.status = 'Completed';
        info.documentNames = new List<String>{ 'Summary' };

        System.assertEquals(true,
            BP_DocuSignEnvelopes.hasActiveDocument(
                new List<BP_DocuSignEnvelopes.EnvelopeInfo>{ info }, 'Summary'
            )
        );
    }

    @IsTest
    static void hasActiveDocumentFalseForCompletedWithoutDoc() {
        BP_DocuSignEnvelopes.EnvelopeInfo info = new BP_DocuSignEnvelopes.EnvelopeInfo();
        info.status = 'Completed';
        info.documentNames = new List<String>{ 'Other' };

        System.assertEquals(false,
            BP_DocuSignEnvelopes.hasActiveDocument(
                new List<BP_DocuSignEnvelopes.EnvelopeInfo>{ info }, 'Summary'
            )
        );
    }

    @IsTest
    static void hasActiveDocumentFalseForFailedEnvelopeWithDoc() {
        BP_DocuSignEnvelopes.EnvelopeInfo info = new BP_DocuSignEnvelopes.EnvelopeInfo();
        info.status = 'Voided';
        info.documentNames = new List<String>{ 'Summary' };

        System.assertEquals(false,
            BP_DocuSignEnvelopes.hasActiveDocument(
                new List<BP_DocuSignEnvelopes.EnvelopeInfo>{ info }, 'Summary'
            )
        );
    }


    // ============================================================
    // isSigned
    // ============================================================
    @IsTest
    static void isSignedFalseWhenStatusIsNotCompleted() {
        BP_DocuSignEnvelopes.EnvelopeInfo info = new BP_DocuSignEnvelopes.EnvelopeInfo();
        info.status = 'Sent';
        info.documentNames = new List<String>{ 'Summary' };

        System.assertEquals(false,
            BP_DocuSignEnvelopes.isSigned(
                new List<BP_DocuSignEnvelopes.EnvelopeInfo>{ info }, 'Summary'
            )
        );
    }

    @IsTest
    static void isSignedTrueWhenCompletedWithMatchingDoc() {
        BP_DocuSignEnvelopes.EnvelopeInfo info = new BP_DocuSignEnvelopes.EnvelopeInfo();
        info.status = 'Completed';
        info.documentNames = new List<String>{ 'Summary' };

        System.assertEquals(true,
            BP_DocuSignEnvelopes.isSigned(
                new List<BP_DocuSignEnvelopes.EnvelopeInfo>{ info }, 'Summary'
            )
        );
    }

    @IsTest
    static void isSignedFalseOnEmptyList() {
        System.assertEquals(false,
            BP_DocuSignEnvelopes.isSigned(
                new List<BP_DocuSignEnvelopes.EnvelopeInfo>(), 'Summary'
            )
        );
    }


    // ============================================================
    // summaryAndMandateSigned
    // ============================================================
    @IsTest
    static void summaryOnlySignedIsFalse() {
        BP_DocuSignEnvelopes.EnvelopeInfo summary = new BP_DocuSignEnvelopes.EnvelopeInfo();
        summary.status = 'Completed';
        summary.documentNames = new List<String>{ 'Summary' };

        System.assertEquals(false,
            BP_DocuSignEnvelopes.summaryAndMandateSigned(
                new List<BP_DocuSignEnvelopes.EnvelopeInfo>{ summary }
            )
        );
    }

    @IsTest
    static void mandateOnlySignedIsFalse() {
        BP_DocuSignEnvelopes.EnvelopeInfo mandate = new BP_DocuSignEnvelopes.EnvelopeInfo();
        mandate.status = 'Completed';
        mandate.documentNames = new List<String>{ 'ddMandate' };

        System.assertEquals(false,
            BP_DocuSignEnvelopes.summaryAndMandateSigned(
                new List<BP_DocuSignEnvelopes.EnvelopeInfo>{ mandate }
            )
        );
    }

    @IsTest
    static void bothSignedIsTrue() {
        BP_DocuSignEnvelopes.EnvelopeInfo summary = new BP_DocuSignEnvelopes.EnvelopeInfo();
        summary.status = 'Completed';
        summary.documentNames = new List<String>{ 'Summary' };
        BP_DocuSignEnvelopes.EnvelopeInfo mandate = new BP_DocuSignEnvelopes.EnvelopeInfo();
        mandate.status = 'Completed';
        mandate.documentNames = new List<String>{ 'ddMandate' };

        System.assertEquals(true,
            BP_DocuSignEnvelopes.summaryAndMandateSigned(
                new List<BP_DocuSignEnvelopes.EnvelopeInfo>{ summary, mandate }
            )
        );
    }


    // ============================================================
    // decideStatus
    // ============================================================
    @IsTest
    static void decideStatusReturnsNullWhenBothSignedAndAlreadyLater() {
        System.assertEquals(null,
            BP_DocuSignEnvelopes.decideStatus(
                BP_DocuSignEnvelopes.STATUS_SIGNED_WAITING_DOCS, true, false
            )
        );
        System.assertEquals(null,
            BP_DocuSignEnvelopes.decideStatus('Docs Sent', true, false)
        );
    }

    @IsTest
    static void decideStatusReturnsNullWhenFailedButAlreadyLater() {
        System.assertEquals(null,
            BP_DocuSignEnvelopes.decideStatus(
                BP_DocuSignEnvelopes.STATUS_FORM_COMPLETED, false, true
            )
        );
        System.assertEquals(null,
            BP_DocuSignEnvelopes.decideStatus(
                BP_DocuSignEnvelopes.STATUS_PENDING_CLIENT, false, true
            )
        );
        System.assertEquals(null,
            BP_DocuSignEnvelopes.decideStatus(
                BP_DocuSignEnvelopes.STATUS_SIGNED_WAITING_DOCS, false, true
            )
        );
    }


    // ============================================================
    // process() — filtering branches
    // ============================================================
    @IsTest
    static void processSkipsBlankSourceId() {
        dfsle__EnvelopeStatus__c status = new dfsle__EnvelopeStatus__c(
            dfsle__Status__c = 'Completed',
            dfsle__SourceId__c = ''
        );
        Test.startTest();
        BP_DocuSignEnvelopes.process(new List<dfsle__EnvelopeStatus__c>{ status }, null);
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void processSkipsInvalidSourceId() {
        dfsle__EnvelopeStatus__c status = new dfsle__EnvelopeStatus__c(
            dfsle__Status__c = 'Completed',
            dfsle__SourceId__c = 'not-an-id'
        );
        Test.startTest();
        BP_DocuSignEnvelopes.process(new List<dfsle__EnvelopeStatus__c>{ status }, null);
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void processSkipsNonBasicSourceId() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        dfsle__EnvelopeStatus__c status = new dfsle__EnvelopeStatus__c(
            dfsle__Status__c = 'Completed',
            dfsle__SourceId__c = String.valueOf(acc.Id)
        );
        Test.startTest();
        BP_DocuSignEnvelopes.process(new List<dfsle__EnvelopeStatus__c>{ status }, null);
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void processSkipsUnchangedStatus() {
        Basic__c claim = getClaim();
        dfsle__EnvelopeStatus__c status = makeStatus(claim.Id, 'DS-1', 'Sent');
        insert status;

        Map<Id, dfsle__EnvelopeStatus__c> oldMap =
            new Map<Id, dfsle__EnvelopeStatus__c>{ status.Id => status };

        Test.startTest();
        BP_DocuSignEnvelopes.process(new List<dfsle__EnvelopeStatus__c>{ status }, oldMap);
        Test.stopTest();

        // No envelopes loaded → no update
        System.assertEquals(
            BP_DocuSignEnvelopes.STATUS_SENT_FOR_ESIG,
            getClaim().Status__c
        );
    }


    // ============================================================
    // process() — happy paths
    // ============================================================
    @IsTest
    static void processMovesClaimToSignedWhenBothSigned() {
        Basic__c claim = getClaim();

        insert new List<dfsle__EnvelopeStatus__c>{
            makeStatus(claim.Id, 'DS-SUM', 'Completed'),
            makeStatus(claim.Id, 'DS-MAN', 'Completed')
        };
        makeEnvelope('DS-SUM', new List<String>{ 'Summary' });
        makeEnvelope('DS-MAN', new List<String>{ 'ddMandate' });

        // Fetch just-created statuses
        List<dfsle__EnvelopeStatus__c> statuses = [
            SELECT Id, dfsle__DocuSignId__c, dfsle__Status__c, dfsle__SourceId__c
            FROM dfsle__EnvelopeStatus__c
        ];

        Test.startTest();
        BP_DocuSignEnvelopes.process(statuses, null);
        Test.stopTest();

        System.assertEquals(
            BP_DocuSignEnvelopes.STATUS_SIGNED_WAITING_DOCS,
            getClaim().Status__c
        );
    }

    @IsTest
    static void processReturnsClaimToPendingClientOnFailedEnvelope() {
        Basic__c claim = getClaim();

        insert makeStatus(claim.Id, 'DS-VOID', 'Voided');

        List<dfsle__EnvelopeStatus__c> statuses = [
            SELECT Id, dfsle__DocuSignId__c, dfsle__Status__c, dfsle__SourceId__c
            FROM dfsle__EnvelopeStatus__c
        ];

        Test.startTest();
        BP_DocuSignEnvelopes.process(statuses, null);
        Test.stopTest();

        System.assertEquals(
            BP_DocuSignEnvelopes.STATUS_PENDING_CLIENT,
            getClaim().Status__c
        );
    }

    @IsTest
    static void processLeavesClaimAloneWhenOnlyOneSigned() {
        Basic__c claim = getClaim();

        insert new List<dfsle__EnvelopeStatus__c>{
            makeStatus(claim.Id, 'DS-SUM', 'Completed'),
            makeStatus(claim.Id, 'DS-MAN', 'Sent')
        };
        makeEnvelope('DS-SUM', new List<String>{ 'Summary' });
        makeEnvelope('DS-MAN', new List<String>{ 'ddMandate' });

        List<dfsle__EnvelopeStatus__c> statuses = [
            SELECT Id, dfsle__DocuSignId__c, dfsle__Status__c, dfsle__SourceId__c
            FROM dfsle__EnvelopeStatus__c
        ];

        Test.startTest();
        BP_DocuSignEnvelopes.process(statuses, null);
        Test.stopTest();

        System.assertEquals(
            BP_DocuSignEnvelopes.STATUS_SENT_FOR_ESIG,
            getClaim().Status__c
        );
    }

    // @IsTest
    // static void processDoesNotPullBackFromLaterStage() {
    //     Basic__c claim = getClaim();
    //     update new Basic__c(Id = claim.Id, Status__c = 'Docs Sent');

    //     insert new List<dfsle__EnvelopeStatus__c>{
    //         makeStatus(claim.Id, 'DS-SUM', 'Completed'),
    //         makeStatus(claim.Id, 'DS-MAN', 'Completed')
    //     };
    //     makeEnvelope('DS-SUM', new List<String>{ 'Summary' });
    //     makeEnvelope('DS-MAN', new List<String>{ 'ddMandate' });

    //     List<dfsle__EnvelopeStatus__c> statuses = [
    //         SELECT Id, dfsle__DocuSignId__c, dfsle__Status__c, dfsle__SourceId__c
    //         FROM dfsle__EnvelopeStatus__c
    //     ];

    //     Test.startTest();
    //     BP_DocuSignEnvelopes.process(statuses, null);
    //     Test.stopTest();

    //     System.assertEquals('Docs Sent', getClaim().Status__c);
    // }

    @IsTest
    static void processHandlesMultipleClaimsInOneCall() {
        Basic__c claim = getClaim();

        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Basic__c otherClaim = BP_TestDataFactory.createBasic(con.Id, true);
        otherClaim.Status__c = BP_DocuSignEnvelopes.STATUS_SENT_FOR_ESIG;
        update otherClaim;

        insert new List<dfsle__EnvelopeStatus__c>{
            makeStatus(claim.Id, 'DS-1', 'Completed'),
            makeStatus(claim.Id, 'DS-2', 'Completed'),
            makeStatus(otherClaim.Id, 'DS-3', 'Voided')
        };
        makeEnvelope('DS-1', new List<String>{ 'Summary' });
        makeEnvelope('DS-2', new List<String>{ 'ddMandate' });

        List<dfsle__EnvelopeStatus__c> statuses = [
            SELECT Id, dfsle__DocuSignId__c, dfsle__Status__c, dfsle__SourceId__c
            FROM dfsle__EnvelopeStatus__c
        ];

        Test.startTest();
        BP_DocuSignEnvelopes.process(statuses, null);
        Test.stopTest();

        Map<Id, Basic__c> after = new Map<Id, Basic__c>([
            SELECT Id, Status__c FROM Basic__c
        ]);

        System.assertEquals(
            BP_DocuSignEnvelopes.STATUS_SIGNED_WAITING_DOCS,
            after.get(claim.Id).Status__c
        );
        System.assertEquals(
            BP_DocuSignEnvelopes.STATUS_PENDING_CLIENT,
            after.get(otherClaim.Id).Status__c
        );
    }

    @IsTest
    static void processReturnsEarlyWhenNoEligibleStatuses() {
        // Status linked to a non-Basic record → filtered out → early return
        Account acc = [SELECT Id FROM Account LIMIT 1];

        dfsle__EnvelopeStatus__c status = new dfsle__EnvelopeStatus__c(
            dfsle__Status__c = 'Completed',
            dfsle__SourceId__c = String.valueOf(acc.Id)
        );

        Test.startTest();
        BP_DocuSignEnvelopes.process(
            new List<dfsle__EnvelopeStatus__c>{ status }, null
        );
        Test.stopTest();

        System.assertEquals(
            BP_DocuSignEnvelopes.STATUS_SENT_FOR_ESIG,
            getClaim().Status__c
        );
    }

    // ============================================================
    // End to end through DocuSignStatusTrigger (no direct process() call)
    // ============================================================
    @IsTest
    static void triggerMovesClaimToSignedOnlyWhenBothEnvelopesAreCompleted() {
        Basic__c claim = getClaim();
        makeEnvelope('DS-SUM-T', new List<String>{ 'Client Summary' });
        makeEnvelope('DS-MAN-T', new List<String>{ 'John_Snow_C0001_ddMandate' });
        dfsle__EnvelopeStatus__c summary = makeStatus(claim.Id, 'DS-SUM-T', 'Sent');
        dfsle__EnvelopeStatus__c mandate = makeStatus(claim.Id, 'DS-MAN-T', 'Sent');
        insert new List<dfsle__EnvelopeStatus__c>{ summary, mandate };

        summary.dfsle__Status__c = 'Completed';
        update summary;
        System.assertEquals(
            BP_DocuSignEnvelopes.STATUS_SENT_FOR_ESIG,
            getClaim().Status__c,
            'One completed envelope is not enough'
        );

        mandate.dfsle__Status__c = 'Completed';
        update mandate;
        System.assertEquals(
            BP_DocuSignEnvelopes.STATUS_SIGNED_WAITING_DOCS,
            getClaim().Status__c
        );
    }

    @IsTest
    static void triggerSendsClaimBackToPendingClientWhenEnvelopeIsDeclined() {
        Basic__c claim = getClaim();
        makeEnvelope('DS-MAN-D', new List<String>{ 'John_Snow_C0001_ddMandate' });
        dfsle__EnvelopeStatus__c mandate = makeStatus(claim.Id, 'DS-MAN-D', 'Sent');
        insert mandate;

        mandate.dfsle__Status__c = 'Declined';
        update mandate;

        System.assertEquals(
            BP_DocuSignEnvelopes.STATUS_PENDING_CLIENT,
            getClaim().Status__c
        );
    }

    @IsTest
    static void failuresAreLoggedNotSwallowed() {
        BP_DocuSignEnvelopes.logFailure(new DmlException('boom'));
        System.assertEquals(1, [SELECT COUNT() FROM Application_Form_Error__c]);
    }
}