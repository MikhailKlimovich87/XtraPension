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
import PHONE_FIELD from "@salesforce/schema/Application__c.Related_Contact_Phone__c";
import FORMER_NAME_FIELD from "@salesforce/schema/Application__c.Full_Maiden_Previous_Name__c";
import UK_HOME_ADDRESS_FIELD from "@salesforce/schema/Application__c.Full_UK_Home_Address__c";

const fields = [
    FIRST_NAME_FIELD,
    SECOND_NAME_FIELD,
    NINO_FIELD,
    NAME_FIELD,
    HMRC_REF_FIELD,
    DATE_OF_BIRTH_FIELD,
    EMAIL_FIELD,
    FULL_ADDRESS_FIELD,
    PHONE_FIELD,
    FORMER_NAME_FIELD,
    UK_HOME_ADDRESS_FIELD
];

export default class DocEditor extends LightningElement {
    @api recordId;
    currentValue;
    currentLabel;
    isOpenModal = false;
    isOpenDWPStatusModal = false;
    isCertifiedDocModal = false;
    isDWP2RequestModal = false;
    isBounceLetterModal = false;
    isUpdateLetterModal = false;
    currentData;
    ninoTemplate;
    customTemplate;
    appealTemplate;
    currentJobTemplate;
    dwpStatusCheckTemplate;
    certifiedDocTemplate;
    euResidencyAppealTemplate;
    updateLetterTemplate;
    maidenNameTemplate;
    dwp2RequestTemplate;
    bounceLetterTemplate;
    euResidencyLetterTemplate;
    replyToEU_C2_C3_RejectionTemplate;
    class3AppealDespite3YearsTemplate;
    badErrorInC2DecisionTemplate;
    noShortfallTableProvidedTemplate;
    missingCorrespondenceTemplate;
    customCarnageTemplate;
    cf83NotReceivedLetterAgainTemplate;
    latePaymentAppealTemplate;
    higherLevelAppealTemplate;
    bodyValue;
    error;
    errorData;
    showSpinner = false;
    abroadEmployers;
    lastUkEmployer;
    dateOfReply;

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

    get phone() {
        return this.application.data.fields.Related_Contact_Phone__c.value;
    }

    get formerName() {
        return this.application.data.fields.Full_Maiden_Previous_Name__c.value;
    }

