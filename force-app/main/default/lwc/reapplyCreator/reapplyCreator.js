import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import createRelatedReapply from '@salesforce/apex/RE_ApplicationDataAction.createRelatedReapply';
import hasExistingReapply from '@salesforce/apex/RE_ApplicationDataAction.hasExistingReapply';
import getReapplyRecordId from '@salesforce/apex/RE_ApplicationDataAction.getReapplyRecordId';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ReapplyCreator extends NavigationMixin(LightningElement) {
    @api recordId;
    @track isLoading = false;
    @track errorMessage = '';
    @track successMessage = '';
    @track hasReapply = false;
    @track showDebug = false;
    @track errorDetails = '';
    @track existingReapplyId = null;

    // Getter for debug button label - FIXES THE ERROR
    get debugButtonLabel() {
        return this.showDebug ? 'Hide Details' : 'Show Details';
    }

    connectedCallback() {
        this.checkExistingReapply();
    }

    async handleCreateReapply() {
        if (!this.recordId) {
            this.showToast('Error', 'No Application ID found', 'error');
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';
        this.successMessage = '';
        this.errorDetails = '';

        try {
            const result = await createRelatedReapply({ appId: this.recordId, isCreateFromBatch: false });
            
            let newReapplyId = result;
            if (typeof result === 'string' && result.startsWith('a')) {
                newReapplyId = result;
            }
            
            this.successMessage = 'Reapply record created successfully!';
            this.hasReapply = true;
            
            this.showToast('Success', 'Reapply record created successfully', 'success');
            
            if (newReapplyId) {
                setTimeout(() => {
                    this.navigateToRecord(newReapplyId);
                }, 1500);
            } else {
                setTimeout(() => location.reload(), 2000);
            }
            
        } catch (error) {
            console.error('Error creating reapply:', error);
            console.error('Full error object:', JSON.stringify(error));
            
            let errorMsg = 'Failed to create Reapply record.';
            let detailedError = '';
            
            if (error.body) {
                if (error.body.message) {
                    errorMsg = error.body.message;
                    detailedError = error.body.message;
                }
                
                if (error.body.exceptionType === 'AuraHandledException' && error.body.message) {
                    errorMsg = error.body.message;
                }
                
                if (error.body.pageErrors && error.body.pageErrors.length > 0) {
                    errorMsg = error.body.pageErrors[0].message;
                    detailedError = error.body.pageErrors[0].message;
                }
                
                if (error.body.fieldErrors) {
                    const fieldErrors = error.body.fieldErrors;
                    const errorMessages = [];
                    for (let field in fieldErrors) {
                        fieldErrors[field].forEach(err => {
                            errorMessages.push(`${field}: ${err.message}`);
                        });
                    }
                    detailedError = errorMessages.join('; ');
                    errorMsg = detailedError;
                }
            }
            
            if (!errorMsg || errorMsg === 'Failed to create Reapply record.') {
                if (error.message) {
                    errorMsg = error.message;
                } else {
                    errorMsg = 'An unexpected error occurred. Please check logs for details.';
                }
            }
            
            this.errorMessage = errorMsg;
            this.errorDetails = detailedError;
            
            this.showToast('Error', errorMsg, 'error');
            
        } finally {
            this.isLoading = false;
        }
    }

    async checkExistingReapply() {
        if (!this.recordId) return;
    
        try {
            const result = await getReapplyRecordId({ appId: this.recordId });
            
            if (result) {
                this.hasReapply = true;
                this.existingReapplyId = result;
                
                this.showToast(
                    'Information', 
                    'A Reapply record already exists for this Application. You will be redirected to it.',
                    'info'
                );
                
                setTimeout(() => {
                    this.navigateToRecord(result);
                }, 2000);
            } else {
                this.hasReapply = false;
                this.existingReapplyId = null;
            }
        } catch (error) {
            console.error('Error checking existing reapply:', error);
        }
    }

    handleNavigateToExisting() {
        if (this.existingReapplyId) {
            this.navigateToRecord(this.existingReapplyId);
        } else {
            this.showToast('Error', 'No existing Reapply record found', 'error');
        }
    }

    navigateToRecord(recordId) {
        if (!recordId) return;
        
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                objectApiName: 'Reapply__c',
                actionName: 'view'
            }
        });
    }

    toggleDebugInfo() {
        this.showDebug = !this.showDebug;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant,
                mode: 'sticky'
            })
        );
    }
}