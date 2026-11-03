public class PK_HowToBuyMoreYearsScheduler implements Schedulable {
    public void execute(SchedulableContext ctx) {
        PK_HowToBuyMoreYearsBatch batch = new PK_HowToBuyMoreYearsBatch();
        Database.executeBatch(batch, 1);
    }
}