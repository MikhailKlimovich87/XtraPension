public with sharing class PK_AnnualPaymentBatch implements Database.Batchable<SObject> {
	private Date paymentDate;
	private Integer amount;
	private final String PENSION_KEEPER_PRODUCT = 'Pension Keeper';

	public PK_AnnualPaymentBatch(Date paymentDate, Integer paymentAmount) {
		this.paymentDate = paymentDate;
		this.amount      = paymentAmount;
	}

	public Database.QueryLocator start(Database.BatchableContext bc) {
		Date yearAgo = Date.today().addYears(-1);
		return Database.getQueryLocator([
			SELECT
				Id,
				Name,
				Email__c,
				First_Name__c,
				Second_Name__c,
				Contact__c,
				Payment_Method__c,
				CurrencyIsoCode,
				Current_Customer_Id__c,
				Stripe_Customer_Id__c
			FROM Application__c
			WHERE Status__c = 'Pension Keeper'
			AND PK_Portal_User_Active__c = true
			AND PK_Auto_Renewal__c = true
			AND PK_Registration_Date__c = :yearAgo
		]);
	}

	public void execute(Database.BatchableContext bc, List<Application__c> apps) {
		if (apps.isEmpty()) return;

		Set<Id> appIds = new Set<Id>();
		Set<String> currencies = new Set<String>();
		for (Application__c app : apps) {
			appIds.add(app.Id);
			if (String.isNotBlank(app.CurrencyIsoCode)) currencies.add(app.CurrencyIsoCode);
		}

		Set<Id> alreadyBilled = new Set<Id>();
		for (Payment__c p : [
			SELECT Application__c
			FROM Payment__c
			WHERE Application__c IN :appIds
			AND Pension_Keeper_Annual_Payment__c = true
			AND Payment_Date__c = :paymentDate
		]) {
			alreadyBilled.add(p.Application__c);
		}

		Map<String, Id> productIdByCurrency = new Map<String, Id>();
		for (PriceBookEntry pbe : [
			SELECT Product2Id, CurrencyIsoCode
			FROM PriceBookEntry
			WHERE Product2.Name = :PENSION_KEEPER_PRODUCT
			AND Pricebook2.IsStandard = true
			AND CurrencyIsoCode IN :currencies
		]) {
			productIdByCurrency.put(pbe.CurrencyIsoCode, pbe.Product2Id);
		}

		Map<Id, Id> orderIdByAppId = new Map<Id, Id>();
		for (Order o : [
			SELECT Id, Application__c
			FROM Order
			WHERE Application__c IN :appIds
			ORDER BY CreatedDate DESC
		]) {
			if (!orderIdByAppId.containsKey(o.Application__c)) {
				orderIdByAppId.put(o.Application__c, o.Id);
			}
		}

		List<Payment__c> toInsert = new List<Payment__c>();
		for (Application__c app : apps) {
			if (alreadyBilled.contains(app.Id)) continue;
			if (!productIdByCurrency.containsKey(app.CurrencyIsoCode)) continue;

			String methodId = '';
			if (String.isNotBlank(app.Payment_Method__c)) {
				List<String> parts = app.Payment_Method__c.split(';');
				methodId = parts[parts.size() - 1].trim();
			}

			toInsert.add(new Payment__c(
				Amount__c                        = amount,
				Product__c                       = productIdByCurrency.get(app.CurrencyIsoCode),
				Order__c                         = orderIdByAppId.get(app.Id),
				Status__c                        = 'Schedule',
				CurrencyIsoCode                  = app.CurrencyIsoCode,
				Payment_Method__c                = methodId,
				Customer_Id__c                   = String.isNotBlank(app.Current_Customer_Id__c)
													  ? app.Current_Customer_Id__c
													  : app.Stripe_Customer_Id__c,
				Application__c                   = app.Id,
				Payment_Date__c                  = paymentDate,
				Pension_Keeper_Annual_Payment__c = true
			));
		}

		if (!toInsert.isEmpty()) {
			Database.SaveResult[] results = Database.insert(toInsert, false);
		}
	}

	public void finish(Database.BatchableContext bc) {
		System.debug('PK_AnnualPaymentBatch completed');
	}
}