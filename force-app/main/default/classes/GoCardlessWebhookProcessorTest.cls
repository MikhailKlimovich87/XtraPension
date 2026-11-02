@IsTest
public without sharing class GoCardlessWebhookProcessorTest {

	private static final String PRODUCT_NAME = 'Claim - Direct Debit';

	@TestSetup
	static void setup() {
		TestDataFactory.createTestCountry(true);
		Account account = TestDataFactory.createAccount(true);
		Contact contact = [
			SELECT Id
			FROM Contact
			WHERE AccountId = :account.Id
			LIMIT 1
		];

		Basic__c claim = BP_TestDataFactory.createBasic(contact.Id, false);
		claim.Current_Address_Abroad__CountryCode__s = 'IE';
		insert claim;

		insert new Product2(
			Name = PRODUCT_NAME,
			CurrencyIsoCode = 'EUR',
			IsActive = true
		);

		List<Basic_Payment__c> payments = new List<Basic_Payment__c>();
		for (Integer indexValue = 0; indexValue < 7; indexValue++) {
			Basic_Payment__c payment = BP_TestDataFactory.createBP_Payment(
				claim.Id,
				false,
				[SELECT Id FROM Product2 WHERE Name = :PRODUCT_NAME LIMIT 1]
			);
			payment.GoCardless_Payment_Id__c = 'GC-PAY-' + indexValue;
			payments.add(payment);
		}
		insert payments;
	}

	private static Map<String, Object> paymentEvent(String paymentId, String action) {
		return new Map<String, Object>{
			'id' => 'EV-' + paymentId,
			'resource_type' => 'payments',
			'action' => action,
			'created_at' => '2026-10-07T12:00:00Z',
			'links' => new Map<String, Object>{ 'payment' => paymentId }
		};
	}

	@IsTest
	static void mapsAllPaymentActionsToStatuses() {
		List<String> actions = new List<String>{
			'created', 'submitted', 'confirmed', 'paid_out',
			'failed', 'cancelled', 'charged_back'
		};
		List<String> expectedStatuses = new List<String>{
			'Schedule', 'Submitted', 'Confirmed', 'Paid',
			'Fail', 'Cancel', 'Refund'
		};
		List<Object> events = new List<Object>();

		for (Integer indexValue = 0; indexValue < actions.size(); indexValue++) {
			events.add(paymentEvent('GC-PAY-' + indexValue, actions[indexValue]));
		}

		Test.startTest();
		GoCardlessWebhookProcessor.process(events);
		Test.stopTest();

		Map<String, String> actualStatuses = new Map<String, String>();
		for (Basic_Payment__c payment : [
			SELECT GoCardless_Payment_Id__c, Status__c
			FROM Basic_Payment__c
			WHERE GoCardless_Payment_Id__c LIKE 'GC-PAY-%'
		]) {
			actualStatuses.put(payment.GoCardless_Payment_Id__c, payment.Status__c);
		}

		for (Integer indexValue = 0; indexValue < expectedStatuses.size(); indexValue++) {
			System.assertEquals(
				expectedStatuses[indexValue],
				actualStatuses.get('GC-PAY-' + indexValue),
				'Unexpected status for action ' + actions[indexValue]
			);
		}
	}

	@IsTest
	static void doesNotRegressOrUpdateIgnoredEvents() {
		Basic_Payment__c paidPayment = [
			SELECT Id, Status__c
			FROM Basic_Payment__c
			WHERE GoCardless_Payment_Id__c = 'GC-PAY-0'
			LIMIT 1
		];
		paidPayment.Status__c = 'Paid';
		update paidPayment;

		List<Object> events = new List<Object>{
			paymentEvent('GC-PAY-0', 'created'),
			paymentEvent('GC-PAY-1', 'unknown_action'),
			paymentEvent('GC-MISSING', 'paid_out'),
			new Map<String, Object>{
				'resource_type' => 'mandates',
				'action' => 'cancelled',
				'links' => new Map<String, Object>{ 'payment' => 'GC-PAY-1' }
			},
			'not-an-event'
		};

		Test.startTest();
		GoCardlessWebhookProcessor.process(events);
		Test.stopTest();

		Map<String, Basic_Payment__c> payments = new Map<String, Basic_Payment__c>();
		for (Basic_Payment__c payment : [
			SELECT GoCardless_Payment_Id__c, Status__c
			FROM Basic_Payment__c
			WHERE GoCardless_Payment_Id__c IN ('GC-PAY-0', 'GC-PAY-1')
		]) {
			payments.put(payment.GoCardless_Payment_Id__c, payment);
		}

		System.assertEquals('Paid', payments.get('GC-PAY-0').Status__c);
		System.assertEquals('Schedule', payments.get('GC-PAY-1').Status__c);
	}

	@IsTest
	static void acceptsNullEmptyAndUnusableEvents() {
		Test.startTest();
		GoCardlessWebhookProcessor.process(null);
		GoCardlessWebhookProcessor.process(new List<Object>());
		GoCardlessWebhookProcessor.process(new List<Object>{
			null,
			new Map<String, Object>{ 'resource_type' => 'payments' },
			new Map<String, Object>{
				'resource_type' => 'payments',
				'action' => 'created',
				'links' => new Map<String, Object>()
			}
		});
		Test.stopTest();

		System.assertEquals(
			'Schedule',
			[SELECT Status__c FROM Basic_Payment__c WHERE GoCardless_Payment_Id__c = 'GC-PAY-0' LIMIT 1].Status__c
		);
	}

}