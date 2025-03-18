global class SchedulePayment implements Schedulable {
    global void execute(SchedulableContext sc) {
        SchedulePaymentBatch paymentBatch = new SchedulePaymentBatch();
        Id batchJobId = Database.executeBatch(paymentBatch, 1);
    }
}