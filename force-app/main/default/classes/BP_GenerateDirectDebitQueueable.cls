public class BP_GenerateDirectDebitQueueable
    implements Queueable, Database.AllowsCallouts {

    private String basicId;

    public BP_GenerateDirectDebitQueueable(String basicId) {
        this.basicId = basicId;
    }

    public void execute(QueueableContext context) {

        if(!Test.isRunningTest()){BP_DirectDebitManadatePdfService.generatePdf(basicId);}

        // The Stage 1 pack normally went out right after the Short Form: only build it here if it has not been sent,
        // otherwise the printing house would get (and post) it a second time.
        if(!Test.isRunningTest()){System.enqueueJob( new BP_GenerateZipArchiveQueueable(basicId, true) );}
    }
}