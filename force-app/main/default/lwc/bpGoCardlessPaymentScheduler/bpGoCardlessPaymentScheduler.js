import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, getFieldValue, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

// ============================================================
// APEX METHODS
// ============================================================
import createDDPayments    from '@salesforce/apex/BP_GoCardlessPaymentSchedulerController.createDDPayments';
import hasExistingSchedule from '@salesforce/apex/BP_GoCardlessPaymentSchedulerController.hasExistingSchedule';
import getGbpExchangeInfo  from '@salesforce/apex/BP_GoCardlessPaymentSchedulerController.getGbpExchangeInfo';
import saveAwardAmount     from '@salesforce/apex/BP_GoCardlessPaymentSchedulerController.saveAwardAmount';
import getMandateStatus    from '@salesforce/apex/BP_GoCardlessPaymentSchedulerController.getMandateStatus';
import setupMandate        from '@salesforce/apex/BP_GoCardlessPaymentSchedulerController.setupMandate';

// ============================================================
// SCHEMA FIELDS
// ============================================================
import AWARD_AMOUNT_FIELD      from '@salesforce/schema/Basic__c.Award_Amount__c';
import DWP_PAYMENT_DATE_FIELD  from '@salesforce/schema/Basic__c.DWP_Payment_Date__c';
import CURRENCY_ISO_CODE_FIELD from '@salesforce/schema/Basic__c.CurrencyIsoCode';
import AWARD_AMOUNT_GBP_FIELD from '@salesforce/schema/Basic__c.Award_Amount_GBP__c';


export default class BpGoCardlessPaymentScheduler extends LightningElement {

    @api recordId;

    // ============================================================
    // FORM STATE
    // ============================================================
    awardAmount       = 10000;
    awardDisplayValue = '£10,000.00';
    isSavingAward     = false;
    awardSaved        = false;

    firstPaymentDate = this.getDateInThreeDays();
    firstChargeDate  = null;

    selectedInstallments = '1';
    isOverride           = false;
    isSaving             = false;

    isLoadingCheck  = true;
    hasExisting     = false;
    scheduleCreated = false;

    installmentOptions = [
        { label: 'Single charge (1x)',                   value: '1' },
        { label: 'Split in 2 monthly installments (2x)', value: '2' },
        { label: 'Split in 3 monthly installments (3x)', value: '3' },
        { label: 'Split in 4 monthly installments (4x)', value: '4' },
        { label: 'Split in 5 monthly installments (5x)', value: '5' },
        { label: 'Split in 6 monthly installments (6x)', value: '6' }
    ];

    // ============================================================
    // EXCHANGE-RATE STATE
    // ============================================================
    recordCurrency   = 'GBP';
    exchangeRate     = null;
    exchangeRateDate = null;
    corporateCurrency = '';

    // ============================================================
    // MANDATE STATUS STATE
    // ============================================================
    mandateStatus = {
        isActive:      false,
        status:        'Loading...',
        message:       '',
        reference:     null,
        createdAt:     null,
        customerId:    null,
        bankAccountId: null,
        mandateId:     null
    };

    isLoadingMandate   = true;
    isSettingUpMandate = false;


    // ============================================================
    // LIFECYCLE
    // ============================================================
    connectedCallback() {
        this.awardDisplayValue = this.formatGBP(this.awardAmount);
        this.recalculateChargeDate();

        // Fetch mandate status immediately
        this.refreshMandateStatus();
    }


