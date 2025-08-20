import { LightningElement, wire, track, api } from 'lwc';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import APPLICATION_OBJECT from '@salesforce/schema/Application__c';
import CHECK_AGENT_FIELD from "@salesforce/schema/Application__c.Check_Agent__c";
import SENT_TO_FIELD from "@salesforce/schema/Application__c.Sent_to__c";

export default class LeftBlockCheckModule extends LightningElement {
    searchValue;
    appName = '';
    @api
    searchApps;
    checkAgents = [];
    sentToValues = [];
    @track
    checkReply = {
        "agent" : null,
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
        "pdfLink" : null
    }
    isExistSearchValue = false;
    isDisabledCheckAgent = true;
    isNotReceivedRequest = false;

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

    handleChange(event) {
        let dataSetId =  event.target.dataset.id;
        switch (dataSetId) {
            case "agent":
                this.checkReply.agent = event.target.value;
                this.isDisabledCheckAgent = event.target.value ? false : true;
                break;
            case "not_received":
                this.checkReply.notReceived = event.target.checked;
                this.isNotReceivedRequest = event.target.checked ? true : false;
                break;
            case 'c2':
                this.checkReply.c2 = event.target.checked;
                break;
            case 'work_item':
                this.checkReply.workItem = event.target.checked;
                break;
            case 'bad_nino':
                this.checkReply.badNINO = event.target.checked;
                break;
            case 'bad_info':
                this.checkReply.badInfo = event.target.checked;
                break;
            case 'processing':
                this.checkReply.processing = event.target.checked;
                break;
            case 'c3':
                this.checkReply.c3 = event.target.checked;
                break;
            case 'dwp':
                this.checkReply.dwp = event.target.checked;
                break;
            case 'X64_8':
                this.checkReply.X64_8 = event.target.checked;
                break;
            case 'reject':
                this.checkReply.reject = event.target.checked;
                break;
            case 'sent_to':
                this.checkReply.sentTo = event.target.value;
                break;
            case 'sent_date':
                this.checkReply.sentDate = event.target.value;
                break;
            case 'notes':
                this.checkReply.notes = event.target.value;
                break;
            case 'pdf_link':
                this.checkReply.pdfLink = event.target.value;
                break;
        }
    }

    handleSave() {
        this.handleValidation();
        this.dispatchEvent(
            new CustomEvent('savecheckreply', {
                "detail" :  this.checkReply
            })
        );
    }

    handleSearchChange(event) {
        this.appName = event.target.value;
        this.checkReply.appName = this.appName;
        let currApp = this.searchApps.find(app => app.Name == this.appName);
        if(currApp) {
            this.searchValue = currApp;
            this.isExistSearchValue = true;
        } else {
            this.searchValue = event.target.value;
            this.isExistSearchValue = false;
        }
    }

    @api
    get isDisabledClientButton() {
        return !this.isExistSearchValue;
    }

    handleCopy(event) {
        let dataSetId = event.target.dataset.id;
        let copyMessageData = '';
        switch(dataSetId) {
            case 'initial_button':
                copyMessageData =
                    'Hi, this is ' + this.checkReply.agent + ', an agent. Just wanted to check if our client\'s CF83 form has come through.';
                this.copyInfo(copyMessageData);
                break;
            case 'client_button':
                copyMessageData +=  this.searchValue.National_Insurance_Number__c ? ('NINO = ' + this.searchValue.National_Insurance_Number__c + '………') : '';
                copyMessageData +=
                    'DOB = ' + this.searchValue.Date_Of_Birth__c + '………' +
                    'Name = ' + this.searchValue.First_Name__c + ' ' + this.searchValue.Second_Name__c + '………' +
                    'Addr = ' + this.searchValue.Full_Current_Address_Abroad__c + '………' +
                    'Phone = ' + this.searchValue.Related_Contact_Phone__c;
                copyMessageData += this.searchValue.Full_Maiden_Previous_Name__c ? ('………Former Name: ' + this.searchValue.Full_Maiden_Previous_Name__c) : '';
                this.copyInfo(copyMessageData.replaceAll("<br>", ", "));
                break;
            case 'agent_button':
                copyMessageData =
                    'JGBA Ltd, Suite 2/11 Pure Offices, 1 Ainslie Road, Hillington, Glasgow G52 4RU - Tel 0141 301 1480 (Previous address Suite 1/31 Pure Offices)';
                this.copyInfo(copyMessageData);
                break;
        }
    }

