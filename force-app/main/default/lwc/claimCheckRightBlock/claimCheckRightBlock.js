import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// C00123, 00123 and 123 all point to the same claim
const numberKey = value => (value || '').trim().replace(/^[A-Za-z]+/, '').replace(/^0+/, '');

export default class ClaimCheckRightBlock extends LightningElement {
    @api searchApps;
    appName;
    isExistSearchValue = false;
    searchValue;

    handleSearchChange(event) {
        this.appName = event.target.value;
        const key = numberKey(this.appName);
        const currApp = key ? this.searchApps.find(app => numberKey(app.Name) === key) : null;
        this.searchValue = currApp || null;
        this.isExistSearchValue = !!currApp;
    }

    handleRequestCheck() {
        if (!this.searchValue) return;
        this.dispatchEvent(
            new CustomEvent('handlerequestcheck', {
                detail : this.searchValue.Id
            })
        );
        const messageBody = 'Hi @check-team, please check Claim ' + this.searchValue.Name + ' with the DWP';
        if (navigator.clipboard) {
            navigator.clipboard.writeText(messageBody)
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

    get isEmptySearchApp() {
        return this.searchValue == null;
    }
}