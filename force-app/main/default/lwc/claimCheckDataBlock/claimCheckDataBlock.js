import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// The representative on the client's Letter of Authority to the DWP (page BP_DWP), as the DWP has it (Fernando, 05/11/2026)
const AGENT_DETAILS =
    'XtraPension Ltd, Gray Office Park, Headford Rd, Galway H91 WC1P, Ireland - Tel +353 91 335 583 - claims@xtrapension.com - Irish Co Number 749802';

// C00123, 00123 and 123 all point to the same claim
export const numberKey = value => (value || '').trim().replace(/^[A-Za-z]+/, '').replace(/^0+/, '');

const FIELD_BY_ID = {
    not_received: 'notReceived',
    received: 'received',
    processing: 'processing',
    more_info: 'moreInfo',
    approved: 'approved',
    rejected: 'rejected',
    lump_sum: 'lumpSum',
    payment_started: 'paymentStarted',
    called_dwp: 'calledDwp'
};

export default class ClaimCheckDataBlock extends LightningElement {
    @api checkRequest;
    @api searchApps;
    @api isAddedCheckAgent;
    @api agent;
    currCheckReply;
    searchValue;
    appName = '';
    isExistSearchValue = false;

    connectedCallback() {
        this.currCheckReply = JSON.parse(JSON.stringify(this.checkRequest));
        // opened from the queue with the claim already chosen
        if (this.currCheckReply.appName) this.findApp(this.currCheckReply.appName);
    }

    handleSearchChange(event) {
        this.findApp(event.target.value);
    }

    findApp(value) {
        this.appName = value;
        this.currCheckReply.appName = this.appName;
        const key = numberKey(this.appName);
        const currApp = key && this.searchApps ? this.searchApps.find(app => numberKey(app.Name) === key) : null;

        if (currApp) {
            this.searchValue = currApp;
            this.isExistSearchValue = true;
        } else {
            this.searchValue = null;
            this.isExistSearchValue = false;
        }
        this.notifyParent();
    }

    handleCopy(event) {
        const dataSetId = event.target.dataset.id;
        let copyMessageData = '';
        switch (dataSetId) {
            case 'initial_button':
                copyMessageData = 'Hi, this is ' + this.agent + ', an agent. Just wanted to check on our client\'s UK State Pension claim.';
                break;
            case 'client_button': {
                const claim = this.searchValue;
                const address = [claim.Claimant_address1__c, claim.Claimant_address2__c, claim.Current_Address_Abroad_Country_Name__c]
                    .filter(Boolean).join(', ');
                copyMessageData += claim.Claimant_nino__c ? ('NINO = ' + claim.Claimant_nino__c + '………') : '';
                copyMessageData +=
                    'DOB = ' + (claim.Claimant_dob__c || '') + '………' +
                    'Name = ' + claim.First_Name__c + ' ' + claim.Last_Name__c + '………' +
                    'Addr = ' + address +
                    (claim.Phone__c ? '………Phone = ' + claim.Phone__c : '');
                copyMessageData += claim.Claimant_maiden_Name__c ? ('………Former Name: ' + claim.Claimant_maiden_Name__c) : '';
                break;
            }
            case 'agent_button':
                copyMessageData = AGENT_DETAILS;
                break;
            default:
                return;
        }
        this.copyInfo(copyMessageData);
    }

    copyInfo(dataOfCopy) {
        if (navigator.clipboard) {
            navigator.clipboard.writeText(dataOfCopy)
                .then(() => this.showToastMessage('Success', 'You copied the data', 'success'))
                .catch(() => this.showToastMessage('Error', 'You didn\'t copy the data', 'error'));
        } else {
            this.showToastMessage('Error', 'You didn\'t copy the data', 'error');
        }
    }

    showToastMessage(titleData, messageInfo, toastVariant) {
        this.dispatchEvent(new ShowToastEvent({
            title: titleData,
            message: messageInfo,
            variant: toastVariant,
        }));
    }

    get isEmptyAppList() {
        return this.searchApps == null;
    }

    handleRemoveRequest() {
        this.dispatchEvent(
            new CustomEvent('removerequest', {
                detail : this.checkRequest.id
            })
        );
    }

    handleChange(event) {
        const dataSetId = event.target.dataset.id;
        if (FIELD_BY_ID[dataSetId]) {
            this.currCheckReply[FIELD_BY_ID[dataSetId]] = event.target.checked;
        } else if (dataSetId === 'notes') {
            this.currCheckReply.notes = event.target.value;
        } else if (dataSetId === 'pdf_link') {
            this.currCheckReply.pdfLink = event.target.value;
        }
        this.notifyParent();
    }

    notifyParent() {
        this.dispatchEvent(
            new CustomEvent('updatecheckreply', {
                detail : this.currCheckReply
            })
        );
    }

    get isDisabledClientButton() {
        return !this.isExistSearchValue;
    }

    get isDisabledInitialButton() {
        return !this.isExistSearchValue || this.isAddedCheckAgent;
    }
}