import { LightningElement, api, track, wire } from 'lwc';
import { getRecord } from "lightning/uiRecordApi";
import { updateRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import Id from '@salesforce/user/Id';
import logCall from '@salesforce/apex/CallFollowUpModuleController.logCall';
import USER_NAME_FIELD from '@salesforce/schema/User.Name';

// Mesmo card no Application__c (Sales) e no Basic__c (Claims): os 7 campos têm o mesmo nome nos dois objetos (04/11/2026).
const CALL_FOLLOW_UP_CALL_CHANGE_USER = 'Call_Follow_Up_Change_User__c';
const FIELD_NAMES = [
    'X1st_Follow_Up_Call__c',
    'X2nd_Follow_Up_Call__c',
    'X3rd_Follow_Up_Call__c',
    CALL_FOLLOW_UP_CALL_CHANGE_USER,
    'X1st_Esign_Follow_Up_Call_Changed_Date__c',
    'X2nd_Esign_Follow_Up_Call_Changed_Date__c',
    'X3rd_Esign_Follow_Up_Call_Changed_Date__c'
];
// Texto do toast por objeto; Application é o de sempre.
const NOUN = { Application__c: 'Application', Basic__c: 'Claim' };
const FOLLOW_FIELD_BY_CHANGED_DATE = new Map([
    ['X1st_Follow_Up_Call__c', 'X1st_Esign_Follow_Up_Call_Changed_Date__c'],
    ['X2nd_Follow_Up_Call__c', 'X2nd_Esign_Follow_Up_Call_Changed_Date__c'],
    ['X3rd_Follow_Up_Call__c', 'X3rd_Esign_Follow_Up_Call_Changed_Date__c']
]);

export default class CallFollowUpModule extends LightningElement {
    @api recordId;
    @api objectApiName;
    userId = Id;
    loaded = false;
    chooseCheckboxLabel;
    currentAgentId = '';
    currentAgent = '';
    currentFollowUpDateRaw = '';
    followUpDateValues = {};
    @track options = [
        { label: '1st Follow Up Call', value: 'X1st_Follow_Up_Call__c', checked : false },
        { label: '2nd Follow Up Call', value: 'X2nd_Follow_Up_Call__c', checked : false },
        { label: '3rd Follow Up Call', value: 'X3rd_Follow_Up_Call__c', checked : false }
    ];
    
    today = new Date();

    // Campos do objeto da página ("Application__c.X1st_Follow_Up_Call__c" ou "Basic__c....").
    get fields() {
        return this.objectApiName ? FIELD_NAMES.map((f) => `${this.objectApiName}.${f}`) : undefined;
    }

    get noun() {
        return NOUN[this.objectApiName] || 'Application';
    }

    @wire(getRecord, { recordId: "$recordId", fields: '$fields' })
    wiredRecords({ error, data }) {
        if (data) {
            this.currentAgentId = data.fields[CALL_FOLLOW_UP_CALL_CHANGE_USER]?.value || '';
            this.currentAgent = '';
            this.currentFollowUpDateRaw = '';
            this.options.forEach(checkbox => {
                checkbox.checked = data.fields[checkbox.value].value;
                const dateFieldApiName = FOLLOW_FIELD_BY_CHANGED_DATE.get(checkbox.value);
                this.followUpDateValues[checkbox.value] = data.fields[dateFieldApiName]?.value || '';
                if (checkbox.checked) {
                    this.currentFollowUpDateRaw = this.followUpDateValues[checkbox.value];
                    this.chooseCheckboxLabel = checkbox.label;
                }
            });
        } else if (error) {
            console.log('error === ', error);
        }
    }

    @wire(getRecord, { recordId: '$currentAgentId', fields: [USER_NAME_FIELD] })
    wiredAgent({ error, data }) {
        if (data) {
            this.currentAgent = data.fields.Name.value || '';
        } else if (error) {
            this.currentAgent = '';
        }
    }

    handleChange(event) {
        const selectedCheckboxName = event.target.name;
        this.options.forEach(checkbox => {
            if (checkbox.value !== selectedCheckboxName) {
                checkbox.checked = false;
            } else {
                checkbox.checked = true;
                this.chooseCheckboxLabel = checkbox.label;
                this.currentFollowUpDateRaw = this.followUpDateValues[checkbox.value] || '';
            }
        });
        // Faltava desde 03/06/2026: o tick só mudava na tela e sumia ao recarregar.
        this.updateApplicationData();
    }

    updateApplicationData() {
        this.loaded = !this.loaded;
        const fields = {};
        fields['Id'] = this.recordId;
        fields[CALL_FOLLOW_UP_CALL_CHANGE_USER] = this.userId;

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
                    message: `${this.noun} updated`,
                    variant: "success",
                }),
            );
            this.loaded = !this.loaded;
            // updateRecord já atualiza o getRecord (o refreshApex de antes não fazia nada)
        })
        .catch((error) => {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: `Error updating ${this.noun.toLowerCase()}`,
                    message: error.body?.message || error.message || 'Unknown error',
                    variant: "error",
                }),
            );
            this.loaded = !this.loaded;
        });
    }

    get currentFollowUpDateFormatted() {
        if (!this.currentFollowUpDateRaw) {
            return '';
        }
        const date = new Date(this.currentFollowUpDateRaw);
        if (Number.isNaN(date.getTime())) {
            return this.currentFollowUpDateRaw;
        }
        const day = String(date.getDate()).padStart(2, '0');
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const year = date.getFullYear();
        return `${day}/${month}/${year}`;
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
                    message: error.body?.message || 'Unknown error',
                    variant: 'error'
                })
            );
        }
    }

}