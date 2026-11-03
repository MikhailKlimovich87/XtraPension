public class CurrencyRateScheduler implements Schedulable {
    public void execute(SchedulableContext ctx) {
        CurrencyRateFetcher.updateRates();
    }
}