    // ============================================================
    // WIRES
    // ============================================================
    @wire(getRecord, {
        recordId: '$recordId',
        fields: [
            AWARD_AMOUNT_FIELD,
            AWARD_AMOUNT_GBP_FIELD,
            DWP_PAYMENT_DATE_FIELD,
            CURRENCY_ISO_CODE_FIELD
        ]
    })
    wiredClaim({ data, error }) {
        if (data) {
            const gbp = getFieldValue(data, AWARD_AMOUNT_GBP_FIELD);
            const legacy = getFieldValue(data, AWARD_AMOUNT_FIELD);
            const existing = gbp != null ? gbp : legacy;
            if (existing != null) {
                this.awardAmount = existing;
                this.awardDisplayValue = this.formatGBP(existing);
            }

            const existingDwp = getFieldValue(data, DWP_PAYMENT_DATE_FIELD);
            if (existingDwp != null) {
                this.firstPaymentDate = existingDwp;
                this.recalculateChargeDate();
            }

            const iso = getFieldValue(data, CURRENCY_ISO_CODE_FIELD);
            if (iso && iso !== this.recordCurrency) {
                this.recordCurrency = iso;
                this.loadExchangeRate();   // load the rate for the record's currency
            }
            
        } else if (error) {
            console.error('Error loading claim:', error);
        }
    }

    @wire(hasExistingSchedule, { claimId: '$recordId' })
    wiredHasExisting({ data, error }) {
        console.log('data ===== ', data);
        console.log('error ===== ', error);
       
        if (data !== undefined) {
            this.isLoadingCheck = false;
            this.hasExisting = data === true;
        } else if (error) {
            this.isLoadingCheck = false;
            console.error('Error checking existing schedule:', JSON.stringify(error));
            this.hasExisting = true;   // fail-closed: hide the form if the check fails
        }
    }


    // ============================================================
    // EXCHANGE-RATE LOADING
    // ============================================================
    async loadExchangeRate() {
        try {
            const info = await getGbpExchangeInfo({
                targetCurrency: this.recordCurrency
            });

            if (info && info.rate != null) {
                this.exchangeRate     = info.rate;
                this.exchangeRateDate = info.rateDate || null;
            } else {
                this.exchangeRate     = null;
                this.exchangeRateDate = null;

                if (info && info.error) {
                    console.warn('Exchange rate unavailable:', info.error);
                }
            }
        } catch (err) {
            console.error('Rate error:', err);
            this.exchangeRate = null;
        }
    }


    // ============================================================
    // MANDATE LOGIC
    // ============================================================
    async refreshMandateStatus() {
        if (!this.recordId) return;

        this.isLoadingMandate = true;
        try {
            const result = await getMandateStatus({ claimId: this.recordId });
            this.mandateStatus = result;
        } catch (error) {
            console.error('Error fetching mandate status:', error);
            this.mandateStatus = {
                isActive:      false,
                status:        'Error',
                message:       'Could not load mandate status: ' +
                               (error?.body?.message || error?.message),
                reference:     null,
                createdAt:     null,
                customerId:    null,
                bankAccountId: null,
                mandateId:     null
            };
        } finally {
            this.isLoadingMandate = false;
        }
    }

    async handleSetupMandate() {
        if (!this.recordId) return;

        this.isSettingUpMandate = true;
        try {
            const mandateId = await setupMandate({ claimId: this.recordId });

            this.dispatchEvent(new ShowToastEvent({
                title:   'Success',
                message: 'Mandate set up successfully!',
                variant: 'success'
            }));

            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            await this.refreshMandateStatus();
        } catch (error) {
            console.error('Setup mandate error:', error);
            this.dispatchEvent(new ShowToastEvent({
                title:   'Error setting up mandate',
                message: error?.body?.message || error?.message || 'Unknown error',
                variant: 'error',
                mode:    'sticky'
            }));
        } finally {
            this.isSettingUpMandate = false;
        }
    }


    // ============================================================
    // GETTERS — UI FLAGS
    // ============================================================
    get isLoadingAny() {
        return this.isLoadingCheck || this.isLoadingMandate;
    }

    get hasGoCardlessData() {
        return this.mandateStatus.customerId ||
               this.mandateStatus.bankAccountId ||
               this.mandateStatus.mandateId;
    }

    get showForm() {
        return !this.isLoadingCheck && !this.hasExisting && !this.scheduleCreated;
    }

    get showAlreadyScheduled() {
        return !this.isLoadingCheck && (this.hasExisting || this.scheduleCreated);
    }

    get isSaveDisabled() {
        return this.isSaving
            || this.scheduleCreated
            || this.hasExisting
            || !this.firstChargeDate
            || !this.mandateStatus.isActive
            || this.isSettingUpMandate;
    }

