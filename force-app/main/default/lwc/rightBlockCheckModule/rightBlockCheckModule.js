import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class RightBlockCheckModule extends LightningElement {
    @api
    searchApps;
    appName;
    isExistSearchValue =false;
    isBlockButton = true;
    messageBody = 'Hi @CheckAgent, please check ';

    handleSearchChange(event) {
        this.appName = event.target.value;
        let currApp = this.searchApps.find(app => app.Name == this.appName);
        if(currApp) {
            this.searchValue = currApp;
            this.isExistSearchValue = true;
            this.isBlockButton  = false;
            this.messageBody = 'Hi @CheckAgent, please check ' + currApp.Name;
        } else {
            this.searchValue = event.target.value;
            this.isExistSearchValue = false;
            this.isBlockButton  = true;
        }
    }

    handleChange (event) {
        this.messageBody = event.target.value;
    }

    handleCopy() {
        const input = document.createElement("textarea");
        document.body.appendChild(input);
        input.select();
        if(navigator.clipboard){
            copy(this.messageBody);
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
}

export const copy = async textToCopy =>
    await navigator.clipboard.writeText(textToCopy)
                             .catch(err =>
                                console.error(JSON.stringify(err)),
                                err => console.error(JSON.stringify(err)
                                )
                            );