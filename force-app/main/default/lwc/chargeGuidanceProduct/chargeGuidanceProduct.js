import { LightningElement, api, wire, track } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import chargeGuidanceProduct from '@salesforce/apex/ChargeGuidanceProductController.chargeProduct';
import getApplication from '@salesforce/apex/ChargeGuidanceProductController.getApplication';

const columns = [
    { label: 'Product Name', fieldName: 'Product_Name__c' },
    { label: 'Payment Date', fieldName: 'Payment_Date__c', type: 'date' },
    { label: 'Status', fieldName: 'Status__c'},
    { label: 'Amount', fieldName: 'Amount__c', type: 'currency'}
];
const CHARGE_PRODUCT_NAME = 'Success';
export default class ChargeGuidanceProduct extends LightningElement  {
    @api recordId;
    content;
    showSpinner = false;
    result;
    error;
    applicationData;
    paymentInfo;
    chargeProductName;
    errorData;
    tableData;
    @track filetabledata=[];
    @track remainingAmount;
    amount;
    currencyCode;

    @wire(getApplication, {recordId: '$recordId'})
    retrievedApplication({error, data}) {
        if(data) {
            this.applicationData = data;
            this.currencyCode = data.currencyCode;
            this.tableData = data.allRelatedPayments.map( item =>{
                var temData = {
                    'prodName':item['Product_Name__c'],
                    'amount':item['Amount__c'],
                    'status':item['Status__c'],
                    'paymentDate': item['Payment_Date__c'],
                    'isPaid' : item['Status__c'] == 'Paid' ? true : false
                }
                this.filetabledata.push(temData);
                this.chargeAmount();
                return{...item}
            })
            this.checkApplicationStatus();
        } else if(error) {
            this.errorData = error;
            console.log('error: ', error);
        }
    }

    checkApplicationStatus() {
        let appStatus =  this.applicationData.application.Status__c;
        console.log('appStatus === ', appStatus);
        if (appStatus != 'Charge CC') {
            this.errorData = 'You are not on the \'Charge CC\' stage';
            return;
        }
        let successPayment = this.applicationData.allRelatedPayments.find(
            payment => payment.Product_Name__c == CHARGE_PRODUCT_NAME
        );
        console.log('successPayment === ', successPayment);
        if(successPayment == null) {
            this.errorData = 'This application doesn\'t contain Success payment';
            return;
        }
        if(successPayment.Status__c == 'Paid') {
            this.errorData = 'Success payment has already paid';
            return;
        }
        this.chargeProductName = 'Success';
    }

    handleCharge() {
        this.showSpinner = !this.showSpinner;
        if (!this.amount) this.amount = this.remainingAmount;
        let successProductData = {
            "recordId" : this.recordId,
            "amount"   : this.amount
        };
        chargeGuidanceProduct({
            productInfo : successProductData
        })
        .then(result => {
            this.result = result;
                this.showSpinner = !this.showSpinner;
            const evt = new ShowToastEvent({
                title: result.title,
                message: result.message,
                variant: result.variant
            });
            this.dispatchEvent(evt);
            this.closeModal();
        }).catch(error => {
            this.error = error;
                this.showSpinner = !this.showSpinner;
            const evt = new ShowToastEvent({
                title: 'Error',
                message: 'You didn\'t charge Success Product. Error is ' + this.error,
                variant: 'error',
            });
            this.dispatchEvent(evt);
            this.closeModal();
        });
    }

    closeModal() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
    @api get isExistChargeProductName() {
        return this.chargeProductName != null ? true : false;
    }
    @api get isExistErrorData() {
        return this.errorData != null ? true : false;
    }

    @api get totalAmount() {
        let amount = 0;
        this.filetabledata.map(
            item => {
                if(item.status == 'Paid') amount += item.amount;
            });
        return amount;
    }

    chargeAmount() {
        let amount = 0;
        this.filetabledata.map(
            item => {
                amount += item.amount;
            });
        this.remainingAmount = amount - this.totalAmount;
    }

    changeAmount(event) {
        this.amount = event.target.value;
    }

}