    get homeAddress() {
        return this.application.data.fields.Full_UK_Home_Address__c.value;
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
                    } else if(data.templateName === 'BOUNCE LETTER') {
                        this.bounceLetterTemplate = data.htmlValue;
                    } else if(data.templateName === '64-8 UPDATE LETTER') {
                        this.updateLetterTemplate = data.htmlValue;
                    } else if(data.templateName === 'EU RESIDENCY LETTER') {
                        this.euResidencyLetterTemplate = data.htmlValue;
                    } else if(data.templateName === 'REPLY TO \'EU C2 & C3 REJECTION\'') {
                        this.replyToEU_C2_C3_RejectionTemplate = data.htmlValue;
                    } else if(data.templateName === 'CLASS3 APPEAL DESPITE 3+ YEARS') {
                        this.class3AppealDespite3YearsTemplate = data.htmlValue;
                    } else if(data.templateName === 'BAD / ERROR IN C2 DECISION') {
                        this.badErrorInC2DecisionTemplate = data.htmlValue;
                    } else if(data.templateName === 'NO SHORTFALL TABLE PROVIDED') {
                        this.noShortfallTableProvidedTemplate = data.htmlValue;
                    } else if(data.templateName === 'CUSTOM CARNAGE (EG STEWART-LORD!)') {
                        this.customCarnageTemplate = data.htmlValue;
                    } else if(data.templateName === 'MISSING CORRESPONDENCE') {
                        this.missingCorrespondenceTemplate = data.htmlValue;
                    } else if(data.templateName === 'CF83 NOT RECEIVED LETTER AGAIN TO HMRC') {
                        this.cf83NotReceivedLetterAgainTemplate = data.htmlValue;
                    } else if(data.templateName === 'LATE PAYMENT APPEAL') {
                        this.latePaymentAppealTemplate = data.htmlValue;
                    } else if(data.templateName === 'HIGHER LEVEL / STAGE 2 APPEAL > STATUTORY REVIEW') {
                        this.higherLevelAppealTemplate = data.htmlValue;
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
            //{ label: 'EU Residency Appeal', value: this.euResidencyAppealTemplate},
            //{ label: 'Appeal', value: this.appealTemplate },
            //{ label: 'Custom', value: this.customTemplate },
            //{ label: 'NINO', value: this.ninoTemplate },
            //{ label: 'Current Job', value: this.currentJobTemplate},
            { label: 'DWP Status Check', value: this.dwpStatusCheckTemplate},
            //{ label: 'Certified Doc', value: this.certifiedDocTemplate},
            //{ label: 'Maiden Name', value: this.maidenNameTemplate},
            { label: 'DWP C2 Request', value: this.dwp2RequestTemplate},
            //{ label: 'Bounce Letter', value: this.bounceLetterTemplate},
            //{ label: '64-8 Update Letter', value: this.updateLetterTemplate},
            { label: 'EU Residency Letter', value: this.euResidencyLetterTemplate},
            { label: 'Reply to \'EU C2 & C3 Rejection\'', value: this.replyToEU_C2_C3_RejectionTemplate},
            { label: 'Class3 Appeal Despite 3+ Years', value: this.class3AppealDespite3YearsTemplate},
            { label: 'Bad / Error In C2 Decision', value: this.badErrorInC2DecisionTemplate},
            { label: 'No Shortfall Table Provided', value: this.noShortfallTableProvidedTemplate},
            { label: 'Custom Carnage (EG Stewart-Lord!)', value: this.customCarnageTemplate},
            { label: 'Missing Correspondence', value: this.missingCorrespondenceTemplate},
            { label: 'CF83 NOT Received letter again to HMRC', value: this.cf83NotReceivedLetterAgainTemplate},
            { label: 'Late Payment Appeal', value: this.latePaymentAppealTemplate},
            { label: 'Higher Level / Stage 2 Appeal > Statutory Review', value: this.higherLevelAppealTemplate},
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
            this.currentLabel === 'Maiden Name' ||
            this.currentLabel === 'EU Residency Letter' ||
            this.currentLabel === 'Reply to \'EU C2 & C3 Rejection\'' ||
            this.currentLabel === 'Class3 Appeal Despite 3+ Years' ||
            this.currentLabel === 'Bad / Error In C2 Decision' ||
            this.currentLabel === 'No Shortfall Table Provided' ||
            this.currentLabel === 'Custom Carnage (EG Stewart-Lord!)' ||
            this.currentLabel === 'Missing Correspondence' ||
            this.currentLabel === 'CF83 NOT Received letter again to HMRC' ||
            this.currentLabel === 'Late Payment Appeal'
        ) {
            this.isOpenModal = !this.isOpenModal;
        } else if(this.currentLabel === 'DWP Status Check') {
            this.isOpenDWPStatusModal = !this.isOpenDWPStatusModal;
        } else if(this.currentLabel === 'Certified Doc') {
            this.isCertifiedDocModal = !this.isCertifiedDocModal;
        } else if(this.currentLabel === 'DWP C2 Request' ||
            this.currentLabel === 'Higher Level / Stage 2 Appeal > Statutory Review') {
            this.isDWP2RequestModal = !this.isDWP2RequestModal;
        } else if(this.currentLabel === 'Bounce Letter') {
            this.isBounceLetterModal = !this.isBounceLetterModal;
        } else if(this.currentLabel === '64-8 Update Letter') {
            this.isUpdateLetterModal = !this.isUpdateLetterModal;
        }
    }

    closePopup() {
        this.isOpenModal = false;
        this.isOpenDWPStatusModal = false;
        this.isCertifiedDocModal = false;
        this.isDWP2RequestModal = false;
        this.isBounceLetterModal = false;
        this.isUpdateLetterModal = false;
    }

    handleGeneratePdf(event) {
        this.bodyValue = event.detail.body;
        this.dateOfReply = event.detail.dateData;
        this.sendDataToCreateFile(this.bodyValue, this.dateOfReply);
    }

    @api async sendDataToCreateFile(bodyInfo, replyDate) {
        this.showSpinner = !this.showSpinner;
        let fileData = {
            "applicationId": this.recordId,
            "fieldValue": bodyInfo,
            "typeOfTemplate":this.currentLabel,
            "dateOfReply":replyDate
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