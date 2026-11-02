public without sharing class RE_ReapplySMSSendScheduler implements Schedulable{
    public void execute(SchedulableContext tc) {
        MassSendSmsBatch batch = new MassSendSmsBatch('See VERY IMPORTANT email we sent you about your HMRC reapplication. Call / Email / WhatsApp us if needed. XtraPension', ' AND Status__c = \'Pre Sale\' ');
        Database.executeBatch(batch , 1);
    }
}