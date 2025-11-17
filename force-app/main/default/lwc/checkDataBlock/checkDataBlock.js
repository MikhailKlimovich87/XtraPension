import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class CheckDataBlock extends LightningElement {
    @api sentToData = [];
    @api checkRequest;
    currCheckReply;
    @api searchApps;
    searchValue;
    appName = '';
    isOpenConfirmModal = false;
    isExistSearchValue = false;
    isNotReceivedRequest = false;
    @api isAddedCheckAgent;
    @api agent;

    connectedCallback() {
        this.currCheckReply = JSON.parse(JSON.stringify(this.checkRequest));
    }

    handleSearchChange(event) {
        this.appName = event.target.value;
        this.currCheckReply.appName = this.appName;

        let currApp = this.searchApps.find(app => {
            let searchValue = app.Name.includes("A0") ?
                app.Name.replace("A0", "") :
                app.Name.includes("A") ?
                    app.Name.replace("A", ""):
                    null;
            return searchValue == this.appName
        });

        if(currApp) {
            this.searchValue = currApp;
            this.isExistSearchValue = true;
            this.dispatchEvent(
                new CustomEvent('updatecheckreply', {
                    "detail" :  this.currCheckReply
                })
            );
        } else {
            this.searchValue = event.target.value;
            this.isExistSearchValue = false;
        }
    }
    handleCopy(event) {
        let dataSetId = event.target.dataset.id;
        let copyMessageData = '';
        switch(dataSetId) {
            case 'initial_button':
                copyMessageData = this.searchValue.Status__c == 'XP Letter Sent' && this.searchValue.Appeal_Application__c == true ?
                    'Hi, this is ' + this.agent + ', an agent. Just wanted to check if our client\'s CF83 Appeal has come through.' :
                    this.searchValue.Status__c == 'Annual Service' || this.searchValue.Status__c == 'No Annual' || this.searchValue.Status__c == 'Closed' ?
                        'Hi, this is ' + this.agent + ', an agent. Just wanted to check if our client\'s voluntary contribution payment has come through and if it was allocated to their National Insurance Record already.' :
                        'Hi, this is ' + this.agent + ', an agent. Just wanted to check if our client\'s CF83 form has come through.';
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

    get isAppealOnXPLetterSent() {
        return this.searchValue &&
               this.searchValue.Appeal_Application__c == true &&
               this.searchValue.Status__c == 'XP Letter Sent' &&
               this.searchValue.Status__c != 'Annual Service' &&
               this.searchValue.Status__c != 'No Annual' &&
               this.searchValue.Status__c != 'Closed' ? true : false;
    }

    get isOnTheLastStages() {
        return this.searchValue &&
               (this.searchValue.Status__c == 'Annual Service' ||
                this.searchValue.Status__c == 'No Annual' ||
                this.searchValue.Status__c == 'Closed') ? true : false;
    }

    get isNotOnTheLastStages() {
        return !this.searchValue ||
               (this.searchValue.Status__c != 'Annual Service' &&
                this.searchValue.Status__c != 'No Annual' &&
                this.searchValue.Status__c != 'Closed') ? true : false;
    }

    get isAppealNotOnXPLetterSent() {
        return !this.isAppealOnXPLetterSent ? true : false;
    }

    get isEmptyAppList() {
        return this.searchApps == null ? true : false;
    }

    openC2Modal() {
        this.isOpenConfirmModal =
               this.searchValue &&
               (this.currCheckReply.c2 == true ||
               this.currCheckReply.c3 == true) &&
               (this.searchValue.Status__c == 'XP Letter Sent' ||
               this.searchValue.Status__c == 'Posted' ||
               this.searchValue.Status__c == '64-8 Bounce' ||
               this.searchValue.Status__c == 'HMRC Reply 1' ||
               this.searchValue.Status__c == 'DWP Teleclaim' ||
               this.searchValue.Status__c == 'DWP 2 Emails Sent' ||
               this.searchValue.Status__c == 'DWP Shortfall Pending' ||
               this.searchValue.Status__c == 'HMRC Reply 2') ? true : false;

    }

    handleRemoveRequest() {
        this.dispatchEvent(
            new CustomEvent('removerequest', {
                "detail" :  this.checkRequest.id
            })
        );
    }

    handleChange(event) {
        let dataSetId =  event.target.dataset.id;
        switch (dataSetId) {
            case "not_received":
                this.currCheckReply.notReceived = event.target.checked;
                this.isNotReceivedRequest = event.target.checked ? true : false;
                break;
            case 'c2':
                this.currCheckReply.c2 = event.target.checked;
                this.openC2Modal();
                break;
            case 'work_item':
                this.currCheckReply.workItem = event.target.checked;
                break;
            case 'bad_nino':
                this.currCheckReply.badNINO = event.target.checked;
                break;
            case 'bad_info':
                this.currCheckReply.badInfo = event.target.checked;
                break;
            case 'processing':
                this.currCheckReply.processing = event.target.checked;
                break;
            case 'c3':
                this.currCheckReply.c3 = event.target.checked;
                this.openC2Modal();
                break;
            case 'dwp':
                this.currCheckReply.dwp = event.target.checked;
                break;
            case 'X64_8':
                this.currCheckReply.X64_8 = event.target.checked;
                break;
            case 'reject':
                this.currCheckReply.reject = event.target.checked;
                break;
            case 'sent_to':
                this.currCheckReply.sentTo = event.target.value;
                break;
            case 'sent_date':
                this.currCheckReply.sentDate = event.target.value;
                break;
            case 'notes':
                this.currCheckReply.notes = event.target.value;
                break;
            case 'pdf_link':
                this.currCheckReply.pdfLink = event.target.value;
                break;
            case 'appeal_letter_not_received':
                this.currCheckReply.appealLetterNotReceived = event.target.checked;
                break;
            case 'appeal_letter_received':
                this.currCheckReply.appealLetterReceived = event.target.checked;
                break;
            case 'appeal_letter_received':
                this.currCheckReply.appealLetterReceived = event.target.checked;
                break;
            case 'payment-received':
                this.currCheckReply.paymentReceived = event.target.checked;
                break;
            case 'payment-not-received':
                this.currCheckReply.paymentNotReceived = event.target.checked;
                break;
        }
        this.dispatchEvent(
            new CustomEvent('updatecheckreply', {
                "detail" :  this.currCheckReply
            })
        );
    }

    handleCancelModal() {
        this.isOpenConfirmModal = !this.isOpenConfirmModal;
    }

    handleRequestedCopy(event) {
        this.currCheckReply.requestedCopy = event.detail.requestCopy;
        this.currCheckReply.paymentMadeByClient = event.detail.paymentMadeByClient;
        this.currCheckReply.whenDate = event.detail.whenData;
   }

    get isDisabledClientButton() {
        return !this.isExistSearchValue;
    }

    get isDisabledInitialButton() {
        return !this.isExistSearchValue || this.isAddedCheckAgent ? true : false;
    }
}

export const copy = async textToCopy =>
    await navigator.clipboard.writeText(textToCopy)
                             .catch(err =>
                                console.error(JSON.stringify(err)),
                                err => console.error(JSON.stringify(err)
                                )
                            );