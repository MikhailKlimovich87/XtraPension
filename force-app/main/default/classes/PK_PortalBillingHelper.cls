public with sharing class PK_PortalBillingHelper {
    public static Map<String, Object> getBillingInfo(PK_RequestWrappers.RecordDataWrapper wrapper) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (wrapper == null || wrapper.id == null) {
                result.put('status', 'error');
                result.put('message', 'Application Id is null');
                return result;
            }
            List<Application__c> apps = PK_PortalUtils.getApplication(wrapper?.id);
            if (apps.size() == 0) {
                result.put('status', 'error');
                result.put('message', 'Not found application');
            } else {
                result.put('status', 'success');
                result.put(
                    'application',
                    new PK_ResponseWrappers.BillingDataWrapper(apps[0])
                );
                return result;
            }
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() + '-' + e.getMessage());
        }
        return result;
    }

    public static Map<String, Object> getReceipt(PK_RequestWrappers.RecordDataWrapper wrapper) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (wrapper == null || wrapper.id == null) {
                result.put('status', 'error');
                result.put('message', 'Payment Id is null');
                return result;
            }
            String receiptBody = PK_PortalUtils.getReceipt(wrapper?.id);
            if (String.isBlank(receiptBody)) {
                result.put('status', 'error');
                result.put('message', 'Not found receipt');
            } else {
                result.put('status', 'success');
                result.put(
                    'receipt',
                    receiptBody
                );
                return result;
            }
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() + '-' + e.getMessage());
        }
        return result;
    }
}