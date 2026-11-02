import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getEmailTemplateData from '@salesforce/apex/DocumentEditorController.getEmailTemplateData';
import generateHMRCReplyFile from '@salesforce/apex/DocumentEditorController.generateHMRCReplyFile';
import changeCustomLetter from '@salesforce/apex/DocumentsContentController.changeCustomLetter';
import pdfAction from '@salesforce/apex/DocumentsContentController.pdfAction';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

import FIRST_NAME_FIELD from '@salesforce/schema/Application__c.First_Name__c';
import SECOND_NAME_FIELD from '@salesforce/schema/Application__c.Second_Name__c';
import NAME_FIELD from '@salesforce/schema/Application__c.Name';
import NINO_FIELD from '@salesforce/schema/Application__c.National_Insurance_Number__c';
import HMRC_REF_FIELD from '@salesforce/schema/Application__c.HMRC_Ref__c';
import DATE_OF_BIRTH_FIELD from '@salesforce/schema/Application__c.Date_Of_Birth__c';
import EMAIL_FIELD from '@salesforce/schema/Application__c.Email__c';
import FULL_ADDRESS_FIELD from '@salesforce/schema/Application__c.Full_Current_Address_Abroad__c';
import PHONE_FIELD from '@salesforce/schema/Application__c.Related_Contact_Phone__c';
import FORMER_NAME_FIELD from '@salesforce/schema/Application__c.Full_Maiden_Previous_Name__c';
import UK_HOME_ADDRESS_FIELD from '@salesforce/schema/Application__c.Full_UK_Home_Address__c';

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
    isOpenDWP_HMRC_C2_RejectionModal = false;
    isOpenWorkHistoryModal = false;
    isOpenRefundRequestModal = false;
    isOpenCustomLetterModal = false;
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
    c2ClientRejectionTemplate;
    hmrcClass2ReassessmentTemplate;
    bodyValue;
    error;
    errorData;
    showSpinner = false;
    abroadEmployers;
    lastUkEmployer;
    dateOfReply;
    currApplication;
    requestData;

    @wire(getRecord, { recordId: '$recordId', fields })
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

    connectedCallback() {
        this.getMessageData();
    }

    getMessageData() {
        getEmailTemplateData({
            applicationId: this.recordId
        })
            .then((result) => {
                if (result) {
                    this.abroadEmployers = result.abroadEmployers;
                    console.log('abroadEmployers: ' + JSON.stringify(this.abroadEmployers));
                    this.lastUkEmployer = result.lastUkEmployer;
                    console.log('lastUkEmployer: ' + JSON.stringify(this.lastUkEmployer));
                    this.currApplication = result.currentApplication;
                    result.htmlInfo.map((data) => {
                        if (data.templateName === 'CUSTOM') {
                            this.customTemplate = data.htmlValue;
                        } else if (data.templateName === 'NINO') {
                            this.ninoTemplate = data.htmlValue;
                        } else if (data.templateName === 'APPEAL') {
                            this.appealTemplate = data.htmlValue;
                        } else if (data.templateName === 'CURRENT JOB') {
                            this.currentJobTemplate = data.htmlValue;
                        } else if (data.templateName === 'DWP STATUS CHECK') {
                            this.dwpStatusCheckTemplate = data.htmlValue;
                        } else if (data.templateName === 'CERTIFIED DOC') {
                            this.certifiedDocTemplate = data.htmlValue;
                        } else if (data.templateName === 'EU RESIDENCY APPEAL') {
                            this.euResidencyAppealTemplate = data.htmlValue;
                        } else if (data.templateName === 'MAIDEN NAME') {
                            this.maidenNameTemplate = data.htmlValue;
                        } else if (data.templateName === 'DWP C2 REQUEST') {
                            this.dwp2RequestTemplate = data.htmlValue;
                        } else if (data.templateName === 'BOUNCE LETTER') {
                            this.bounceLetterTemplate = data.htmlValue;
                        } else if (data.templateName === '64-8 UPDATE LETTER') {
                            this.updateLetterTemplate = data.htmlValue;
                        } else if (data.templateName === 'EU RESIDENCY LETTER') {
                            this.euResidencyLetterTemplate = data.htmlValue;
                        } else if (data.templateName === "REPLY TO 'EU C2 & C3 REJECTION'") {
                            this.replyToEU_C2_C3_RejectionTemplate = data.htmlValue;
                        } else if (data.templateName === 'CLASS3 APPEAL DESPITE 3+ YEARS') {
                            this.class3AppealDespite3YearsTemplate = data.htmlValue;
                        } else if (data.templateName === 'BAD / ERROR IN C2 DECISION') {
                            this.badErrorInC2DecisionTemplate = data.htmlValue;
                        } else if (data.templateName === 'NO SHORTFALL TABLE PROVIDED') {
                            this.noShortfallTableProvidedTemplate = data.htmlValue;
                        } else if (data.templateName === 'CUSTOM CARNAGE (EG STEWART-LORD!)') {
                            this.customCarnageTemplate = data.htmlValue;
                        } else if (data.templateName === 'MISSING CORRESPONDENCE') {
                            this.missingCorrespondenceTemplate = data.htmlValue;
                        } else if (data.templateName === 'CF83 NOT RECEIVED LETTER AGAIN TO HMRC') {
                            this.cf83NotReceivedLetterAgainTemplate = data.htmlValue;
                        } else if (data.templateName === 'LATE PAYMENT APPEAL') {
                            this.latePaymentAppealTemplate = data.htmlValue;
                        } else if (data.templateName === 'HIGHER LEVEL / STAGE 2 APPEAL > STATUTORY REVIEW') {
                            this.higherLevelAppealTemplate = data.htmlValue;
                        } else if (data.templateName === 'DWP/HMRC C2 REJECTION') {
                            this.c2ClientRejectionTemplate = data.htmlValue;
                        } else if (data.templateName === 'HRMC_CLASS_2_REASSESSMENT') {
                            this.hmrcClass2ReassessmentTemplate = data.htmlValue;
                        }
                    });
                }
            })
            .catch((error) => {
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
            { label: 'DWP Status Check', value: this.dwpStatusCheckTemplate },
            //{ label: 'Certified Doc', value: this.certifiedDocTemplate},
            //{ label: 'Maiden Name', value: this.maidenNameTemplate},
            { label: 'DWP C2 Request', value: this.dwp2RequestTemplate },
            //{ label: 'Bounce Letter', value: this.bounceLetterTemplate},
            //{ label: '64-8 Update Letter', value: this.updateLetterTemplate},
            { label: 'EU Residency Letter', value: this.euResidencyLetterTemplate },
            { label: "Reply to 'EU C2 & C3 Rejection'", value: this.replyToEU_C2_C3_RejectionTemplate },
            { label: 'Class3 Appeal Despite 3+ Years', value: this.class3AppealDespite3YearsTemplate },
            { label: 'Bad / Error In C2 Decision', value: this.badErrorInC2DecisionTemplate },
            { label: 'No Shortfall Table Provided', value: this.noShortfallTableProvidedTemplate },
            { label: 'Custom Carnage (EG Stewart-Lord!)', value: this.customCarnageTemplate },
            { label: 'Missing Correspondence', value: this.missingCorrespondenceTemplate },
            { label: 'CF83 NOT Received letter again to HMRC', value: this.cf83NotReceivedLetterAgainTemplate },
            { label: 'Late Payment Appeal', value: this.latePaymentAppealTemplate },
            { label: 'Higher Level / Stage 2 Appeal > Statutory Review', value: this.higherLevelAppealTemplate },
            { label: 'DWP/HMRC C2 Rejection', value: this.c2ClientRejectionTemplate },
            { label: 'Work History', value: 'Work History' },
            { label: 'HMRC Refund Request', value: 'HMRC Refund Request' },
            { label: 'Custom Letter', value: 'Custom Letter' },
            { label: 'HMRC Class 2 Reassessment', value: this.hmrcClass2ReassessmentTemplate }
        ];
    }

    handleChange(event) {
        console.log('Selected value: ', event.detail.value);
        this.currentValue = event.detail.value;
        const selectedOption = this.options.find((opt) => opt.value === event.detail.value);
        this.currentLabel = selectedOption ? selectedOption.label : undefined;
        console.log('Selected label: ', this.currentLabel);
    }

    handleClick() {
        if (
            this.currentLabel === 'Appeal' ||
            this.currentLabel === 'Custom' ||
            this.currentLabel === 'NINO' ||
            this.currentLabel === 'Current Job' ||
            this.currentLabel === 'EU Residency Appeal' ||
            this.currentLabel === 'Maiden Name' ||
            this.currentLabel === 'EU Residency Letter' ||
            this.currentLabel === "Reply to 'EU C2 & C3 Rejection'" ||
            this.currentLabel === 'Class3 Appeal Despite 3+ Years' ||
            this.currentLabel === 'Bad / Error In C2 Decision' ||
            this.currentLabel === 'No Shortfall Table Provided' ||
            this.currentLabel === 'Custom Carnage (EG Stewart-Lord!)' ||
            this.currentLabel === 'Missing Correspondence' ||
            this.currentLabel === 'CF83 NOT Received letter again to HMRC' ||
            this.currentLabel === 'Late Payment Appeal' ||
            this.currentLabel === 'HMRC Class 2 Reassessment'
        ) {
            this.isOpenModal = !this.isOpenModal;
        } else if (this.currentLabel === 'DWP Status Check') {
            this.isOpenDWPStatusModal = !this.isOpenDWPStatusModal;
        } else if (this.currentLabel === 'Certified Doc') {
            this.isCertifiedDocModal = !this.isCertifiedDocModal;
        } else if (
            this.currentLabel === 'DWP C2 Request' ||
            this.currentLabel === 'Higher Level / Stage 2 Appeal > Statutory Review'
        ) {
            this.isDWP2RequestModal = !this.isDWP2RequestModal;
        } else if (this.currentLabel === 'Bounce Letter') {
            this.isBounceLetterModal = !this.isBounceLetterModal;
        } else if (this.currentLabel === '64-8 Update Letter') {
            this.isUpdateLetterModal = !this.isUpdateLetterModal;
        } else if (this.currentLabel === 'DWP/HMRC C2 Rejection') {
            this.isOpenDWP_HMRC_C2_RejectionModal = !this.isOpenDWP_HMRC_C2_RejectionModal;
        } else if (this.currentLabel === 'Work History') {
            this.isOpenWorkHistoryModal = !this.isOpenWorkHistoryModal;
        } else if (this.currentLabel === 'HMRC Refund Request') {
            this.isOpenRefundRequestModal = !this.isOpenRefundRequestModal;
        } else if (this.currentLabel === 'Custom Letter') {
            this.isOpenCustomLetterModal = !this.isOpenCustomLetterModal;
        }
    }

    closePopup() {
        this.isOpenModal = false;
        this.isOpenDWPStatusModal = false;
        this.isCertifiedDocModal = false;
        this.isDWP2RequestModal = false;
        this.isBounceLetterModal = false;
        this.isUpdateLetterModal = false;
        this.isOpenDWP_HMRC_C2_RejectionModal = false;
        this.isOpenWorkHistoryModal = false;
        this.isOpenRefundRequestModal = false;
        this.isOpenCustomLetterModal = false;
    }

    handleGeneratePdf(event) {
        this.bodyValue = event.detail.body;
        this.dateOfReply = event.detail.dateData;
        this.sendDataToCreateFile(this.bodyValue, this.dateOfReply);
    }

    @api async sendDataToCreateFile(bodyInfo, replyDate) {
        this.showSpinner = !this.showSpinner;
        let fileData = {
            applicationId: this.recordId,
            fieldValue: bodyInfo,
            typeOfTemplate: this.currentLabel,
            dateOfReply: replyDate
        };
        await generateHMRCReplyFile({
            messageData: fileData
        })
            .then((result) => {
                console.log(result);
            })
            .catch((error) => {
                this.error = error;
            })
            .finally(() => {
                this.showSpinner = !this.showSpinner;
                window.location.reload();
            });
    }

    regenerateCustomLetter(event) {
        this.requestData = {
            applicationId: this.recordId,
            freeformTextLine1: event.detail.freeformTextLine1,
            freeformTextLine2: event.detail.freeformTextLine2,
            freeformTextLine3: event.detail.freeformTextLine3,
            freeformTextLine4: event.detail.freeformTextLine4,
            freeformTextLine5: event.detail.freeformTextLine5,
            newPreviousAddressData: event.detail.newPreviousAddressData,
            newEmployerData: event.detail.newEmployerCheckboxData,
            customLetterDate: event.detail.currentDate
        };
        this.changeApplication();
    }

    changeApplication() {
        this.showSpinner = true;
        changeCustomLetter({
            letterData: JSON.parse(JSON.stringify(this.requestData))
        })
            .then((result) => {
                if (result == 'true') {
                    this.createNewContentDocument();
                    const evt = new ShowToastEvent({
                        title: 'Success',
                        message: 'You have successfully changed the Custom Letter',
                        variant: 'success'
                    });
                    this.dispatchEvent(evt);
                }
            })
            .catch((error) => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: "You didn't changed the Custom Letter. Error is: " + error,
                        variant: 'error'
                    })
                );
            })
            .finally(() => {
                this.showSpinner = false;
                this.isOpenCustomLetterModal = false;
            });
    }

    createNewContentDocument() {
        pdfAction({
            applicationId: this.recordId,
            isReply: true
        })
            .then((result) => {
                window.location.reload();
            })
            .catch((error) => {
                this.isOpenCustomLetterModal = false;
            });
    }
}