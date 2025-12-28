import { LightningElement, api, track, wire } from 'lwc';
import { getRecord } from "lightning/uiRecordApi";
import { updateRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from '@salesforce/apex';
import Id from '@salesforce/user/Id';
import logCall from '@salesforce/apex/CallFollowUpModuleController.logCall';

import X1_FOLLOW_UP_CALL from '@salesforce/schema/Application__c.X1st_Follow_Up_Call__c';
import X2_FOLLOW_UP_CALL from '@salesforce/schema/Application__c.X2nd_Follow_Up_Call__c';
import X3_FOLLOW_UP_CALL from '@salesforce/schema/Application__c.X3rd_Follow_Up_Call__c';
import CALL_FOLLOW_UP_CALL_CHANGE_USER from '@salesforce/schema/Application__c.Call_Follow_Up_Change_User__c';

const FIELDS = [X1_FOLLOW_UP_CALL, X2_FOLLOW_UP_CALL, X3_FOLLOW_UP_CALL,CALL_FOLLOW_UP_CALL_CHANGE_USER];
const FOLLOW_FIELD_BY_CHANGED_DATE = new Map([
    ['X1st_Follow_Up_Call__c', 'X1st_Esign_Follow_Up_Call_Changed_Date__c'],
    ['X2nd_Follow_Up_Call__c', 'X2nd_Esign_Follow_Up_Call_Changed_Date__c'],
    ['X3rd_Follow_Up_Call__c', 'X3rd_Esign_Follow_Up_Call_Changed_Date__c']
]);

export default class CallFollowUpModule extends LightningElement {
    @api recordId;
    userId = Id;
    loaded = false;
    chooseCheckboxLabel;
    @track options = [
        { label: '1st Follow Up Call', value: 'X1st_Follow_Up_Call__c', checked : false },
        { label: '2nd Follow Up Call', value: 'X2nd_Follow_Up_Call__c', checked : false },
        { label: '3rd Follow Up Call', value: 'X3rd_Follow_Up_Call__c', checked : false }
    ];
    today = new Date();
    @wire(getRecord, { recordId: "$recordId", fields: FIELDS })
    wiredRecords({ error, data }) {
        if (data) {
            this.options.forEach(checkbox => {
                checkbox.checked = data.fields[checkbox.value].value;
            });
        } else if (error) {
            console.log('error === ', error);
        }
    }

    handleChange(event) {
        const selectedCheckboxName = event.target.name;
        this.options.forEach(checkbox => {
            if (checkbox.value != selectedCheckboxName) {
                checkbox.checked = false;
            } else {
                checkbox.checked = true;
                this.chooseCheckboxLabel = checkbox.label;
            }
        });
        this.updateApplicationData();
    }

    updateApplicationData() {
        this.loaded = !this.loaded;
        const fields = {};
        fields['Id'] = this.recordId;
        fields[CALL_FOLLOW_UP_CALL_CHANGE_USER.fieldApiName] = this.userId;

        this.options.forEach(
            data => {
                fields[data.value] = data.checked;
                if (data.checked == true) {
                    fields[FOLLOW_FIELD_BY_CHANGED_DATE.get(data.value)] = this.today.toISOString().slice(0, 10);
                } else {
                    fields[FOLLOW_FIELD_BY_CHANGED_DATE.get(data.value)] = null;
                }
            }
        );
        updateRecord({ fields })
        .then(() => {
            this.handleLogCall();
            this.dispatchEvent(
                new ShowToastEvent({
                    title: "Success",
                    message: "Application updated",
                    variant: "success",
                }),
            );
            this.loaded = !this.loaded;
            refreshApex(this.wiredRecords)
        })
        .catch((error) => {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: "Error updating application",
                    message: error.body.message,
                    variant: "error",
                }),
            );
            this.loaded = !this.loaded;
        });
    }

    async handleLogCall() {
        try {
            const taskId = await logCall({
                subject: this.chooseCheckboxLabel,
                relatedToId: this.recordId,
                whoId: this.userId
            });
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error logging call',
                    message: error.body.message,
                    variant: 'error'
                })
            );
        }
    }
}