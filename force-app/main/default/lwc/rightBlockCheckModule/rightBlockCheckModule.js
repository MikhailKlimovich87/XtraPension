import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class RightBlockCheckModule extends LightningElement {
    @api
    searchApps;
    appName;
    isExistSearchValue =false;
    isBlockButton = true;
    messageBody;
    searchValue;

    handleSearchChange(event) {
        this.appName = event.target.value;
        let currApp = this.searchApps.find(app => {
            let searchValue = app.Name.includes("A0") ?
                app.Name.replace("A0", "") :
                app.Name.includes("A") ?
                    app.Name.replace("A", ""):
                    null;
                return searchValue == this.appName;
        } );
        if(currApp && currApp.HMRC_Check_Requests__r) {
            this.searchValue = currApp;
            this.isExistSearchValue = true;
            this.isBlockButton  = false;
        } else if(currApp) {
            this.searchValue = currApp;
            this.isExistSearchValue = true;
            this.isBlockButton  = true;
        } else {
            this.isExistSearchValue = false;
            this.isBlockButton  = true;
        }
    }

    handleChange (event) {
        this.messageBody = event.target.value;
    }

    handleRquestCheck() {
        if (!this.isBlockButton) {
            this.dispatchEvent(
                new CustomEvent('handlerequestcheck', {
                    "detail" :  this.searchValue.Id
                }
            )
        );
        }
        this.messageBody = 'Hi @check-team, please check ' + this.searchValue.Name;
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

    get isEmptyAppList() {
        return this.searchApps == null ? true : false;
    }
    get isEmptySearchApp() {
        return this.searchValue == null ? true : false;
    }
}

export const copy = async textToCopy =>
    await navigator.clipboard.writeText(textToCopy)
                             .catch(err =>
                                console.error(JSON.stringify(err)),
                                err => console.error(JSON.stringify(err)
                                )
                            );