    get isSaveAwardDisabled() {
        return this.isSavingAward
            || this.awardAmount === ''
            || this.awardAmount === null
            || !this.mandateStatus.isActive
            || this.isSettingUpMandate;
    }

    get isSetupDisabled() {
        return this.isSettingUpMandate;
    }


    // ============================================================
    // GETTERS — DISPLAY (mandate IDs)
    // ============================================================
    get displayCustomerId() {
        return this.mandateStatus.customerId
            ? '...' + this.mandateStatus.customerId.slice(-6)
            : 'Not set';
    }

    get displayBankAccountId() {
        return this.mandateStatus.bankAccountId
            ? '...' + this.mandateStatus.bankAccountId.slice(-6)
            : 'Not set';
    }

    get displayMandateId() {
        return this.mandateStatus.mandateId
            ? '...' + this.mandateStatus.mandateId.slice(-6)
            : 'Not set';
    }

    get displayReference() {
        return this.mandateStatus.reference
            ? '...' + this.mandateStatus.reference.slice(-6)
            : '...7VK2RH';
    }

    get displayActiveSince() {
        if (!this.mandateStatus.createdAt) return '';

        try {
            const d = new Date(this.mandateStatus.createdAt);
            return d.toLocaleString('en-GB', {
                day:    '2-digit',
                month:  '2-digit',
                year:   'numeric',
                hour:   '2-digit',
                minute: '2-digit'
            });
        } catch (e) {
            return this.mandateStatus.createdAt;
        }
    }


    // ============================================================
    // GETTERS — FEE / INSTALLMENTS
    // ============================================================
    get feeAmount() {
        const award = parseFloat(this.awardAmount);
        if (isNaN(award)) return 0;
        return Math.round((award * 0.25) * 100) / 100;
    }

    get installmentAmount() {
        const totalFee     = parseFloat(this.feeAmount);
        const installments = parseInt(this.selectedInstallments, 10);
        if (!installments) return '0.00';
        return (totalFee / installments).toFixed(2);
    }

    get formattedInstallmentAmount() {
        return parseFloat(this.installmentAmount).toLocaleString('en-GB', {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        });
    }

    get formattedFeeAmount() {
        return parseFloat(this.feeAmount).toLocaleString('en-GB', {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        });
    }

    get schedulePreview() {
        if (!this.firstChargeDate) return 'No date selected';

        const dates           = [];
        const baseDate        = new Date(this.firstChargeDate + 'T00:00:00');
        const numInstallments = parseInt(this.selectedInstallments, 10);

        for (let i = 0; i < numInstallments; i++) {
            const nextDate = new Date(baseDate);
            nextDate.setMonth(baseDate.getMonth() + i);

            const day   = nextDate.getDate();
            const month = nextDate.toLocaleString('en-GB', { month: 'short' });

            dates.push(`${day} ${month}`);
        }

        return dates.join(', ');
    }


    // ============================================================
    // GETTERS — EXCHANGE RATE
    // ============================================================
    get showExchangeRate() {
        return this.exchangeRate != null
            && !isNaN(this.exchangeRate)
            && this.recordCurrency
            && this.recordCurrency !== 'GBP';
    }

    get convertedMonthlyAmount() {
        const amt = parseFloat(this.installmentAmount);
        if (!this.exchangeRate || isNaN(amt)) return '';

        return (amt * this.exchangeRate).toLocaleString('en-GB', {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        });
    }

    get exchangeRateDisplay() {
        if (this.exchangeRate == null || isNaN(this.exchangeRate)) return '';
        return Number(this.exchangeRate).toFixed(3);
    }

    get targetCurrency() {
        return this.recordCurrency || 'GBP';
    }


    // ============================================================
    // HANDLERS — FORM INPUTS
    // ============================================================
    handleAwardChange(event) {
        const raw = event.target.value;
        this.awardDisplayValue = raw;

        const parsed = this.parseCurrency(raw);
        this.awardAmount = parsed === null ? '' : parsed;
    }

