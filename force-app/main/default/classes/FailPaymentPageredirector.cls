public class FailPaymentPageredirector {
    public final String PAYMENT_URL = XtraPension_Data__c.getInstance().Phone_payment_URL__c;
    public String paymentId {get; set;}


    public FailPaymentPageredirector(ApexPages.StandardController Controller) {
        paymentId = ApexPages.currentPage().getParameters().get('id');
    }

    public PageReference doRedirectAction() {
        PageReference retURL = new PageReference(PAYMENT_URL + paymentId);
        retURL.setRedirect(true);
        return retURL;
    }
}