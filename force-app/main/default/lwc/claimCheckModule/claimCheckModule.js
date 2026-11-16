import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import insertCheckResult from '@salesforce/apex/ClaimCheckController.createClaimCheckRecords';
import addRequestCheckData from '@salesforce/apex/ClaimCheckController.addRequestCheckData';
import getClaims from '@salesforce/apex/ClaimCheckController.getClaims';

export default class ClaimCheckModule extends LightningElement {
    claims;
    error;
    activeTab = 'queue';
    prefill;

    handleTabActive(event) {
        this.activeTab = event.target.value;
    }

    // "Check" on a queue row: open the record tab with that claim already filled in
    handleCheckFromQueue(event) {
        this.prefill = { name: event.detail, at: Date.now() };
        this.activeTab = 'record';
    }

    connectedCallback() {
        getClaims()
            .then(result => {
                this.claims = result;
                this.error = undefined;
            })
            .catch(error => {
                this.error = error;
                this.claims = undefined;
            });
    }

    async handleInsertReply(event) {
        await insertCheckResult({
            checkData : {
                checkReplies : event.detail.replies,
                checkAgent   : event.detail.agent
            }
        })
            .then(result => {
                if (result) {
                    this.showToastMessage('Success', 'You\'ve created Claim Check record', 'success');
                    setTimeout(() => {
                        window.location.reload();
                    }, 3000);
                }
            })
            .catch(error => {
                this.error = error;
                this.showToastMessage('Error', 'You have error: ' + (error.body ? error.body.message : error), 'error');
            });
    }

    handleRequestCheck(event) {
        addRequestCheckData({
            claimId : event.detail
        }).then(() => {
            this.showToastMessage('Success', 'Claim check request saved', 'success');
        }).catch(error => {
            this.showToastMessage('Error update record', error.body ? error.body.message : error, 'error');
        });
    }

    showToastMessage(titleData, messageInfo, toastVariant) {
        this.dispatchEvent(new ShowToastEvent({
            title: titleData,
            message: messageInfo,
            variant: toastVariant,
        }));
    }
}