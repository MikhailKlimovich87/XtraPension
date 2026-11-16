import { LightningElement, wire, api } from 'lwc';
import { getPicklistValues, getObjectInfo } from 'lightning/uiObjectInfoApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import CLAIM_CHECK_OBJECT from '@salesforce/schema/Claim_Check__c';
import CHECK_AGENT_FIELD from '@salesforce/schema/Claim_Check__c.Check_Agents__c';

// What the DWP said; "Called DWP" only says how it was checked, so it does not count on its own
const STATUS_KEYS = ['notReceived', 'received', 'processing', 'moreInfo', 'approved', 'rejected', 'lumpSum', 'paymentStarted'];

export default class ClaimCheckLeftBlock extends LightningElement {
    @api searchApps;
    checkAgents = [];
    checkAgent;
    isDisabledCheckAgent = true;
    isSaving = false;
    replies = [this.newReply()];
    _prefill;

    // { name, at } from the queue: a new block with that claim, replacing the first one if it is still blank
    @api
    get prefill() {
        return this._prefill;
    }
    set prefill(value) {
        this._prefill = value;
        if (!value || !value.name) return;
        const reply = { ...this.newReply(), appName: value.name };
        const blank = r => !r.appName && !r.notes && !r.pdfLink;
        this.replies = this.replies.length && blank(this.replies[0])
            ? [reply, ...this.replies.slice(1)]
            : [...this.replies, reply];
    }

    @wire(getObjectInfo, { objectApiName: CLAIM_CHECK_OBJECT })
    checkInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$checkInfo.data.defaultRecordTypeId',
        fieldApiName: CHECK_AGENT_FIELD })
    agentsData({ error, data }) {
        if (data) {
            this.checkAgents = [...data.values];
        }
        if (error) {
            console.log('Error uploading picklist values');
        }
    }

    newReply() {
        return {
            id : this.generateUniqueId(),
            appName : null,
            notReceived : false,
            received : false,
            processing : false,
            moreInfo : false,
            approved : false,
            rejected : false,
            lumpSum : false,
            paymentStarted : false,
            calledDwp : false,
            notes : null,
            pdfLink : null
        };
    }

    handleSave() {
        if (!this.handleValidation()) return;
        this.isSaving = true;
        // the page reloads after a successful save; if it fails, let them try again
        setTimeout(() => { this.isSaving = false; }, 5000);
        this.dispatchEvent(
            new CustomEvent('savecheckreply', {
                detail : {
                    replies : this.replies,
                    agent   : this.checkAgent
                },
                bubbles: true,
                composed: true
            })
        );
    }

    handleValidation() {
        const agentInputElement = this.template.querySelector('[data-id="agent"]');
        let isValid = true;
        let isNotBlankCheckboxes = true;

        if (!agentInputElement.value) {
            agentInputElement.setCustomValidity('Check Agent cannot be empty.');
            isValid = false;
        } else {
            agentInputElement.setCustomValidity('');
        }
        agentInputElement.reportValidity();

        this.replies.forEach(item => {
            if (!item.appName || !item.notes) {
                isValid = false;
            }
            if (!STATUS_KEYS.some(key => item[key] === true)) {
                isNotBlankCheckboxes = false;
            }
        });

        if (!isValid) {
            this.showToastMessage('Error', 'Claim No, Check Agent and Notes are required. Please check', 'error');
        }
        if (!isNotBlankCheckboxes) {
            this.showToastMessage('Error', 'Please tick at least one result (Called DWP alone is not enough)', 'error');
        }
        return isValid && isNotBlankCheckboxes;
    }

    handleAddRequest() {
        this.replies = [...this.replies, this.newReply()];
    }

    generateUniqueId() {
        return Date.now().toString(36) + Math.random().toString(36).substring(2);
    }

    handleRemoveRequest(event) {
        this.replies = this.replies.filter(item => item.id !== event.detail);
    }

    handleUpdateReply(event) {
        const currReply = JSON.parse(JSON.stringify(event.detail));
        const index = this.replies.findIndex(item => item.id === currReply.id);
        if (index !== -1) {
            this.replies = [
                ...this.replies.slice(0, index),
                currReply,
                ...this.replies.slice(index + 1)
            ];
        }
    }

    get isSaveDisabled() {
        return this.replies.length === 0 || this.isSaving;
    }

    showToastMessage(titleData, messageInfo, toastVariant) {
        this.dispatchEvent(new ShowToastEvent({
            title: titleData,
            message: messageInfo,
            variant: toastVariant,
        }));
    }

    handleChangeAgent(event) {
        this.checkAgent = event.target.value;
        this.isDisabledCheckAgent = !event.target.value;
    }
}