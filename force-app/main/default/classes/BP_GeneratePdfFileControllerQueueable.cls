public with sharing class BP_GeneratePdfFileControllerQueueable implements Queueable,Database.AllowsCallouts {

    private String basicId;

    public BP_GeneratePdfFileControllerQueueable(String basicId) {
        this.basicId = basicId;
    }

    public void execute(QueueableContext context) {
        Map<String,Object> objMap = BP_GeneratePdfFileController.getApplication(basicId);
        BP_ClientSummaryPdfService.generatePdf(basicId); 
        if(!Test.isRunningTest()) {
            System.enqueueJob(
                new BP_GenerateDirectDebitQueueable(basicId)
            );
        }
    }
}