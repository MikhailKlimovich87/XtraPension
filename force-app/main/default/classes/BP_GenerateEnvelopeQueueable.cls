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

        // The Stage 1 pack (the big envelope: signature pages, pink, yellow, DWP authority, payment notes) goes to the
        // printing house right after the Short Form: it only carries the client's name, C number and address, so it
        // does not wait for the long form (Fernando, 11/11/2026: only the DocuSign waits for a complete claim).
        // Before 10/11/2026 the ZIP was only built after "Send to Validation", so C05500's pack never went.
        if (!Test.isRunningTest()) {
            System.enqueueJob(new BP_GenerateZipArchiveQueueable(basicId, true));
        }
    }
}