import { LightningElement, wire, api } from 'lwc';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import uploadFile from '@salesforce/apex/UploadHMRCReplyController.uploadFile'
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import APPLICATION_OBJECT from '@salesforce/schema/Application__c';
import TYPE_OF_EMPLOYMENT_FIELD from "@salesforce/schema/Application__c.HMRC_Reply_Status__c";
import HMRC_REF_FIELD from "@salesforce/schema/Application__c.HMRC_Ref__c";
import FIRST_NAME_FIELD from "@salesforce/schema/Application__c.First_Name__c";
import SECOND_NAME_FIELD from "@salesforce/schema/Application__c.Second_Name__c";
import NAME_FIELD from "@salesforce/schema/Application__c.Name";
import UK_WORK_FIELD from "@salesforce/schema/Application__c.Years_Of_Work_In_The_UK__c";
import SHORTFALL_FIELD from "@salesforce/schema/Application__c.Shortfall__c";
import CASEWORKER_FIELD from "@salesforce/schema/Application__c.Caseworker__c";

export default class UploadHMRCReply extends LightningElement {
    @api
    recordId;

    currentReplyType;
    currentRef;
    currentFile;
    currentShortfall;
    currentCaseworker;
    fileName;
    moveToStatus = 'Not Move';

    typesOfHMRCReply = [];

    get shortfallData() {
        return [
            { label: 'Yes', value: 'Yes' },
            { label: 'No', value: 'No' }
        ];
    }

    get moveToStatusData() {
        return [
            { label: 'Not Move', value: 'Not Move' },
            { label: '64-8 Bounce', value: '64-8 Bounce' },
            { label: 'HMRC Reply 1', value: 'HMRC Reply 1' },
            { label: 'HMRC Reply 2', value: 'HMRC Reply 2' },
            { label: 'Send to Client', value: 'Send to Client'}
        ];
    }

    showSpinner= false;

    @wire(getObjectInfo, { objectApiName: APPLICATION_OBJECT })
    applicationInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$applicationInfo.data.defaultRecordTypeId',
        fieldApiName: TYPE_OF_EMPLOYMENT_FIELD })
    replyTypes({ error, data }) {
        if (data) {
            this.typesOfHMRCReply = [...data.values];
            this.typesOfHMRCReply.push({value:'VOLUNTARY NI PAYMENT RECEIPT', label:'VOLUNTARY NI PAYMENT RECEIPT'});
        }
        if(error) {
            console.log('Error uploading picklist values');
        }
    }

    @wire(getRecord, {
        recordId: '$recordId',
        fields: [NAME_FIELD, FIRST_NAME_FIELD, SECOND_NAME_FIELD, SHORTFALL_FIELD, HMRC_REF_FIELD, UK_WORK_FIELD, CASEWORKER_FIELD]
    })
    application;

    get hmrcRef() {
        let hrmcRefData = getFieldValue(this.application.data, HMRC_REF_FIELD);
        if (hrmcRefData) {
            return hrmcRefData;
        } else return 'IC';
    }

    get ukWork() {
        return getFieldValue(this.application.data, UK_WORK_FIELD);
    }

    get shortfall() {
        return getFieldValue(this.application.data, SHORTFALL_FIELD);
    }

    get caseworker() {
        return getFieldValue(this.application.data, CASEWORKER_FIELD);
    }

    handleChangeType(event) {
        this.currentReplyType = event.detail.value;
    }

    handleChangeYear(event) {
        this.currentYears = event.detail.value;
    }

    handleChangeRef(event) {
        this.currentRef = event.detail.value;
    }

    handleChangeShortfall(event) {
        this.currentShortfall = event.detail.value;
    }

    handleChangeCaseworker(event) {
        this.currentCaseworker = event.detail.value;
    }

    handleChangeStatus(event) {
        this.moveToStatus = event.detail.value;
    }

    handleFilesSelected(event) {
        this.currentFiles = event.target.files[0];
        let reader = new FileReader();
        reader.onload = () => {
            var base64 = reader.result.split(',')[1];
            this.currentFile =  base64;
            this.fileName = getFieldValue(this.application.data, FIRST_NAME_FIELD) + '_' +
                            getFieldValue(this.application.data, SECOND_NAME_FIELD) + '_' +
                            getFieldValue(this.application.data, NAME_FIELD) + '_' +
                            this.currentReplyType +
                            this.currentFiles.name.substring(this.currentFiles.name.lastIndexOf('.'));
        }
        reader.readAsDataURL(this.currentFiles);
    }

    async handleUploadFile() {
        if (!this.currentFile || !this.currentReplyType) {
            let titleEmptyData = `Please, specify all data before uploading`;
            this.toast(titleEmptyData, 'error');
        } else {
            this.showSpinner = !this.showSpinner;
            let requestData = {
                "recordId"    : this.recordId,
                "fileData"    : this.currentFile,
                "ref"         : this.currentRef ? this.currentRef : this.hmrcRef,
                "typeOfReply" : this.currentReplyType,
                "years"       : this.currentYears ? this.currentYears : this.ukWork,
                "fileName"    : this.fileName,
                "shortfall"   : this.currentShortfall ? this.currentShortfall : this.shortfall,
                "caseworker"  : this.currentCaseworker ? this.currentCaseworker : this.caseworker,
                "status"      : this.moveToStatus == 'Not Move' ? null : this.moveToStatus
            };
            await uploadFile({
                request : requestData
            }).then(result => {
                this.currentFile = null;
                this.fileName = null;
                let title = `File was uploaded successfully!`
                this.toast(title, 'success');
                this.showSpinner = !this.showSpinner;
                window.location.reload();
            }).catch(error => {
                console.log('error === ', error);
                let errorTitle = 'File didn\'t upload. The error is ' + error.body.message;
                this.toast(errorTitle, 'error');
                this.showSpinner = !this.showSpinner;
            })
        }
    }

    toast(title, variantType){
        const toastEvent = new ShowToastEvent({
            title,
            variant: variantType
        })
        this.dispatchEvent(toastEvent)
    }
}