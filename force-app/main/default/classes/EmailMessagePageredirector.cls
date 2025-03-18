public class EmailMessagePageredirector {
    public PageReference doRedirectAction() {
        List<ListView> messageListView = [
            SELECT
                Id
            FROM ListView
            WHERE Name = 'Received Emails'
        ];
        String url = URL.getOrgDomainUrl().toExternalForm() + '/lightning/o/EmailMessage';

        url += !messageListView.isEmpty() ? '/list?filterName=' + messageListView[0].Id : '';
        PageReference retURL = new PageReference(url);
        retURL.setRedirect(true);
        return retURL;
    }
}