    copyInfo(dataOfCopy) {
        const input = document.createElement("textarea");
        document.body.appendChild(input);
        input.select();
        if(navigator.clipboard){
            copy(dataOfCopy);
            this.showToastMessage(
                'Success',
                'You copied the data',
                'success'
            );
        } else {
            this.showToastMessage(
                'Error',
                'You didn\'t copy the data',
                'error'
            );
        }
        document.body.removeChild(input);
    }

    showToastMessage(titleData, messageInfo, toastVariant) {
        this.dispatchEvent(new ShowToastEvent({
            title: titleData,
            message: messageInfo,
            variant: toastVariant,
        }));
    }

    handleValidation() {
        const agentInputElement = this.template.querySelector('[data-id="agent"]');
        const appNoInputElement = this.template.querySelector('[data-id="app_number"]');
        const notesInputElement = this.template.querySelector('[data-id="notes"]');
        const pdfLinkInputElement = this.template.querySelector('[data-id="pdf_link"]');
        let isValid = true;

        if (!agentInputElement.value) {
            agentInputElement.setCustomValidity('Check Agent cannot be empty.');
            isValid = false;
        } else {
            agentInputElement.setCustomValidity(''); // Clear previous error
        }
        agentInputElement.reportValidity();

        if (!appNoInputElement.value) {
            appNoInputElement.setCustomValidity('App No cannot be empty.');
            isValid = false;
        } else {
            appNoInputElement.setCustomValidity(''); // Clear previous error
        }
        appNoInputElement.reportValidity();

        if (!notesInputElement.value) {
            notesInputElement.setCustomValidity('Notes cannot be empty.');
            isValid = false;
        } else {
            notesInputElement.setCustomValidity(''); // Clear previous error
        }
        notesInputElement.reportValidity();

        if (!pdfLinkInputElement.value) {
            pdfLinkInputElement.setCustomValidity('PDF GDrive Link cannot be empty.');
            isValid = false;
        } else {
            pdfLinkInputElement.setCustomValidity(''); // Clear previous error
        }
        pdfLinkInputElement.reportValidity();

        if (!isValid) {
            this.showToastMessage(
                'Error',
                'Some of fields is empty!!! Please check',
                'error'
            );
        }
    }

    get isAppealAppUndersXPLetterSent() {
        return this.searchValue.Appeal_Application__c == true &&
                    (this.currApp.Status__c == 'Posted' ||
                     this.currApp.Status__c == '64-8 Bounce' ||
                     this.currApp.Status__c == 'HMRC Reply 1' ||
                     this.currApp.Status__c == 'DWP Teleclaim' ||
                     this.currApp.Status__c == 'DWP 2 Emails Sent' ||
                     this.currApp.Status__c == 'DWP Shortfall Pending' ||
                     this.currApp.Status__c == 'XP Letter Sent')? true : false;
    }

    get isAppealAppAboveXPLetterSent() {
        return this.searchValue.Appeal_Application__c == true &&
                     (this.currApp.Status__c == 'HMRC Reply 2' ||
                     this.currApp.Status__c == 'Send to Client' ||
                     this.currApp.Status__c == 'Agent Call' ||
                     this.currApp.Status__c == 'Charge CC' ||
                     this.currApp.Status__c == 'Annual Service' ||
                     this.currApp.Status__c == 'No Annual') ? true : false;
    }
}

export const copy = async textToCopy =>
    await navigator.clipboard.writeText(textToCopy)
                             .catch(err =>
                                console.error(JSON.stringify(err)),
                                err => console.error(JSON.stringify(err)
                                )
                            );