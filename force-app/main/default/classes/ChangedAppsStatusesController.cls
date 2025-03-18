public class ChangedAppsStatusesController {
    private final static Map<String,String> CHANGED_STATUS_DATE_FIELDS = new Map<String, String>{
        'Form In Progress'    => 'CreatedDate',
        'Form Completed'      => 'Form_Completed_Change_Date__c',
        'NINO/Doc Needed'     => 'NINO_Doc_Needed_Changed_Date__c',
        'Pending Client'	  => 'Pending_Client_Send_SMS_Date__c',
        'Fix'                 => 'Fix_Changed_Date__c',
        'Agent Check'         => 'Agent_Check_Changed_Date__c',
        'QC Approved'	      => 'QC_Approved_Changed_Date__c',
        'Sent for eSignature' => 'Sent_for_eSignature_Changed_Date__c',
        'Signed'              => 'Signed_Changed_Date__c',
        'Printing House'      => 'Printing_House_Changed_Date__c',
        'Posted'              => 'Posted_Changed_Date__c',
        'HMRC Reply 1'        => 'HMRC_Reply_1_Changed_Date__c',
        'XP Letter Sent'      => 'XP_Letter_Sent_Changed_Date__c',
        'HMRC Reply 2'        => 'HMRC_Reply_2_Changed_Date__c',
        'REPEAT(edits)'       => 'Repeat_Change_Date__c',
        'REPEAT(NO edits)'    => 'Repeat_No_Edit_Changed_Date__c',
        'Send to Client'      => 'Send_to_Client_Changed_Date__c',
        'Agent Call'	      => 'Agent_Call_Changed_Date__c',
        'Charge CC'	          => 'Charge_CC_Changed_Date__c',
        'Annual Service'      => 'Annual_Service_Changed_Date__c',
        'No Annual'           => 'Closed_Won_Changed_Date__c',
        'Closed'              => 'Closed_Lost_Changed_Date__c',
        'Deposit Refund'      => 'Deposit_Refund_Changed_Date__c',
        'Deferred'            => 'Deferred_Changed_Date__c'
    };

    @AuraEnabled(cacheable=true)
    public static ApplicationStatusWrapper getAppsStatusChangedData(){
        ApplicationStatusWrapper appStatusData = new ApplicationStatusWrapper();
        StatusWrapper formCompletedStatus = new StatusWrapper();
        Map<String, StatusWrapper> appStatusNameByStatusWrapper = new Map<String, StatusWrapper>();
        for (String status : CHANGED_STATUS_DATE_FIELDS.keySet()) {
            appStatusNameByStatusWrapper.put(
                CHANGED_STATUS_DATE_FIELDS.get(status),
                new StatusWrapper(status)
            );
        }
        Date todayDate = Date.today();
        Date currentMonthStartDate = todayDate.toStartOfMonth();
        Date lastMonthStartDate = currentMonthStartDate.addMonths(-1);
        Date lastMonthEndDate = lastMonthStartDate.addMonths(1);
        Date currentWeekStartDate = todayDate.toStartOfWeek();
        Date lastWeekStartDate = currentWeekStartDate.addDays(-7);
        Date lastWeekEndDate = lastWeekStartDate.addDays(7);

        List<Application__c> changedStatusApps = [
            SELECT
                CreatedDate,
                Form_Completed_Change_Date__c,
                Agent_Check_Changed_Date__c,
                Quality_Control_Changed_Date__c,
                QC_Approved_Changed_Date__c,
                Sent_for_eSignature_Changed_Date__c,
                Signed_Changed_Date__c,
                Printing_House_Changed_Date__c,
                Posted_Changed_Date__c,
                HMRC_Reply_1_Changed_Date__c,
                XP_Letter_Sent_Changed_Date__c,
                HMRC_Reply_2_Changed_Date__c,
                Send_to_Client_Changed_Date__c,
                Agent_Call_Changed_Date__c,
                Charge_CC_Changed_Date__c,
                Annual_Service_Changed_Date__c,
                Closed_Won_Changed_Date__c,
                Closed_Lost_Changed_Date__c,
                Deposit_Refund_Changed_Date__c,
                NINO_Doc_Needed_Changed_Date__c,
                Deferred_Changed_Date__c,
                Repeat_Change_Date__c,
                Repeat_No_Edit_Changed_Date__c,
                Fix_Changed_Date__c,
                Pending_Client_Send_SMS_Date__c
            FROM Application__c
            WHERE
                CreatedDate >= :lastMonthStartDate OR
                Form_Completed_Change_Date__c >= :lastMonthStartDate OR
                Agent_Check_Changed_Date__c >= :lastMonthStartDate OR
                Quality_Control_Changed_Date__c >= :lastMonthStartDate OR
                QC_Approved_Changed_Date__c >= :lastMonthStartDate OR
                Sent_for_eSignature_Changed_Date__c >= :lastMonthStartDate OR
                Signed_Changed_Date__c >= :lastMonthStartDate OR
                Printing_House_Changed_Date__c >= :lastMonthStartDate OR
                Posted_Changed_Date__c >= :lastMonthStartDate OR
                HMRC_Reply_1_Changed_Date__c >= :lastMonthStartDate OR
                XP_Letter_Sent_Changed_Date__c >= :lastMonthStartDate OR
                HMRC_Reply_2_Changed_Date__c >= :lastMonthStartDate OR
                Send_to_Client_Changed_Date__c >= :lastMonthStartDate OR
                Agent_Call_Changed_Date__c >= :lastMonthStartDate OR
                Charge_CC_Changed_Date__c >= :lastMonthStartDate OR
                Annual_Service_Changed_Date__c >= :lastMonthStartDate OR
                Closed_Won_Changed_Date__c >= :lastMonthStartDate OR
                Closed_Lost_Changed_Date__c >= :lastMonthStartDate OR
                Deposit_Refund_Changed_Date__c >= :lastMonthStartDate OR
                NINO_Doc_Needed_Changed_Date__c >= :lastMonthStartDate OR
                Deferred_Changed_Date__c >= :lastMonthStartDate OR
                Repeat_Change_Date__c >= :lastMonthStartDate OR
                Repeat_No_Edit_Changed_Date__c >= :lastMonthStartDate OR
                Fix_Changed_Date__c >= :lastMonthStartDate OR
                Pending_Client_Send_SMS_Date__c >= :lastMonthStartDate
        ];
        if (changedStatusApps.isEmpty()) return null;
        for (Application__c application : changedStatusApps) {
            for (String fieldName : CHANGED_STATUS_DATE_FIELDS.values()) {
                Date currentValue;
                if (fieldName == 'CreatedDate') {
                    Datetime createdDate = (Datetime)application.get(fieldName);
                    currentValue = createdDate.date();
                } else {
                    currentValue = (Date)application.get(fieldName);
                }
                StatusWrapper currentStatusWrapper = appStatusNameByStatusWrapper.get(fieldName);
                if (currentValue != null && currentValue >= currentWeekStartDate && currentValue <= todayDate) {
                    currentStatusWrapper.quantityPerThisWeek += 1;
                }
                if (currentValue != null && currentValue >= lastWeekStartDate && currentValue < lastWeekEndDate) {
                    currentStatusWrapper.quantityPerLastWeek += 1;
                }
                if (currentValue != null && currentValue >= currentMonthStartDate && currentValue <= todayDate) {
                    currentStatusWrapper.quantityPerCurrentMonth += 1;
                }
                if (currentValue != null && currentValue >= lastMonthStartDate && currentValue < lastMonthEndDate) {
                    currentStatusWrapper.quantityPerLastMonth += 1;
                }
                appStatusNameByStatusWrapper.put(fieldName, currentStatusWrapper);
            }
        }
        for (String statusName : CHANGED_STATUS_DATE_FIELDS.keySet()) {
            StatusWrapper currentWrapper = appStatusNameByStatusWrapper.get(CHANGED_STATUS_DATE_FIELDS.get(statusName));
            if (currentWrapper == null) {
                currentWrapper = new StatusWrapper();
                currentWrapper.name = statusName;
                currentWrapper.quantityPerCurrentMonth = 0;
                currentWrapper.quantityPerLastMonth    = 0;
                currentWrapper.quantityPerLastWeek     = 0;
                currentWrapper.quantityPerThisWeek     = 0;
            }
            appStatusData.statusData.add(currentWrapper);
        }
        return appStatusData;
    }

    public class ApplicationStatusWrapper {
        @AuraEnabled
        public List<StatusWrapper> statusData = new List<StatusWrapper>();
    }

    public class StatusWrapper {
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Integer quantityPerThisWeek = 0;
        @AuraEnabled
        public Integer quantityPerLastWeek = 0;
        @AuraEnabled
        public Integer quantityPerCurrentMonth = 0;
        @AuraEnabled
        public Integer quantityPerLastMonth = 0;

        public StatusWrapper(String name) {
            this.name = name;
        }

        public StatusWrapper() {}
    }
}