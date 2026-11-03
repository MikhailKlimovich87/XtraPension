public class BP_GenerateZipArchiveQueueable implements Queueable, Database.AllowsCallouts {

    private String basicId;

    public BP_GenerateZipArchiveQueueable(String basicId) {
        this.basicId = basicId;
    }

    public void execute(QueueableContext context) {
        if(!Test.isRunningTest()) {
            BP_PortalUtils.generateZipArchiveAfterCreatedClaim(basicId);
        }
        
    }
}