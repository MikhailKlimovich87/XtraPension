/**
 * AA_FeeInstallmentChargeQueueable — async wrapper that charges due
 * AA_Fee_Installment__c rows via GoCardless.
 *
 * Split out of AA_FeeInstallmentScheduler on 2026-09-02 (audit critical
 * #1/#2): synchronous Web-service callouts are banned in Schedulable context,
 * so the scheduler hands the charging step to this
 * Queueable(Database.AllowsCallouts), mirroring AA_GoCardlessMandateQueueable.
 *
 * chargeDue() charges up to CHUNK rows per transaction with
 * callouts-FIRST-then-DML (audit #15). One chunk per daily sweep is far beyond
 * real volume (a plan is <=3 installments and only those due TODAY are charged);
 * any overflow drains on the next daily sweep. No self-chaining — that keeps
 * the class fully testable and removes any risk of a runaway chain.
 *
 * chargeDue() catches per-installment errors internally, so an exception out of
 * this method means a catastrophic query/DML failure — it is intentionally NOT
 * swallowed: the async job fails loudly (Apex Jobs log + admin notification)
 * rather than a fee sweep silently doing nothing.
 */
public with sharing class AA_FeeInstallmentChargeQueueable implements Queueable, Database.AllowsCallouts {
    private final Date today;

    public AA_FeeInstallmentChargeQueueable(Date today) {
        this.today = today;
    }

    public void execute(QueueableContext ctx) {
        AA_FeeInstallmentScheduler.ChargeResult cr =
            AA_FeeInstallmentScheduler.chargeDue(this.today);
        System.debug(LoggingLevel.INFO,
            'AA_FeeInstallmentChargeQueueable — fired=' + cr.fired +
            ' errored=' + cr.errored + ' due=' + cr.due);
    }
}