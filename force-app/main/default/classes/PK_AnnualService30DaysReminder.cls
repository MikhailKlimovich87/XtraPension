public with sharing class PK_AnnualService30DaysReminder
		implements Database.Batchable<SObject>, Database.AllowsCallouts {

	private static final String  TEMPLATE_NAME = 'PK 30 day Renewal Reminder';
	private static final String  OWD_ADDRESS   = 'keeper@xtrapension.com';
	private static final Integer DAYS_AHEAD    = 30;

	private static final String TOKEN_PAYMENT_DATE = '{PAYMENT_DATE}';
	private static final String TOKEN_ANNUAL_COST  = '{ANNUAL_COST}';
	private static final String TOKEN_CARD         = '{LAST4_CARD_NUMBERS}';

	private static final String TOKEN_FIRST_NAME   = '{!Application__c.First_Name__c}';
	private static final String TOKEN_UPDATE_LINK  = '{!Application__c.Update_Credit_Card_Link__c}';

	private static EmailTemplate       cachedTemplate;
	private static OrgWideEmailAddress cachedOwd;
	private static Map<String, String> cardCache = new Map<String, String>();

	public Database.QueryLocator start(Database.BatchableContext bc) {
		Date target = Date.today().addDays(DAYS_AHEAD);
		return Database.getQueryLocator([
			SELECT
				Name,
				Application__r.First_Name__c,
				Application__r.Email__c,
				Application__r.Contact__c,
				Application__r.Update_Credit_Card_Link__c,
				Application__c,
				Customer_Id__c,
				Payment_Method__c,
				Payment_Date__c,
				Amount__c,
				CurrencyIsoCode
			FROM Payment__c
			WHERE Status__c = 'Schedule'
			  AND Pension_Keeper_Annual_Payment__c = true
			  AND Payment_Date__c = :target
			  AND Application_Reminder_Sent_Date__c = null
		]);
	}

	public void execute(Database.BatchableContext bc, List<Payment__c> payments) {
		if (payments == null || payments.isEmpty()) return;

		for (Payment__c p : payments) {
			try {
				if (sendNotificationEmail(p)) {
					p.Application_Reminder_Sent_Date__c = Date.today();
				}
			} catch (Exception e) {
				System.debug(LoggingLevel.ERROR,
					'Reminder failed for ' + p.Id + ': ' + e.getMessage()
					+ ' | ' + e.getStackTraceString());
			}
		}

		List<Database.SaveResult> results = Database.update(payments, false);
		for (Integer i = 0; i < results.size(); i++) {
			Database.SaveResult sr = results[i];
			if (!sr.isSuccess()) {
				System.debug(LoggingLevel.ERROR,
					'Flag update failed for ' + payments[i].Id + ': ' + sr.getErrors());
			}
		}
	}

	public void finish(Database.BatchableContext bc) {
		System.debug(LoggingLevel.INFO, 'PK_AnnualService30DaysReminder completed');
	}

	private Boolean sendNotificationEmail(Payment__c payment) {
		if (payment == null
			|| payment.Application__c == null
			|| payment.Application__r.Contact__c == null
			|| String.isBlank(payment.Application__r.Email__c)) {
			System.debug('Skipping ' + (payment == null ? 'null' : payment.Id)
				+ ': missing application/contact/email');
			return false;
		}

		EmailTemplate tpl = getTemplate();
		OrgWideEmailAddress owd = getOwd();
		if (tpl == null || (owd == null && !Test.isRunningTest())) {
			System.debug('Skipping ' + payment.Id + ': missing template or OWD');
			return false;
		}

		Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
		msg.setTargetObjectId(payment.Application__r.Contact__c);
		msg.setWhatId(payment.Application__c);
		msg.setUseSignature(false);
		msg.setBccSender(false);
		msg.setSaveAsActivity(true);
		msg.setTreatTargetObjectAsRecipient(false);
		if (owd != null) {
			msg.setOrgWideEmailAddressId(owd.Id);
		}
		msg.setToAddresses(new List<String>{ payment.Application__r.Email__c });
		msg.setSubject(tpl.Subject);
		msg.setHtmlBody(parseData(payment, tpl.HtmlValue));

		Messaging.SendEmailResult[] results = Messaging.sendEmail(
			new List<Messaging.SingleEmailMessage>{ msg });

		if (results == null || results.isEmpty()) {
			return false;
		}
		if (!results[0].isSuccess()) {
			System.debug(LoggingLevel.ERROR,
				'sendEmail failed for ' + payment.Id + ': ' + results[0].getErrors());
			return false;
		}
		return true;
	}

	private EmailTemplate getTemplate() {
		if (cachedTemplate == null) {
			// BYPASS FOR TESTS: Cannot insert EmailTemplates in test context
			if (Test.isRunningTest()) {
				cachedTemplate = new EmailTemplate(
					Subject = 'Test Subject',
					HtmlValue = 'Hi {!Application__c.First_Name__c} Date: {PAYMENT_DATE} Cost: {ANNUAL_COST} Card: {LAST4_CARD_NUMBERS} Link: {!Application__c.Update_Credit_Card_Link__c}'
				);
				return cachedTemplate;
			}
			List<EmailTemplate> t = [
				SELECT Id, HtmlValue, Subject
				FROM EmailTemplate
				WHERE Name = :TEMPLATE_NAME
				WITH SYSTEM_MODE
				LIMIT 1
			];
			if (!t.isEmpty()) cachedTemplate = t[0];
		}
		return cachedTemplate;
	}

	private OrgWideEmailAddress getOwd() {
		if (cachedOwd == null) {
			// BYPASS FOR TESTS: Cannot insert OrgWideEmailAddresses in test context.
			// We return null and let the test bypass the OWD assignment.
			if (Test.isRunningTest()) {
				return null;
			}
			List<OrgWideEmailAddress> o = [
				SELECT Id
				FROM OrgWideEmailAddress
				WHERE Address = :OWD_ADDRESS
				WITH SYSTEM_MODE
				LIMIT 1
			];
			if (!o.isEmpty()) cachedOwd = o[0];
		}
		return cachedOwd;
	}

	private String getCardData(String paymentMethod) {
		if (String.isBlank(paymentMethod)) return 'Unknown';
		if (cardCache.containsKey(paymentMethod)) return cardCache.get(paymentMethod);

		String result = 'Unknown';
		try {
			StripeApiHandler.StripeAPIResponseWrapper res =
				StripeApiHandler.requestStripeApi('payment_methods/' + paymentMethod, 'GET', null);

			if (res != null && String.isNotBlank(res.responseBody)) {
				Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody);
				Map<String, Object> card = (Map<String, Object>) m.get('card');
				if (card != null && card.get('brand') != null && card.get('last4') != null) {
					result = card.get('brand') + ' - ' + card.get('last4');
				}
			}
		} catch (Exception e) {
			System.debug(LoggingLevel.ERROR, 'getCardData failed for ' + paymentMethod + ': ' + e.getMessage());
		}

		cardCache.put(paymentMethod, result);
		return result;
	}

	private String parseData(Payment__c p, String body) {
		if (String.isBlank(body)) return '';

		String dateStr = '';
		if (p.Payment_Date__c != null) {
			try { dateStr = p.Payment_Date__c.format(); } catch (Exception e) { dateStr = String.valueOf(p.Payment_Date__c); }
		}

		String amtStr = '';
		if (p.Amount__c != null) amtStr = formatAmountWithCurrency(p.Amount__c, p);

		String cardStr = '';
		if (body.contains(TOKEN_CARD)) cardStr = getCardData(p.Payment_Method__c);

		String firstName = (p.Application__r != null && p.Application__r.First_Name__c != null) ? p.Application__r.First_Name__c : '';

		String updateLinkHtml = buildUpdateLinkHtml(p.Application__r != null ? p.Application__r.Update_Credit_Card_Link__c : null);

		String result = body;
		if (result.contains(TOKEN_PAYMENT_DATE)) result = result.replace(TOKEN_PAYMENT_DATE, dateStr);
		if (result.contains(TOKEN_ANNUAL_COST)) result = result.replace(TOKEN_ANNUAL_COST, amtStr);
		if (result.contains(TOKEN_CARD)) result = result.replace(TOKEN_CARD, cardStr);
		if (result.contains(TOKEN_FIRST_NAME)) result = result.replace(TOKEN_FIRST_NAME, escapeHtml(firstName));
		if (result.contains(TOKEN_UPDATE_LINK)) result = result.replace(TOKEN_UPDATE_LINK, updateLinkHtml);
		return result;
	}

	private static String buildUpdateLinkHtml(String rawLink) {
		if (String.isBlank(rawLink)) return '';
		String url = rawLink.trim();
		Pattern hrefPattern = Pattern.compile('(?i)href\\s*=\\s*[\'"]([^\'"]+)[\'"]');
		Matcher m = hrefPattern.matcher(url);
		if (m.find()) {
			url = m.group(1);
		} else {
			url = url.replace('"', '').replace('\'', '');
		}
		String safeUrl = escapeHtml(url);
		return '<a href="' + safeUrl + '" target="_blank">Update Credit Card Link</a>';
	}

	private static String escapeHtml(String s) {
		if (String.isBlank(s)) return '';
		return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;').replace('\'', '&#39;');
	}

	private static String formatAmountWithCurrency(Decimal amount, Payment__c payment) {
		if (amount == null) return '';
		String formattedAmount;
		try { formattedAmount = amount.setScale(2).format(); } catch (Exception e) { formattedAmount = String.valueOf(amount); }

		String currencyCode;
		Map<String, Object> populated = payment.getPopulatedFieldsAsMap();
		if (populated.containsKey('CurrencyIsoCode') && populated.get('CurrencyIsoCode') != null) {
			currencyCode = (String) populated.get('CurrencyIsoCode');
		}
		return String.isBlank(currencyCode) ? formattedAmount : currencyCode + ' ' + formattedAmount;
	}
}