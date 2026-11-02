public class BP_GenerateEnvelopeQueueable implements Queueable, Database.AllowsCallouts {

    private String basicId;

    public BP_GenerateEnvelopeQueueable(String basicId) {
        this.basicId = basicId;
    }

    public void execute(QueueableContext context) {

        BP_GeneratePdfFileController.generateSignature(basicId);
        BP_ClientSummaryPdfService.generatePink(basicId);
        BP_ClientSummaryPdfService.generateYellow(basicId);
        BP_ClientSummaryPdfService.generateDWP(basicId);
        BP_ClientSummaryPdfService.generateNotes(basicId);
        
    }
}