    handleAwardBlur() {
        if (this.awardAmount === '' || this.awardAmount === null) {
            this.awardDisplayValue = '';
            return;
        }
        this.awardDisplayValue = this.formatGBP(this.awardAmount);
    }

    handleFirstPaymentDateChange(event) {
        this.firstPaymentDate = event.target.value;
        this.recalculateChargeDate();
    }

    handleInstallmentChange(event) {
        this.selectedInstallments = event.target.value;
    }

    handleOverrideToggle(event) {
        this.isOverride = event.target.checked;
        if (event.target.checked === false) {
            this.selectedInstallments = '1';
        }
    }

    recalculateChargeDate() {
        if (!this.firstPaymentDate) {
            this.firstChargeDate = null;
            return;
        }

        const d = new Date(this.firstPaymentDate + 'T00:00:00');
        d.setDate(d.getDate() + 11);
        this.firstChargeDate = d.toISOString().split('T')[0];
    }


    // ============================================================
    // HANDLERS — SAVE
    // ============================================================
    async handleSave() {
        if (!this.recordId) {
            this.dispatchEvent(new ShowToastEvent({
                title:   'Missing record',
                message: 'This component must be on a record page.',
                variant: 'error'
            }));
            return;
        }

        if (!this.firstPaymentDate) {
            this.dispatchEvent(new ShowToastEvent({
                title:   'Missing date',
                message: 'Please select a First Payment Date.',
                variant: 'error'
            }));
            return;
        }

        const wrapper = {
            claimId:           this.recordId,
            awardAmount:       parseFloat(this.awardAmount),
            feeAmount:         parseFloat(this.feeAmount),
            installments:      parseInt(this.selectedInstallments, 10),
            firstChargeDate:   this.firstChargeDate,
            installmentAmount: parseFloat(this.installmentAmount),
            dwpPaymentDate:    this.firstPaymentDate || null
        };

        this.isSaving = true;
        try {
            const result = await createDDPayments({ wrapper });
            this.scheduleCreated = true;

            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);

            this.dispatchEvent(new ShowToastEvent({
                title:   'Success',
                message: result || 'Payment schedule created.',
                variant: 'success'
            }));
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title:   'Error creating payment schedule',
                message: error?.body?.message || error?.message || 'Unknown error',
                variant: 'error',
                mode:    'sticky'
            }));
        } finally {
            this.isSaving = false;
        }
    }

    async handleSaveAward() {
        if (!this.recordId) {
            this.dispatchEvent(new ShowToastEvent({
                title:   'Missing record',
                message: 'This component must be on a record page.',
                variant: 'error'
            }));
            return;
        }

        const amount = parseFloat(this.awardAmount);
        if (isNaN(amount) || amount < 0) {
            this.dispatchEvent(new ShowToastEvent({
                title:   'Invalid amount',
                message: 'Please enter a valid award amount.',
                variant: 'error'
            }));
            return;
        }

        this.isSavingAward = true;
        try {
            await saveAwardAmount({
                claimId:        this.recordId,
                awardAmount:    amount,
                dwpPaymentDate: this.firstPaymentDate || null
            });

            this.awardSaved = true;
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);

            this.dispatchEvent(new ShowToastEvent({
                title:   'Success',
                message: 'Award amount and DWP Payment Date saved.',
                variant: 'success'
            }));
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title:   'Error saving award amount',
                message: error?.body?.message || error?.message || 'Unknown error',
                variant: 'error',
                mode:    'sticky'
            }));
        } finally {
            this.isSavingAward = false;
        }
    }


    // ============================================================
    // UTILITIES
    // ============================================================
    getDateInThreeDays() {
        const d = new Date();
        d.setDate(d.getDate() + 3);
        return d.toISOString().split('T')[0];
    }

    formatGBP(num) {
        if (num === '' || num === null || num === undefined || isNaN(num)) return '';
        return '£' + Number(num).toLocaleString('en-GB', {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        });
    }

    parseCurrency(str) {
        if (!str) return null;
        const cleaned = String(str).replace(/[£,\s]/g, '');
        if (cleaned === '' || isNaN(cleaned)) return null;
        return parseFloat(cleaned);
    }
}