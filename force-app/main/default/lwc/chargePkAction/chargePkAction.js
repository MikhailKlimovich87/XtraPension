import { LightningElement, api, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { updateRecord } from 'lightning/uiRecordApi';
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import { NavigationMixin } from 'lightning/navigation';

import {ShowToastEvent} from "lightning/platformShowToastEvent";
import { refreshApex } from "@salesforce/apex";

import ID_FIELD from '@salesforce/schema/Application__c.Id';
import PK_REGISTRATION_DATE_FIELD from '@salesforce/schema/Application__c.PK_Registration_Date__c';
import PK_PORTAL_USER_ACTIVE_FIELD from '@salesforce/schema/Application__c.PK_Portal_User_Active__c';
import EMAIL_FIELD from '@salesforce/schema/Application__c.Email__c';
import STATUS_FIELD from '@salesforce/schema/Application__c.Status__c';
import NAME_FIELD from '@salesforce/schema/Application__c.Name';
import PK_SALES_AGENT_FIELD from '@salesforce/schema/Application__c.PK_Sale_Agent__c';

import registartePKCustomer from '@salesforce/apex/ChargePkActionController.registratePkService';
import getPensionKeeperBaseUrl from '@salesforce/apex/ChargePkActionController.getPensionKeeperBaseUrlAddress';

const FIELDS = [
    PK_REGISTRATION_DATE_FIELD,
    PK_PORTAL_USER_ACTIVE_FIELD,
    EMAIL_FIELD,
    STATUS_FIELD,
    NAME_FIELD,
    PK_SALES_AGENT_FIELD
];

export default class ChargePkAction extends NavigationMixin(LightningElement) {
    @api
    recordId;
    baseUrl = '';
    isScheduleView = false;
    registrationDate;
    isRegistrateCustomer = false;
    disableCharge = false;
    
    async connectedCallback() {
        try {
            const baseUrl = await getPensionKeeperBaseUrl();
            console.log('Base URL:', baseUrl);
            this.baseUrl = baseUrl;
            // Use baseUrl as needed in your component
        } catch (error) {
            console.error('Error getting base URL:', error);
        }
    }

    @wire(getRecord, { recordId: "$recordId", fields: FIELDS })
    application;
    salesAgent;

    get options() {
        return [
            { label: 'John', value: 'John' },
            { label: 'Megan', value: 'Megan' },
            { label: 'Tomas', value: 'Tomas' },
            { label: 'Sean Bedford', value: 'Sean Bedford' },
            { label: 'Sean Byrne', value: 'Sean Byrne' },
            { label: 'Katherine', value: 'Katherine' },
            { label: 'Ciara', value: 'Ciara' },
            { label: 'MaryClaire', value: 'MaryClaire' },
            { label: 'Grace', value: 'Grace' },
            { label: 'Fiona', value: 'Fiona' },
            { label: 'Richard', value: 'Richard' },
            { label: 'Breege', value: 'Breege' },
            { label: 'Becky', value: 'Becky' },
            { label: 'Monica', value: 'Monica' },
            { label: 'Daniel', value: 'Daniel' },
        ];
    }

    handleChange(event) {
        this.salesAgent = event.detail.value;
    }

    get portalUserActive() {
        return getFieldValue(this.application.data, PK_PORTAL_USER_ACTIVE_FIELD);
    }

    get email() {
        return getFieldValue(this.application.data, EMAIL_FIELD);
    }

    get name() {
        return getFieldValue(this.application.data, NAME_FIELD);
    }

    get salesAgent() {
        return getFieldValue(this.application.data, PK_SALES_AGENT_FIELD);
    }

    closeModal() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    openSchedulePage() {
        this.isScheduleView = true;
    }

    handleChangeDate(event) {
        this.registrationDate = event.target.value;
    }

    async handleCharge() {
        this.isRegistrateCustomer = true;
        this.disableCharge = true;
        try {
            const responseData = await registartePKCustomer(
                { appId: this.recordId, salesAgent: this.salesAgent }
            );
            console.log('responseData ===', responseData);
            if (responseData) {
               this.toast('Customer registered successfully', 'success');
            }
            return refreshApex(this.application);
        } catch (err) {
            console.log('On error data console');
            console.error(err);
            const errorMessage = this.getErrorMessage(err);
            this.toast(errorMessage, 'error');
        } finally {
            this.isRegistrateCustomer = false;
            this.closeModal();
        }
    }

    toast(title, variantType) {
        const toastEvent = new ShowToastEvent({
            title,
            variant: variantType
        })
        this.dispatchEvent(toastEvent)
    }

    getErrorMessage(error) {
        if (!error) {
            return 'An unexpected error occurred.';
        }

        if (typeof error === 'string') {
            return error;
        }

        const body = error.body;
        let message = body?.message || error?.message || '';

        if (!message && body?.pageErrors?.length) {
            message = body.pageErrors.map((pageError) => pageError.message).join(' | ');
        }

        if (!message && body?.fieldErrors) {
            message = Object.values(body.fieldErrors)
                .flat()
                .map((fieldError) => fieldError.message)
                .join(' | ');
        }

        return message || 'An unexpected error occurred.';
    }

    async handleSchedule() {
        if (!this.registrationDate) {
            this.toast('Please select a registration date.', 'error');
            return;
        }
        if (this.registrationDate <= new Date().toISOString().slice(0, 10)) {
            this.toast('Please select a future date.', 'error');
            return;
        }
        if ( this.portalUserActive == true) {
            this.toast('Applcation has already registred on PK service', 'error');
            return;
        }       
        this.isRegistrateCustomer = true;
        
        const fields = {};
        fields[PK_REGISTRATION_DATE_FIELD.fieldApiName] = this.registrationDate;
        fields[ID_FIELD.fieldApiName] = this.recordId;

        const recordInput = { fields };
        console.log('recordInput:', recordInput);
        
        try {
            const resultUpdate = await updateRecord(recordInput);
            console.log('Success');
            console.log('resultUpdate ==== ', resultUpdate);
            
            this.toast('You scheduled registration of PK service successfully', 'success');
        } catch (error) {
            console.error(error);
            const errorMessage = this.getErrorMessage(error);
            this.toast(errorMessage, 'error');
        } finally {
            this.isRegistrateCustomer = false;
            this.closeModal();
        }
    }

    async openUpdateCCPage() {
        this.isRegistrateCustomer = true;
        // 3. Define the configuration for the destination URL
        const urlAddress = this.baseUrl ? this.baseUrl + '?email=' + this.email + '&applicationNumber=' + this.name : '';
        if (!this.baseUrl) {
            this.toast('Base URL is not defined. Please check the configuration.', 'error');
            return;
        }

        // Update PK_SALES_AGENT_FIELD if salesAgent is not null
        if (this.salesAgent) {
            const fields = {};
            fields[ID_FIELD.fieldApiName] = this.recordId;
            fields[PK_SALES_AGENT_FIELD.fieldApiName] = this.salesAgent;

            const recordInput = { fields };
            try {
                await updateRecord(recordInput);
                console.log('Sales Agent updated successfully');
            } catch (error) {
                console.error('Error updating sales agent:', error);
                const errorMessage = this.getErrorMessage(error);
                this.toast(errorMessage, 'error');
                return;
            }
        }

        const config = {
            type: 'standard__webPage',
            attributes: {
                url: urlAddress
            }
        };
        this.closeModal();
        this.isRegistrateCustomer = false;
        this[NavigationMixin.Navigate](config);
        
    }
}