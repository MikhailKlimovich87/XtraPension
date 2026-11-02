public class ExcelExportController {

    public List<Application__c> appList { get; set; }

    public ExcelExportController() {

        appList = new List<Application__c>();

        String requestId =
            ApexPages.currentPage()
                .getParameters()
                .get('requestId');

        System.debug('requestId ==== ' + requestId);

        if (!String.isBlank(requestId)) {

            List<Export_Request__c> exportRequests = [
                SELECT Application_Ids__c
                FROM Export_Request__c
                WHERE Id = :requestId
                LIMIT 1
            ];

            System.debug(
                'exportRequests ==== ' + exportRequests
            );

            if (!exportRequests.isEmpty()) {

                Export_Request__c exportReq =
                    exportRequests[0];

                if (!String.isBlank(
                    exportReq.Application_Ids__c
                )) {

                    List<Id> appIds =
                        new List<Id>();

                    for (
                        String idStr :
                        exportReq.Application_Ids__c
                            .split(',')
                    ) {

                        if (!String.isBlank(idStr)) {
                            appIds.add((Id)idStr);
                        }
                    }

                    if (!appIds.isEmpty()) {

                        Map<Id, Application__c> appsById =
                            new Map<Id, Application__c>([
                                SELECT
                                    Id,
                                    Email__c,
                                    Name,
                                    First_Name__c,
                                    Second_Name__c,
                                    Full_Current_Address_Abroad__c
                                FROM Application__c
                                WHERE Id IN :appIds
                            ]);

                        appList = new List<Application__c>();

                        // Preserve original order stored in Export_Request__c
                        for (Id appId : appIds) {

                            if (appsById.containsKey(appId)) {
                                appList.add(appsById.get(appId));
                            }
                        }
                    }
                }
            }
        }

        System.debug(
            'appList size ==== ' + appList.size()
        );
    }
}