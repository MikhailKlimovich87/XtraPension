public class BP_GenerateZipArchiveQueueable implements Queueable, Database.AllowsCallouts {

    private String basicId;
    // true on the automatic paths (after the Short Form and after Send to Validation): a Stage 1 pack that already
    // went to the printing house is not built again, so the printer never posts it twice. The "Redo a Form" button
    // calls BP_PortalUtils.generateZipArchiveAfterCreatedClaim directly and can still re-send on purpose.
    private Boolean onlyIfNotSent;
    // How many times this job went on to build the ZIP (tests only read it)
    @TestVisible
    private static Integer builds = 0;

    public BP_GenerateZipArchiveQueueable(String basicId) {
        this(basicId, false);
    }

    public BP_GenerateZipArchiveQueueable(String basicId, Boolean onlyIfNotSent) {
        this.basicId = basicId;
        this.onlyIfNotSent = onlyIfNotSent == true;
    }

    public void execute(QueueableContext context) {
        if (onlyIfNotSent && stage1AlreadySent(basicId)) {
            return;
        }
        builds++;
        if(!Test.isRunningTest()) {
            BP_PortalUtils.generateZipArchiveAfterCreatedClaim(basicId);
        }
    }

    @TestVisible
    private static Boolean stage1AlreadySent(String basicId) {
        // FOR UPDATE: the hourly upload (BP_SFTPZipFileEnvelupeBatch) waits for this transaction, so it cannot set the
        // send date between this check and the rebuild (which clears it) and get the pack posted twice.
        List<Basic__c> claims = [SELECT FTP_Claim_Created_Send_Date__c FROM Basic__c WHERE Id = :basicId LIMIT 1 FOR UPDATE];
        return !claims.isEmpty() && claims[0].FTP_Claim_Created_Send_Date__c != null;
    }
}