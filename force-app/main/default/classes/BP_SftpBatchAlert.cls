/**
 * Collects per-claim failures of the claim SFTP batches and, in finish(), raises one alert
 * (an Application_Form_Error__c record, which e-mails the admins) so a failed upload is not silent.
 */
public class BP_SftpBatchAlert {

    private final String batchName;
    private final List<String> failures = new List<String>();

    public BP_SftpBatchAlert(String batchName) {
        this.batchName = batchName;
    }

    public void addFailure(Basic__c claim, String reason) {
        failures.add(claim.Name + ' (' + claim.Id + '): ' + (reason == null ? 'unknown error' : reason.abbreviate(300)));
    }

    public Integer failureCount() {
        return failures.size();
    }

    public void send() {
        if (failures.isEmpty()) {
            return;
        }
        try {
            insert new Application_Form_Error__c(
                Error_Body__c = batchName + ' finished with ' + failures.size() + ' failed upload(s):\n' + String.join(failures, '\n'),
                Error_Date__c = Date.today()
            );
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, batchName + ' alert could not be created: ' + ex.getMessage());
        }
    }
}