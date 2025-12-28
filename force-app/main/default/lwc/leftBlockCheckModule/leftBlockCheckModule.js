import { LightningElement, wire, track, api } from 'lwc';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import APPLICATION_OBJECT from '@salesforce/schema/Application__c';
import CHECK_AGENT_FIELD from "@salesforce/schema/Application__c.Check_Agent__c";
import SENT_TO_FIELD from "@salesforce/schema/Application__c.Sent_to__c";

export default class LeftBlockCheckModule extends LightningElement {
    @api searchApps;
    checkAgents = [];
    sentToValues = [];
    checkAgent;
    isDisabledCheckAgent = true;

    @track
    checkReply = {
        "id" : this.generateUniqueId(),
        "appName" : null,
        "notReceived" : false,
        "c2" : false,
        "workItem" : false,
        "badNINO" : false,
        "badInfo" : false,
        "processing" : false,
        "c3" : false,
        "dwp" : false,
        "X64_8": false,
        "reject" : false,
        "sentTo" : null,
        "sentDate" : null,
        "notes" : null,
        "pdfLink" : null,
        "appealLetterNotReceived" : false,
        "appealLetterReceived" : false,
        "requestedCopy" : null,
        "paymentMadeByClient" : null,
        "whenDate" : null,
        "paymentReceived": false,
        "paymentNotReceived": false,
        "dwpCall" : false
    }
    replies = [this.checkReply];

    @wire(getObjectInfo, { objectApiName: APPLICATION_OBJECT })
    applicationInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$applicationInfo.data.defaultRecordTypeId',
        fieldApiName: CHECK_AGENT_FIELD })
    agentsData({ error, data }) {
        if (data) {
            this.checkAgents = [...data.values];
        }
        if(error) {
            console.log('Error uploading picklist values');
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$applicationInfo.data.defaultRecordTypeId',
        fieldApiName: SENT_TO_FIELD })
    sentToData({ error, data }) {
        if (data) {
            this.sentToValues = [...data.values];
        }
        if(error) {
            console.log('Error uploading picklist values');
        }
    }

    handleSave() {
        let isValid = this.handleValidation();
        if(!isValid) return;
        this.dispatchEvent(
            new CustomEvent('savecheckreply', {
                detail :  {
                    replies : this.replies,
                    agent   : this.checkAgent
                },
                bubbles: true,
                composed: true
            })
        );
    }

    handleRequestedCopy(event) {
        this.checkReply.requestedCopy = event.detail;
        this.dispatchEvent(
            new CustomEvent('savecheckreply', {
                "detail" :  this.checkReply
            })
        );
    }

    handleValidation() {
        const agentInputElement = this.template.querySelector('[data-id="agent"]');
        let isValid = true;
        let isNotBlankCheckboxes = true;
        let isOnlyDWPCallCheckboxChecked = true;

        if (!agentInputElement.value) {
            agentInputElement.setCustomValidity('Check Agent cannot be empty.');
            isValid = false;
        } else {
            agentInputElement.setCustomValidity(''); // Clear previous error
        }
        agentInputElement.reportValidity();

        this.replies.forEach(item => {
            if(!item.appName || !item.notes || !item.pdfLink) {
                isValid = false;
            }
            if (item.notReceived == false &&
                item.c2 == false &&
                item.workItem == false &&
                item.badNINO == false &&
                item.badInfo == false &&
                item.processing == false &&
                item.c3 == false &&
                item.dwp == false &&
                item.X64_8 == false &&
                item.reject == false &&
                item.appealLetterNotReceived == false &&
                item.appealLetterReceived == false &&
                item.paymentReceived == false &&
                item.paymentNotReceived == false &&
                item.dwpCall == false
            ) {
                isNotBlankCheckboxes = false;
            }
            if (item.notReceived == false &&
                item.c2 == false &&
                item.workItem == false &&
                item.badNINO == false &&
                item.badInfo == false &&
                item.processing == false &&
                item.c3 == false &&
                item.dwp == false &&
                item.X64_8 == false &&
                item.reject == false &&
                item.appealLetterNotReceived == false &&
                item.appealLetterReceived == false &&
                item.paymentReceived == false &&
                item.paymentNotReceived == false &&
                item.dwpCall == true
            ) {
                isOnlyDWPCallCheckboxChecked = false;
            }
        });

        if (!isValid) {
            this.showToastMessage(
                'Error',
                'Some of fields is empty!!! Please check',
                'error'
            );
        }
        if (!isNotBlankCheckboxes) {
            this.showToastMessage(
                'Error',
                'Please, tick at least one checkboxes!',
                'error'
            );
        }
        if (!isOnlyDWPCallCheckboxChecked) {
            this.showToastMessage(
                'Error',
                'Please, tick at least 2 checkboxes if \'DWP Call\' is ticked!',
                'error'
            );
        }
        return isValid && isNotBlankCheckboxes && isOnlyDWPCallCheckboxChecked ? true : false;
    }

    handleAddRequest() {
        this.replies = [...this.replies, {
            "id" : this.generateUniqueId(),
            "appName" : null,
            "notReceived" : false,
            "c2" : false,
            "workItem" : false,
            "badNINO" : false,
            "badInfo" : false,
            "processing" : false,
            "c3" : false,
            "dwp" : false,
            "X64_8": false,
            "reject" : false,
            "sentTo" : null,
            "sentDate" : null,
            "notes" : null,
            "pdfLink" : null,
            "appealLetterNotReceived" : false,
            "appealLetterReceived" : false,
            "requestedCopy" : null,
            "paymentMadeByClient" : null,
            "whenDate" : null,
            "paymentReceived": false,
            "paymentNotReceived": false,
            "dwpCall" : false
        }];
    }

    generateUniqueId() {
        return Date.now().toString(36) + Math.random().toString(36).substring(2);
    }

    handleRemoveRequest(event) {
        this.replies = this.replies.filter(item => item.id !== JSON.parse(JSON.stringify(event.detail)));
    }

    handleUpdateReply(event) {
        let currReply = JSON.parse(JSON.stringify(event.detail));
        const index = this.replies.findIndex(item => item.id == currReply.id);
        if (index != -1) {
             this.replies = [
                ...this.replies.slice(0, index),
                currReply,
                ...this.replies.slice(index + 1)
            ];
        }
    }

    get isEmptyListReplies() {
        return this.replies.length === 0 ? true : false;
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
        this.isDisabledCheckAgent = event.target.value ? false : true;
    }
}