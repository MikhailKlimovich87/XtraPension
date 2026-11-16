import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// Reapply stages where a C2/C3 answer means HMRC moved before we did (same rule as the normal checks)
const OPEN_STAGES = ['Posted', 'HMRC Reply 1', 'Pending Info', 'HMRC Appeal', 'HMRC Reply 2'];

const AGENT_DETAILS =
    'JGBA Ltd, Suite 2/11 Pure Offices, 1 Ainslie Road, Hillington, Glasgow G52 4RU - Tel 0141 301 1480 (Previous address Suite 1/31 Pure Offices)';

// R08694, A08694, 08694 and 8694 all point to the same reapply
export const numberKey = value => (value || '').trim().replace(/^[A-Za-z]+/, '').replace(/^0+/, '');

export default class ReapplyCheckDataBlock extends LightningElement {
    @api sentToData = [];
    @api checkRequest;
    @api searchApps;
    @api isAddedCheckAgent;
    @api agent;
    currCheckReply;
    searchValue;
    appName = '';
    isOpenConfirmModal = false;
    isExistSearchValue = false;
    isNotReceivedRequest = false;

    connectedCallback() {
        this.currCheckReply = JSON.parse(JSON.stringify(this.checkRequest));
        // opened from the queue with the reapply already chosen
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
                copyMessageData = 'Hi, this is ' + this.agent + ', an agent. Just wanted to check if our client\'s CF83 form has come through.';
                break;
            case 'client_button': {
                const app = this.searchValue;
                const phone = app.Phone__c || app.Daytime_phone_number__c;
                copyMessageData += app.NINO__c ? ('NINO = ' + app.NINO__c + '………') : '';
                copyMessageData +=
                    'DOB = ' + app.Date_of_birth__c + '………' +
                    'Name = ' + app.First_Name__c + ' ' + app.Second_Name__c + '………' +
                    'Addr = ' + (app.Full_Address_abroad__c || '') +
                    (phone ? '………Phone = ' + phone : '');
                copyMessageData += app.Former_Name__c ? ('………Former Name: ' + app.Former_Name__c) : '';
                copyMessageData = copyMessageData.replaceAll('<br>', ', ');
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

    openC2Modal() {
        if (this.searchValue &&
            (this.currCheckReply.c2 || this.currCheckReply.c3) &&
            OPEN_STAGES.includes(this.searchValue.Status__c)) {
            this.isOpenConfirmModal = true;
        }
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
        const checked = event.target.checked;
        const value = event.target.value;
        switch (dataSetId) {
            case 'not_received':
                this.currCheckReply.notReceived = checked;
                this.isNotReceivedRequest = checked;
                break;
            case 'c2':
                this.currCheckReply.c2 = checked;
                this.openC2Modal();
                break;
            case 'c3':
                this.currCheckReply.c3 = checked;
                this.openC2Modal();
                break;
            case 'work_item':
                this.currCheckReply.workItem = checked;
                break;
            case 'bad_nino':
                this.currCheckReply.badNINO = checked;
                break;
            case 'bad_info':
                this.currCheckReply.badInfo = checked;
                break;
            case 'processing':
                this.currCheckReply.processing = checked;
                break;
            case 'dwp':
                this.currCheckReply.dwp = checked;
                break;
            case 'dwp_call':
                this.currCheckReply.dwpCall = checked;
                break;
            case 'X64_8':
                this.currCheckReply.X64_8 = checked;
                break;
            case 'reject':
                this.currCheckReply.reject = checked;
                break;
            case 'sent_to':
                this.currCheckReply.sentTo = value;
                break;
            case 'sent_date':
                this.currCheckReply.sentDate = value;
                break;
            case 'notes':
                this.currCheckReply.notes = value;
                break;
            case 'pdf_link':
                this.currCheckReply.pdfLink = value;
                break;
            default:
                break;
        }
        this.notifyParent();
    }

    // c2CheckConfirmModal sends 'Yes' or 'No'
    handleRequestedCopy(event) {
        this.currCheckReply.requestedCopy = event.detail;
        this.isOpenConfirmModal = false;
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