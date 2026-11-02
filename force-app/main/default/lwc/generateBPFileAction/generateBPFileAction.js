import { LightningElement, api, track } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getApplicationSignature from '@salesforce/apex/BP_GeneratePdfFileController.generateSignature';
import getApplication from '@salesforce/apex/BP_GeneratePdfFileController.getApplication';
import generatePdf from '@salesforce/apex/BP_ClientSummaryPdfService.generatePdf';
import generatePinkAndYellow from '@salesforce/apex/BP_ClientSummaryPdfService.generatePinkAndYellow';
import generateDWP from '@salesforce/apex/BP_ClientSummaryPdfService.generateDWP';
import getContentDocuments from '@salesforce/apex/BP_DocumentsContentController.getContentDocuments';
import generateZipArchiveAfterCreatedClaim from '@salesforce/apex/BP_PortalUtils.generateZipArchiveAfterCreatedClaim';
import generateZipArchiveFullFormClaim from '@salesforce/apex/BP_PortalUtils.generateZipArchiveFullFormClaim';
import { NavigationMixin } from "lightning/navigation";

export default class GenerateBPFileAction  extends NavigationMixin(LightningElement) {
    _recordId;

    @api
    set recordId(value) {
        this._recordId = value;

        if (value) {
            this.isLoading = true;
            this.handleDocuments();
        }
    }

    get recordId() {
        return this._recordId;
    }

    @track latestDocs;
    isLoading = false;
    showLatest = true;

    tabs = [
        { label: 'Full Forms', value: 'FullForm' },
        { label: 'WET Signature', value: 'WET' },
        { label: 'Client Summary', value: 'Summary' },
        { label: 'DWP', value: 'DWP' },
        { label: 'Pink, Yellow, Notes', value: 'Color' },
        { label:  'Collect Stage 1 (wet-signature pack) to SFTP', value: 'ColectBig' },
        { label:  'Collect Stage 2 (Big Envelope) to SFTP', value: 'ColectFullForm' }

    ];

    activeTab = 'FullForm';

    get filteredDocs() {
          if(this.latestDocs) {
            console.log(this.latestDocs.filter(doc => doc.redoGroup === this.activeTab));
            return this.latestDocs.filter(doc => doc.redoGroup === this.activeTab);
          }
            
        }
    
    handleDocuments() {
            getContentDocuments({
                recordId : this.recordId
            })
            .then(result => {
              
              this.latestDocs = result?.latestDocs;
              console.log(structuredClone(this.latestDocs));
              console.log(structuredClone(this.activeTab));
              this.isLoading = false;
            }).catch(error => {
              this.error = error;
              this.isLoading = false;
            });
        }

    handleRegenerate() {
        this.isLoading = true;
        console.log(structuredClone(this.activeValueMessage));
        if(this.activeTab === 'FullForm') {
            this.generateApplication();
        } else if(this.activeTab === 'Summary') {
            this.generateClientSummary();
        } else if(this.activeTab === 'WET') {
            this.generateApplicationSignature();
        } else if(this.activeTab === 'DWP') {
            this.generateDWP();
        } else if(this.activeTab === 'Color') {
            this.generatePinkAndYellow();
        } else if(this.activeTab === 'ColectBig') {
           this.generateZipArchiveAfterCreatedClaimLWC();
        } else if(this.activeTab === 'ColectFullForm') {
           this.generateZipArchiveFullFormClaimLWC();
        }
    }

    generateApplicationSignature() {
            getApplicationSignature({ recordId: this.recordId })
            .then(result => {
                this.handleDocuments();
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Signature generated successfully',
                        variant: 'success'
                    })
                );
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body?.message || error.message,
                        variant: 'error'
                    })
                );
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
    generateApplication() {
            getApplication({ recordId: this.recordId })
            .then(result => {
                this.handleDocuments();
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Full forms generated successfully',
                        variant: 'success'
                    })
                );
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body?.message || error.message,
                        variant: 'error'
                    })
                );
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
    generateClientSummary() {
            generatePdf({ basicId: this.recordId })
            .then(result => {
                this.handleDocuments();
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Client Summary generated successfully',
                        variant: 'success'
                    })
                );
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body?.message || error.message,
                        variant: 'error'
                    })
                );
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
    generatePinkAndYellow() {
            generatePinkAndYellow({ basicId: this.recordId })
            .then(result => {
                this.handleDocuments();
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Pink And Yellow generated successfully',
                        variant: 'success'
                    })
                );
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body?.message || error.message,
                        variant: 'error'
                    })
                );
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
    generateDWP() {
            generateDWP({ basicId: this.recordId })
            .then(result => {
                this.handleDocuments();
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Signature generated successfully',
                        variant: 'success'
                    })
                );
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body?.message || error.message,
                        variant: 'error'
                    })
                );
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
    generateZipArchiveAfterCreatedClaimLWC() {
            generateZipArchiveAfterCreatedClaim({ applicationId: this.recordId })
            .then(result => {
                this.handleDocuments();
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Stage 1 (wet-signature pack) ZIP generated successfully',
                        variant: 'success'
                    })
                );
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body?.message || error.message,
                        variant: 'error'
                    })
                );
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
    generateZipArchiveFullFormClaimLWC() {
            generateZipArchiveFullFormClaim({ applicationId: this.recordId })
            .then(result => {
                this.handleDocuments();
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Stage 2 (Big Envelope) ZIP generated successfully',
                        variant: 'success'
                    })
                );
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body?.message || error.message,
                        variant: 'error'
                    })
                );
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    
    handleTabActive(event) {
         console.log(structuredClone(this.recordId));
        this.activeTab = event.target.value;
        console.log(structuredClone( this.activeTab));
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

   navigateToFiles(event) {
    try {
        const documentId = event.currentTarget.dataset.documentId;
        console.log(structuredClone( documentId))

        if (!documentId) {
            console.error('Document not found');
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'filePreview'
            },
            state: {
                recordIds: documentId
            }
        });
        // this[NavigationMixin.Navigate]({
        //     type: 'standard__recordPage',
        //     attributes: {
        //         recordId: this.recordId,
        //         actionName: 'view'
        //     }
        // });
    } catch (e) {
        console.log(structuredClone(e));
    }
}

}