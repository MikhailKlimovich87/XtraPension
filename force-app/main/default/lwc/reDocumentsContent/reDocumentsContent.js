import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getContentDocuments from '@salesforce/apex/RE_DocumentsContentController.getContentDocuments';

export default class ReDocumentsContent extends NavigationMixin(LightningElement) {
    @api recordId;
    @track latestDocs;
    @track replyDocs;
    @track allDocs;
    @track error;
    application;
    lastUKAddresses;
    previuosAddresses;
    lastUKEmployer;
    abroadEmployers;
    showLatest = true;
    //isOpenModal = false;
    requestData;
    isShowSpinner = false;
    //isExistReplyDocs = false;
    @track sendDocs = Array();
    isOpenResultModal = false;
    isSendToClientAppStatus = false;
    isPaidApplicationPayment = false;
    replyData;
    templates;
    currentTemplate;
    emailSubject;

    tabs = [{ label: 'Reapply', value: 'Reapply' }, { label: 'Completed', value: 'Completed' }];

    activeTab = 'Reapply';

    connectedCallback() {
        this.handleDocuments();
    }

    handleTabActive(event) {
        this.activeTab = event.target.value;
    }

    get filteredDocs() {
        if (this.latestDocs) {
            return this.latestDocs.filter((doc) => doc.typeGroup === this.activeTab);
        }
    }

    @api async handleDocuments() {
        await getContentDocuments({
            recordId: this.recordId
        })
            .then((result) => {
                this.latestDocs = result?.latestDocs;
                console.log('latestDocs ====', structuredClone(this.latestDocs));
                console.log('activeTab =====', structuredClone(this.activeTab));
            })
            .catch((error) => {
                this.error = error;
            });
    }
    navigateToFiles(event) {
        const documentName = event.currentTarget.getAttribute('value');
        const searchValue = this.latestDocs.find((el) => el.documentId == documentName);
        console.log(structuredClone(this.latestDocs));
        console.log(structuredClone(documentName));
        console.log(structuredClone(searchValue));
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'filePreview'
            },
            state: {
                recordIds: searchValue.documentId
            }
        });
    }

    handleDisplayAll() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordRelationshipPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: 'Reapply__c',
                relationshipApiName: 'AttachedContentDocuments',
                actionName: 'view'
            }
        });
    }

    @api get isApproved() {
        return true;
    }
}