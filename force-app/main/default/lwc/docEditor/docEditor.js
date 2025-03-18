import { LightningElement, api, wire } from 'lwc';
import getEmailTemplateData from '@salesforce/apex/DocumentEditorController.getEmailTemplateData';
import generateHMRCReplyFile from '@salesforce/apex/DocumentEditorController.generateHMRCReplyFile';
import { getRecord, getFieldValue } from "lightning/uiRecordApi";

import FIRST_NAME_FIELD from "@salesforce/schema/Application__c.First_Name__c";
import SECOND_NAME_FIELD from "@salesforce/schema/Application__c.Second_Name__c";
import NAME_FIELD from "@salesforce/schema/Application__c.Name";
import NINO_FIELD from "@salesforce/schema/Application__c.National_Insurance_Number__c";
import HMRC_REF_FIELD from "@salesforce/schema/Application__c.HMRC_Ref__c";
import DATE_OF_BIRTH_FIELD from "@salesforce/schema/Application__c.Date_Of_Birth__c";
import EMAIL_FIELD from "@salesforce/schema/Application__c.Email__c";
import FULL_ADDRESS_FIELD from "@salesforce/schema/Application__c.Full_Current_Address_Abroad__c";

const fields = [
    FIRST_NAME_FIELD,
    SECOND_NAME_FIELD,
    NINO_FIELD,
    NAME_FIELD,
    HMRC_REF_FIELD,
    DATE_OF_BIRTH_FIELD,
    EMAIL_FIELD,
    FULL_ADDRESS_FIELD
];

export default class DocEditor extends LightningElement {
    @api recordId;
    currentValue;
    currentLabel;
    isOpenModal = false;
    isOpenDWPStatusModal = false;
    isCertifiedDocModal = false;
    isDWP2RequestModal = false;
    currentData;
    ninoTemplate;
    customTemplate;
    appealTemplate;
    currentJobTemplate;
    dwpStatusCheckTemplate;
    certifiedDocTemplate;
    euResidencyAppealTemplate;
    maidenNameTemplate;
    dwp2RequestTemplate
    bodyValue;
    error;
    errorData;
    showSpinner = false;
    abroadEmployers;
    lastUkEmployer;

    @wire(getRecord, { recordId: "$recordId", fields })
    application;

    get firstName() {
        return getFieldValue(this.application.data, FIRST_NAME_FIELD);
    }

    get secondName() {
        return getFieldValue(this.application.data, SECOND_NAME_FIELD);
    }

    get appName() {
        return getFieldValue(this.application.data, NAME_FIELD);
    }

    get hmrcRef() {
        return getFieldValue(this.application.data, HMRC_REF_FIELD);
    }

    get nino() {
        return getFieldValue(this.application.data, NINO_FIELD);
    }

    get dateOfBirth() {
        return getFieldValue(this.application.data, DATE_OF_BIRTH_FIELD);
    }

    get customerEmail() {
        return getFieldValue(this.application.data, EMAIL_FIELD);
    }

    get addressInfo() {
        return this.application.data.fields.Full_Current_Address_Abroad__c.value;
    }

    connectedCallback(){
        this.getMessageData();
    }

    getMessageData() {
        getEmailTemplateData({
            applicationId : this.recordId
        })
        .then(result => {
            if (result) {
                this.abroadEmployers = result.abroadEmployers;
                this.lastUkEmployer = result.lastUkEmployer;
                console.log('this.abroadEmployers === ', this.abroadEmployers);
                console.log('this.lastUkEmployer === ', this.lastUkEmployer);
                result.htmlInfo.map(data => {
                    if (data.templateName ==='CUSTOM') {
                        this.customTemplate = data.htmlValue
                    } else if(data.templateName === 'NINO') {
                        this.ninoTemplate = data.htmlValue;
                    } else if(data.templateName === 'APPEAL') {
                        this.appealTemplate = data.htmlValue;
                    } else if(data.templateName === 'CURRENT JOB') {
                        this.currentJobTemplate = data.htmlValue;
                    } else if(data.templateName === 'DWP STATUS CHECK') {
                        this.dwpStatusCheckTemplate = data.htmlValue;
                    } else if(data.templateName === 'CERTIFIED DOC') {
                        this.certifiedDocTemplate = data.htmlValue;
                    } else if(data.templateName === 'EU RESIDENCY APPEAL') {
                        this.euResidencyAppealTemplate = data.htmlValue;
                    } else if(data.templateName === 'MAIDEN NAME') {
                        this.maidenNameTemplate = data.htmlValue;
                    } else if(data.templateName === 'DWP C2 REQUEST') {
                        this.dwp2RequestTemplate = data.htmlValue;
                    }
                });
            }
        }).catch(error => {
          this.error = error;
          console.log('error = ', this.error);
        });
    }

    get options() {
        return [
            { label: 'EU Residency Appeal', value: this.euResidencyAppealTemplate},
            { label: 'Appeal', value: this.appealTemplate },
            { label: 'Custom', value: this.customTemplate },
            { label: 'NINO', value: this.ninoTemplate },
            { label: 'Current Job', value: this.currentJobTemplate},
            { label: 'DWP Status Check', value: this.dwpStatusCheckTemplate},
            { label: 'Certified Doc', value: this.certifiedDocTemplate},
            { label: 'Maiden Name', value: this.maidenNameTemplate},
            { label: 'DWP C2 Request', value: this.dwp2RequestTemplate}
        ];
    }

    handleChange(event) {
        this.currentValue = event.detail.value;
        this.currentLabel = event.target.options.find(
            opt => opt.value === event.detail.value
        ).label;
    }

    handleClick() {
        if (this.currentLabel === 'Appeal' ||
            this.currentLabel === 'Custom' ||
            this.currentLabel === 'NINO' ||
            this.currentLabel === 'Current Job' ||
            this.currentLabel === 'EU Residency Appeal' ||
            this.currentLabel === 'Maiden Name') {
            this.isOpenModal = !this.isOpenModal;
        } else if(this.currentLabel === 'DWP Status Check') {
            this.isOpenDWPStatusModal = !this.isOpenDWPStatusModal;
        } else if(this.currentLabel === 'Certified Doc') {
            this.isCertifiedDocModal = !this.isCertifiedDocModal;
        } else if(this.currentLabel === 'DWP C2 Request') {
            this.isDWP2RequestModal = !this.isDWP2RequestModal;
        }
    }

    closePopup() {
        this.isOpenModal = false;
        this.isOpenDWPStatusModal = false;
        this.isCertifiedDocModal = false;
        this.isDWP2RequestModal = false;
    }

    handleGeneratePdf(event) {
        this.bodyValue = event.detail;
        this.sendDataToCreateFile(this.bodyValue);
    }

    @api async sendDataToCreateFile(bodyInfo) {
        this.showSpinner = !this.showSpinner;
        let fileData = {
            "applicationId": this.recordId,
            "fieldValue": bodyInfo,
            "typeOfTemplate":this.currentLabel
        }
        await generateHMRCReplyFile({
            messageData: fileData
        }).then(result => {
            console.log(result);
        }).catch(error => {
          this.error = error;
        }).finally(() => {
            this.showSpinner = !this.showSpinner;
            window.location.reload();
        });
    }
}