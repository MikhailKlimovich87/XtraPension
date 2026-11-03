/**
 * Regenerates the whole document pack of a claim after its data changed, one step per transaction
 * (each step makes callouts, and a callout is not allowed once there is uncommitted DML):
 *   1. IPCBR1 + IPC1394 and the Client Summary
 *   2. wet-signature BR1 + IPC1394 (only if they already exist)
 *   3. Direct Debit mandate
 *   4. Stage 1 ZIP (only if it exists and has not been sent to the printing house yet)
 * The signed Summary / ddMandate copies are never touched (see the "completed" exclusion in the services).
 */
public class BP_RegeneratePackQueueable implements Queueable, Database.AllowsCallouts {

    private static final Integer LAST_STEP = 4;

    private Id claimId;
    private Integer step;

    public BP_RegeneratePackQueueable(Id claimId) {
        this(claimId, 1);
    }

    public BP_RegeneratePackQueueable(Id claimId, Integer step) {
        this.claimId = claimId;
        this.step = step;
    }

    public void execute(QueueableContext context) {
        try {
            if (step == 1) {
                BP_GeneratePdfFileController.getApplication(claimId);
                BP_ClientSummaryPdfService.generatePdf(claimId);
            } else if (step == 2 && hasDocument('%IPCBR1_Wet_Signature')) {
                BP_GeneratePdfFileController.generateSignature(claimId);
            } else if (step == 3) {
                BP_DirectDebitManadatePdfService.generatePdf(claimId);
            } else if (step == 4 && hasDocument('%Stage 1%') && isStage1NotSent()) {
                BP_PortalUtils.generateZipArchiveAfterCreatedClaim(claimId);
            }
        } catch (Exception ex) {
            insert new Application_Form_Error__c(
                Error_Body__c = 'Pack regeneration step ' + step + ' failed for claim ' + claimId + '\n' + ex.getMessage() + '\n' + ex.getStackTraceString(),
                Error_Date__c = Date.today()
            );
        }
        if (step < LAST_STEP && !Test.isRunningTest()) {
            System.enqueueJob(new BP_RegeneratePackQueueable(claimId, step + 1));
        }
    }

    private Boolean hasDocument(String titlePattern) {
        return ![
            SELECT Id FROM ContentDocumentLink
            WHERE LinkedEntityId = :claimId AND ContentDocument.Title LIKE :titlePattern
            LIMIT 1
        ].isEmpty();
    }

    private Boolean isStage1NotSent() {
        return [SELECT FTP_Claim_Created_Send_Date__c FROM Basic__c WHERE Id = :claimId].FTP_Claim_Created_Send_Date__c == null;
    }
}