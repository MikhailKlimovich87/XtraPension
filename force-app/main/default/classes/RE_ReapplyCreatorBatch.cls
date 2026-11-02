public without sharing class RE_ReapplyCreatorBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {
    public RE_ReapplyCreatorBatch() {}

    public Database.QueryLocator start(Database.BatchableContext BC) {
        return Database.getQueryLocator([
            SELECT
                Name,
                Status__c,
                (SELECT Id FROM Reapplies__r) 
            FROM Application__c 
            WHERE (Status__c = 'No Annual' 
                OR Status__c = 'Annual Service' 
                OR Status__c = 'Pension Keeper') 
            AND Id NOT IN (SELECT Application__c FROM Reapply__c)
        ]);
    }


    public void execute(Database.BatchableContext BC, List<Application__c> apps) {
        if (apps.size() == 0) {
            return;
        }
        // Query the standard field history for these Applications,
        // filtered to the Status__c field only, newest first.
        List<Application__History> histories = [
            SELECT Id, ParentId, Field, OldValue, NewValue, CreatedDate
            FROM Application__History
            WHERE ParentId IN :new Map<Id, Application__c>(apps).keySet()
              AND Field = 'Status__c'
            ORDER BY ParentId, CreatedDate DESC
        ];

        // Keep only the most recent Status__c change per Application
        Map<Id, String> latestHistoryStatusByAppId = new Map<Id, String>();
        Map<Id, Datetime> latestHistoryDateByAppId = new Map<Id, Datetime>();
        for (Application__History h : histories) {
            if (!latestHistoryStatusByAppId.containsKey(h.ParentId)) {
                latestHistoryStatusByAppId.put(
                    h.ParentId,
                    h.NewValue == null ? null : String.valueOf(h.NewValue)
                );
                latestHistoryDateByAppId.put(h.ParentId, h.CreatedDate);
            }
        }

        processApplications(apps, latestHistoryStatusByAppId, latestHistoryDateByAppId);
    }

    @TestVisible
    private static void processApplications(
        List<Application__c> apps,
        Map<Id, String> latestHistoryStatusByAppId,
        Map<Id, Datetime> latestHistoryDateByAppId
    ) {
        Date cutoffDate = Date.today().addMonths(-1);
        Set<Id> qualifiedApplicationIds = new Set<Id>();

        for (Application__c app : apps) {
            // No history record for Status__c -> skip
            if (!latestHistoryStatusByAppId.containsKey(app.Id)) {
                continue;
            }

            // Confirm the history's NewValue matches the Application's CURRENT status.
            // This ensures we're looking at the change that produced the current status,
            // not an older status the record has since moved on from.
            if (latestHistoryStatusByAppId.get(app.Id) != app.Status__c) {
                continue;
            }

            // Check the change happened 45+ days ago
            Datetime historyDate = latestHistoryDateByAppId.get(app.Id);
            if (historyDate != null && historyDate.date() <= cutoffDate) {
                qualifiedApplicationIds.add(app.Id);
            }
        }

        if (qualifiedApplicationIds.size() == 0) {
            return;
        }
        for (Id appId : qualifiedApplicationIds) {
            try {
                RE_ApplicationDataAction.createRelatedReapply(appId, true);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Failed for ' + appId + ': ' + e.getMessage());
            }
        }
    }

    public void finish(Database.BatchableContext BC) {
        Database.executeBatch(new RE_NoAnnualEmailBatch(' AND CreatedFromReapplyCreatorBatch__c = true'), 1);
        Database.executeBatch(new RE_PensionKeeperEmailBatch(' AND CreatedFromReapplyCreatorBatch__c = true'), 1);
    }
}