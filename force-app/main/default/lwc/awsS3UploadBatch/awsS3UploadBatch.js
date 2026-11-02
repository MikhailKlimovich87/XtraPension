// awsS3UploadBatch.js
import { LightningElement, track, api, wire } from 'lwc';
import executeBatch from '@salesforce/apex/AwsS3UploadBatchController.executeBatch';
import getBatchStatus from '@salesforce/apex/AwsS3UploadBatchController.getBatchStatus';
import getApplicationInfo from '@salesforce/apex/AwsS3UploadBatchController.getApplicationInfo';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CurrentPageReference } from 'lightning/navigation';
import { NavigationMixin } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class AwsS3UploadBatch extends NavigationMixin(LightningElement) {
    _recordId;
    @track applicationId = '';
    @track applicationName = '';
    @track isLoading = false;
    @track isLoadingAppInfo = false;
    @track batchJobId = null;
    @track statusCheckInterval = null;
    @track batchStatus = {
        status: '',
        jobItemsProcessed: 0,
        totalJobItems: 0,
        extendedStatus: '',
        completedDate: null,
        createdDate: null
    };
    @track showStatus = false;
    @track showConfirmDialog = false;

    connectedCallback() {
        if (this._recordId) {
            this.applicationId = this._recordId;
            this.loadApplicationInfo();
        }
    }

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            this._recordId = currentPageReference.state.recordId;
            if (this._recordId) {
                this.applicationId = this._recordId;
                this.loadApplicationInfo();
            }
        }
    }

    async loadApplicationInfo() {
        if (!this.applicationId) return;

        this.isLoadingAppInfo = true;
        try {
            const result = await getApplicationInfo({ applicationId: this.applicationId });
            if (result && result.id) {
                this.applicationName = result.name;
            } else {
                this.applicationName = 'Unknown Application';
            }
        } catch (error) {
            console.error('Error loading application info:', error);
            this.applicationName = 'Error loading application';
        } finally {
            this.isLoadingAppInfo = false;
        }
    }

    get buttonLabel() {
        return this.isLoading ? 'Executing...' : 'Execute Batch';
    }

    get isButtonDisabled() {
        return this.isLoading || !this.applicationId || this.isLoadingAppInfo;
    }

    get progressStyle() {
        return `width: ${this.progressPercentage}%;`;
    }

    get formattedCreatedDate() {
        if (!this.batchStatus.createdDate) return '-';
        return this.formatDate(this.batchStatus.createdDate);
    }

    get formattedCompletedDate() {
        if (!this.batchStatus.completedDate) return '-';
        return this.formatDate(this.batchStatus.completedDate);
    }

    get isBatchRunning() {
        return (
            this.batchStatus.status === 'Processing' ||
            this.batchStatus.status === 'Queued' ||
            this.batchStatus.status === 'Holding'
        );
    }

    get isBatchCompleted() {
        return this.batchStatus.status === 'Completed' || this.batchStatus.status === 'Completed with Errors';
    }

    get isBatchFailed() {
        return (
            this.batchStatus.status === 'Failed' ||
            this.batchStatus.status === 'Aborted' ||
            this.batchStatus.status === 'ERROR'
        );
    }

    get progressPercentage() {
        if (this.batchStatus.totalJobItems === 0) return 0;
        return Math.round((this.batchStatus.jobItemsProcessed / this.batchStatus.totalJobItems) * 100);
    }

    get statusIcon() {
        if (this.isBatchCompleted && this.batchStatus.status !== 'Completed with Errors') {
            return 'utility:success';
        } else if (this.isBatchCompleted && this.batchStatus.status === 'Completed with Errors') {
            return 'utility:warning';
        } else if (this.isBatchFailed) {
            return 'utility:error';
        } else if (this.isBatchRunning) {
            return 'utility:spinner';
        }
        return 'utility:info';
    }

    get statusVariant() {
        if (this.isBatchCompleted && this.batchStatus.status !== 'Completed with Errors') {
            return 'success';
        } else if (this.isBatchCompleted && this.batchStatus.status === 'Completed with Errors') {
            return 'warning';
        } else if (this.isBatchFailed) {
            return 'destructive';
        }
        return 'base';
    }

    handleExecuteBatch() {
        if (!this.applicationId) {
            this.showToast('Error', 'Application ID is required.', 'error');
            return;
        }
        this.showConfirmDialog = true;
    }

    handleConfirm() {
        this.showConfirmDialog = false;
        this.executeBatch();
    }

    handleCancel() {
        this.showConfirmDialog = false;
    }

    async executeBatch() {
        try {
            this.isLoading = true;
            this.resetState();

            const result = await executeBatch({ applicationId: this.applicationId });

            if (result.success) {
                this.batchJobId = result.batchJobId;
                this.showToast('Success', result.message, 'success');
                this.showStatus = true;

                this.startStatusPolling();
            } else {
                this.showToast('Error', result.message, 'error');
                this.isLoading = false;
            }
        } catch (error) {
            console.error('Error executing batch:', error);
            this.showToast('Error', 'Failed to execute batch: ' + (error.body?.message || error.message), 'error');
            this.isLoading = false;
        }
    }

    handleReset() {
        this.resetState();
        this.showStatus = false;
        this.isLoading = false;
        if (this._recordId) {
            this.applicationId = this._recordId;
            this.loadApplicationInfo();
        }
        this.stopStatusPolling();
        this.showToast('Info', 'Component has been reset.', 'info');
    }

    startStatusPolling() {
        if (this.statusCheckInterval) {
            clearInterval(this.statusCheckInterval);
        }

        this.checkBatchStatus();

        this.statusCheckInterval = setInterval(() => {
            this.checkBatchStatus();
        }, 3000);
    }

    async checkBatchStatus() {
        if (!this.batchJobId) return;

        try {
            const status = await getBatchStatus({ batchJobId: this.batchJobId });
            this.batchStatus = status;

            if (this.isBatchCompleted || this.isBatchFailed) {
                this.stopStatusPolling();
                this.showFinalStatusToast();
                this.isLoading = false;

                if (this.isBatchCompleted && this.batchStatus.status !== 'Completed with Errors') {
                    setTimeout(() => {
                        //this.reloadPage();
                        //this.handleClose();
                    }, 2000);
                }
            }
        } catch (error) {
            console.error('Error checking batch status:', error);
            this.stopStatusPolling();
            this.showToast('Error', 'Failed to check batch status: ' + (error.body?.message || error.message), 'error');
            this.isLoading = false;
        }
    }

    showFinalStatusToast() {
        if (this.isBatchCompleted && this.batchStatus.status !== 'Completed with Errors') {
            this.showToast(
                '✅ Batch Completed Successfully',
                `Successfully processed ${this.batchStatus.jobItemsProcessed} out of ${this.batchStatus.totalJobItems} records.`,
                'success'
            );
        } else if (this.isBatchCompleted && this.batchStatus.status === 'Completed with Errors') {
            this.showToast(
                '⚠️ Batch Completed with Errors',
                `Processed ${this.batchStatus.jobItemsProcessed} out of ${this.batchStatus.totalJobItems} records. Some records may have failed. Check logs for details.`,
                'warning'
            );
            setTimeout(() => {
                //this.reloadPage();
                //this.handleClose();
            }, 3000);
        } else if (this.isBatchFailed) {
            this.showToast(
                '❌ Batch Failed',
                `Batch failed with status: ${this.batchStatus.status}. ${this.batchStatus.extendedStatus || 'Check logs for more details.'}`,
                'error'
            );
        }
    }

    stopStatusPolling() {
        if (this.statusCheckInterval) {
            clearInterval(this.statusCheckInterval);
            this.statusCheckInterval = null;
        }
    }

    resetState() {
        this.batchJobId = null;
        this.showStatus = false;
        this.batchStatus = {
            status: '',
            jobItemsProcessed: 0,
            totalJobItems: 0,
            extendedStatus: '',
            completedDate: null,
            createdDate: null
        };
        this.stopStatusPolling();
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: 'dismissable'
        });
        this.dispatchEvent(event);
    }

    handleViewJobDetails() {
        if (this.batchJobId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.batchJobId,
                    objectApiName: 'AsyncApexJob',
                    actionName: 'view'
                }
            });
        }
    }

    formatDate(dateString) {
        if (!dateString) return '-';
        try {
            const date = new Date(dateString);
            return date.toLocaleString();
        } catch (error) {
            return '-';
        }
    }

    reloadPage() {
        window.location.reload();
    }

    disconnectedCallback() {
        this.stopStatusPolling();
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}