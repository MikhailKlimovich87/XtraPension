public class AppsStatusCountReportController {
    private final static List<String> APPLICATION_STATUSES = new List<String>{
        'Form In Progress',
        'Form Completed',
        'NINO/Doc Needed',
        'Pending Client',
        'Fix',
        'Agent Check',
        'QC Approved',
        'Sent for eSignature',
        'Signed',
        'Printing House',
        'Posted',
        'HMRC Reply 1',
        'XP Letter Sent',
        'HMRC Reply 2',
        'REPEAT(edits)',
        'REPEAT(NO edits)',
        'Send to Client',
        'Agent Call',
        'Charge CC',
        'Annual Service',
        'No Annual',
        'Closed',
        'Deposit Refund',
        'Deferred'
    };
    @AuraEnabled(cacheable=true)
    public static StatusDataCounter getAppStatusCount() {
        StatusDataCounter result = new StatusDataCounter();
        List<AggregateResult> groupStatusApp = [
            SELECT
                Status__c,
                COUNT(Id)
            FROM Application__c
            GROUP BY Status__c
        ];
        if (groupStatusApp.isEmpty()) {
            return null;
        }
        Map<String, StatusDataWrapper> statusNameByStatusDataWrapper = new Map<String, StatusDataWrapper>();
        for (AggregateResult aggregateResult : groupStatusApp) {
            statusNameByStatusDataWrapper.put(
                (String)aggregateResult.get('Status__c'),
                new StatusDataWrapper((String)aggregateResult.get('Status__c'), (Integer)aggregateResult.get('expr0'))
            );
        }
        for (String status : APPLICATION_STATUSES) {
            StatusDataWrapper currentWrapper = statusNameByStatusDataWrapper.get(status);
            if (currentWrapper != null) {
                result.statusData.add(currentWrapper);
            } else {
                result.statusData.add(
                    new StatusDataWrapper(status, 0)
                );
            }
        }
        System.debug('result ==== ' + result);
        return result;
    }

    public class StatusDataCounter {
        @AuraEnabled
        public List<StatusDataWrapper> statusData = new List<StatusDataWrapper>();
    }

    public class StatusDataWrapper {
        @AuraEnabled
        public String statusName{get; set;}
        @AuraEnabled
        public Integer count{get; set;}

        StatusDataWrapper(String name, Integer countRecords) {
            statusName = name;
            count = countRecords;
        }

        StatusDataWrapper() {}
    }
}