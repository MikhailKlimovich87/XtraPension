public class BP_GenerateDirectDebitQueueable
    implements Queueable, Database.AllowsCallouts {

    private String basicId;

    public BP_GenerateDirectDebitQueueable(String basicId) {
        this.basicId = basicId;
    }

    public void execute(QueueableContext context) {

        if(!Test.isRunningTest()){BP_DirectDebitManadatePdfService.generatePdf(basicId);}

        if(!Test.isRunningTest()){System.enqueueJob( new BP_GenerateZipArchiveQueueable(basicId) );}
    }
}