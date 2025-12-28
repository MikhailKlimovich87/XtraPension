import { LightningElement, track, api, wire } from 'lwc';
import LightningAlert from 'lightning/alert';
import getAvailableAttachments from '@salesforce/apex/PrintingHouseReplyModalController.getAvailableDocuments';
import sendFilesToHMRC from '@salesforce/apex/PrintingHouseReplyModalController.sendDocs';

import { NavigationMixin } from "lightning/navigation";

export default class PrintingHouseReplyModal extends NavigationMixin(LightningElement) {
    selectedValues = [];
    isNotExistAttachments = true;
    @api appId;
    error;
    docs = [];
    replyDocs = [];
    currentStep = 1;
    selectAttach;
    selectAttachLabel;
    showSpinner = false;

    @api
    get attachmentOptions() {
        let attachments = [];
        if(this.docs) {
            attachments = this.docs.map( item => ({
                label : item.ContentDocument.Title,
                value : item.ContentDocumentId

            }));
        }
        return attachments;
    }

    @api
    get replyAttachmentOptions() {
        let attachments = [];
        if(this.replyDocs) {
            attachments = this.replyDocs.map( item => ({
                label : item.ContentDocument.Title,
                value : item.ContentDocumentId

            }));
        }
        return attachments;
    }

    connectedCallback() {
        getAvailableAttachments( {
            appId : this.appId
        }).then(result => {
            if(result) {
                this.docs = JSON.parse(JSON.stringify(result?.allAvailableFiles));
                this.replyDocs = JSON.parse(JSON.stringify(result?.replyFiles));
            }
            if(this.docs.length == 0) {
                this.handleAlert(
                    'Error',
                    'Please generate at least 1 REPLY file',
                    'error'
                );
            } else this.isNotExistAttachments = false;
        }).catch(error => {
            this.error = error;
        });
    }

    handleSelect(e) {
        this.selectedValues = e.detail.value;
    }

    closeModal(event) {
        event.preventDefault();
        const selectEvent = new CustomEvent('closemodal');
        this.dispatchEvent(selectEvent);
    }

    handleSend() {
        this.showSpinner = !this.showSpinner;
        sendFilesToHMRC( {
            appId : this.appId,
            attachFiles : this.selectedValues,
            fileIdToHMRC : this.selectAttach
        }).then(result => {
            if(result.isSent) {
                this.handleAlert(
                    'Success',
                    'Files was sent successfully',
                    'success'
                );
                this.showSpinner = !this.showSpinner;
                this.dispatchEvent(new CustomEvent('closemodal'));
            } else {
                this.handleAlert(
                    'Error',
                    'Error is ' + result.errorMessage,
                    'error'
                );
            }
        }).catch(error => {
            this.error = error;
            this.handleAlert(
                'Error',
                'Error is ' + error,
                'error'
            );
        });
    }

    handleSelectAttachment(event) {
        this.selectAttach = event.detail.value;
        this.selectAttachLabel = this.replyAttachmentOptions.find(item => item.value == this.selectAttach).label;
    }

    handleRemove() {
        this.selectAttach = null;
        this.selectAttachLabel = null;
    }

    async handleAlert(titleText, messageText, variant) {
        await LightningAlert.open({
            message: messageText,
            theme: variant,
            label: titleText,
        });
    }

    navigateToReplyFiles(event) {
        let documentId = event.currentTarget.getAttribute("value");
        var searchValue = this.docs.find(el => el.ContentDocumentId == documentId);
        this[NavigationMixin.Navigate]({
            type: "standard__namedPage",
            attributes: {
                pageName: "filePreview",
            },
            state: {
                recordIds: searchValue.ContentDocumentId
            },
        });
    }

    get isStepOne() {
        return this.currentStep == 1;
    }

    get isStepTwo() {
        return this.currentStep == 2;
    }

    get isSelectedEmailAttachments () {
        return !this.selectedValues.length > 0 && !this.isNotExistAttachments;
    }

    get isSelectedHMRCAttachments () {
        return !this.selectAttach && !this.isNotExistAttachments;
    }

    goToStepOne() {
        this.currentStep = 1;
    }

    goToStepTwo() {
        this.currentStep = 2;
    }

}