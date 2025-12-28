public class CallFollowUpModuleController {

    @AuraEnabled
    public static Id logCall(String subject, Id relatedToId, Id whoId) {
        if (subject == null || relatedToId == null || whoId == null) {
            throw new AuraHandledException('Some of input parameters is blank!');
        }
        List<User> currUsers = [
            SELECT
                Id,
                FirstName
            FROM User
            WHERE Id = :whoId
        ];
        if (currUsers.size() == 0) throw new AuraHandledException('Didn\'t find any users!');
        Task newCall = new Task();
        newCall.Subject = subject + ' - Creator: ' + currUsers[0].FirstName;
        newCall.Status = 'Completed';
        newCall.ActivityDate = System.today();
        newCall.IsReminderSet = false;
        newCall.Type = 'Call';
        newCall.WhatId = relatedToId;

        try {
            insert newCall;
            return newCall.Id;
        } catch (DmlException e) {
            System.debug('Error logging call: ' + e.getMessage());
            throw new AuraHandledException('Error logging call: ' + e.getMessage());
        }
    }
}