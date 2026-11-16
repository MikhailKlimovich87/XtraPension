import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import insertCheckResult from '@salesforce/apex/ReapplyCheckController.createReapplyCheckRecords';
import addRequestCheckData from '@salesforce/apex/ReapplyCheckController.addRequestCheckData';
import getReapplies from '@salesforce/apex/ReapplyCheckController.getReapplyNames';

export default class ReapplyCheckModule extends LightningElement {
    reapplies;
    error;
    activeTab = 'queue';
    prefill;

    handleTabActive(event) {
        this.activeTab = event.target.value;
    }

    // "Check" on a queue row: open the record tab with that reapply already filled in
    handleCheckFromQueue(event) {
        this.prefill = { name: event.detail, at: Date.now() };
        this.activeTab = 'record';
    }

    connectedCallback() {
        getReapplies()
            .then(result => {
                this.reapplies = result;
                this.error = undefined;
            })
            .catch(error => {
                this.error = error;
                this.reapplies = undefined;
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
                    this.showToastMessage(
                        'Success',
                        'You\'ve created Reapply Check Request record',
                        'success'
                    );
                    setTimeout(() => {
                        window.location.reload();
                    }, 3000);
                }
            })
            .catch(error => {
                this.error = error;
                this.showToastMessage(
                    'Error',
                    'You have error: ' + (error.body ? error.body.message : error),
                    'error'
                );
            });
    }

    handleRequestCheck(event) {
        addRequestCheckData({
            reapplyId : event.detail
        }).then(() => {
            this.showToastMessage(
                'Success',
                'Reapply check request saved',
                'success'
            );
        }).catch(error => {
            this.showToastMessage(
                'Error update record',
                error.body ? error.body.message : error,
                'error'
            );
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