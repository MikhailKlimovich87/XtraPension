import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from "lightning/navigation";
import getContentDocuments from '@salesforce/apex/DocumentsContentController.getContentDocuments';
import changeCustomLetter from '@salesforce/apex/DocumentsContentController.changeCustomLetter';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import pdfAction from '@salesforce/apex/DocumentsContentController.pdfAction';
import sendEmail from '@salesforce/apex/DocumentsContentController.sendHMRCResult';
import sendMissingPaymentsEmail from '@salesforce/apex/DocumentsContentController.sendMissingApplicationPaymentEmail';
export default class DocumentsContent extends NavigationMixin(LightningElement) {
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
    isOpenModal = false;
    requestData;
    isShowSpinner = false;
    isExistReplyDocs = false;
    @track sendDocs = Array();
    isOpenResultModal = false;
    isSendToClientAppStatus = false;
    isPaidApplicationPayment = false;
    replyData;
    templates;
    currentTemplate;
    emailSubject;

    connectedCallback(){
        this.handleDocuments();
    }
    @api async handleDocuments() {
        await getContentDocuments({
            recordId : this.recordId
        })
        .then(result => {
          this.latestDocs              = result?.latestDocs;
          this.allDocs                 = result?.latestDocs;
          this.replyDocs               = result?.replyDocs;
          this.application             = result?.application;
          this.previuosAddresses       = result?.previousAddresses;
          this.lastUKEmployer          = result?.lastUKEmployer;
          this.abroadEmployers         = result?.abroadEmployers;
          this.lastUKAddresses         = result?.latestUKAddress;
          this.isSendToClientAppStatus = result?.isSendToClientAppStatus;
          this.isPaidApplicationPayment= result?.isPaidApplicationPayment;
          this.templates               = result?.templateData;
          this.emailSubject            = result?.templateData?.emailSubject;
          if(result.isSendToClientAppStatus) {
            let successReplyDoc = false;
            let rejectReplyDoc = false;
            this.replyDocs.some( doc => {
              if(doc.title.includes('C2')||doc.title.includes('C3')){
                successReplyDoc = true;
              } else if(doc.title.includes('Reject')) {
                rejectReplyDoc = true;
              }
            })
            if (successReplyDoc) {
              this.replyDocs.map( item =>{
                if (item.title.includes('C2') || item.title.includes('C3') || item.title.includes('Next Step 1') || item.title.includes('Next Step 2') || item.title.includes('Annual Service') || item.title.includes('Bank Transfer') || item.title.includes('Private Pensions')) {
                  item["isCheck"] = true;
                } else item["isCheck"] = false;
              })
            }
            if (rejectReplyDoc) {
              this.replyDocs.map( item =>{
                if (item.title.includes('Reject') || item.title.includes('APPEAL')) {
                  item["isCheck"] = true;
                } else item["isCheck"] = false;
              })
            }
          }
        }).catch(error => {
          this.error = error;
        });
        if (this.replyDocs) this.isExistReplyDocs = true;
    }
    navigateToFiles(event) {
        var documentName = event.currentTarget.getAttribute("value");
        var searchValue = this.allDocs.find(el => el.title == documentName);
        this[NavigationMixin.Navigate]({
          type: "standard__namedPage",
          attributes: {
            pageName: "filePreview",
          },
          state: {
            recordIds: searchValue.documentId
        },
      });
    }

    navigateToReplyFiles(event) {
      var documentName = event.currentTarget.getAttribute("value");
      var searchValue = this.replyDocs.find(el => el.title == documentName);
      this[NavigationMixin.Navigate]({
        type: "standard__namedPage",
        attributes: {
          pageName: "filePreview",
        },
        state: {
          recordIds: searchValue.documentId
      },
    });
  }

    handleDisplayAll() {
      this[ NavigationMixin.Navigate ]( {
        type: 'standard__recordRelationshipPage',
        attributes: {
            recordId: this.recordId,
            objectApiName: 'Application__c',
            relationshipApiName: 'AttachedContentDocuments',
            actionName: 'view'
        }
    } );
    }
    handleOpenModal() {
      this.isOpenModal = !this.isOpenModal;
  }
  closePopup() {
    this.isOpenModal = false;
  }

  closeResultPopup() {
    this.isOpenResultModal = !this.isOpenResultModal;
  }
  @api get isApproved() {
    return true;
  }

  regenerateCustomLetter(event) {
    this.requestData = {
      applicationId    : this.recordId,
      freeformTextLine1: event.detail.freeformTextLine1,
      freeformTextLine2: event.detail.freeformTextLine2,
      freeformTextLine3: event.detail.freeformTextLine3,
      freeformTextLine4: event.detail.freeformTextLine4,
      freeformTextLine5: event.detail.freeformTextLine5,
      newPreviousAddressData: event.detail.newPreviousAddressData,
      newEmployerData: event.detail.newEmployerCheckboxData,
      customLetterDate : event.detail.currentDate
    }
    this.changeApplication();
  }

  changeApplication() {
    this.isShowSpinner = true;
    changeCustomLetter({
      letterData : JSON.parse(JSON.stringify(this.requestData))
    })
    .then(result => {
      if (result == 'true') {
        this.createNewContentDocument();
        const evt = new ShowToastEvent({
          title: 'Success',
          message: 'You have successfully changed the Custom Letter',
          variant: 'success'
        });
        this.dispatchEvent(evt);
        this.isShowSpinner = false;
      }
    }).catch(error => {
        this.dispatchEvent(new ShowToastEvent({
          title: 'Error',
          message: 'You didn\'t changed the Custom Letter. Error is: ' + error,
          variant: 'error',
      }));
      this.isShowSpinner = false;
      this.isOpenModal = false;
    });
  }
  createNewContentDocument() {
    pdfAction({
      applicationId : this.recordId
    }).then(result => {
      window.location.reload();
    }).catch(error => {
      this.isOpenModal = false;
    })
  }

  get colorValue() {
    let replyStatus = this.latestDocs.find( item => item.title == 'HMRC Assessment').hmrcReplyStatus;
    return replyStatus == 'APPROVED' ? 'color:green' :
              replyStatus == 'REJECT' ? 'color:red' :
                  replyStatus == 'UNKNOWN' ? 'color:blue' : null;
  }

  handleCheck(event) {
    let checkboxName = event.target.attributes["data-id"].nodeValue;
    let currentOject = this.replyDocs.find(doc =>
      doc.title == checkboxName
    )
    currentOject.isCheck = !currentOject.isCheck;
  }

  handleSendEmail() {
    this.replyDocs.map( item =>{
      if (item.title.includes('C2') || item.title.includes('C3')) {
        this.currentTemplate = this.templates.successTemplate;
      } else if (item.title.includes('Reject')) {
        this.currentTemplate = this.templates.rejectTempalte;
      }
    })
    this.isOpenResultModal = !this.isOpenResultModal;
    // if (this.isPaidApplicationPayment) {
    //   this.isOpenResultModal = !this.isOpenResultModal;
    // } else {
    //   this.dispatchEvent(new ShowToastEvent({
    //       title: 'Error',
    //       message: 'Application Fee NOT PAID',
    //       variant: 'error',
    //   }));
    //   sendMissingPaymentsEmail({
    //       appId: this.recordId
    //   })
    // }
  }

  handleSendMissingPaymentMessage() {
    this.isOpenResultModal = !this.isOpenResultModal;
    sendMissingPaymentsEmail({
      appId: this.recordId
    })
  }

  handleChangeBody(event) {
    this.currentTemplate = event.bodyHTML;
  }

  @api
  async handleEventSend(event) {
    let docIds = new Array();
    this.replyDocs.map(doc => {
      if (doc.isCheck == true) {
        let docId = doc.documentId;
        docIds.push(docId);
      }
    });
    this.showMessageSpinner = !this.showMessageSpinner;
        let sendData = {
          applicationId: this.recordId,
          htmlBody: event.detail.template,
          subject : event.detail.subject,
          documentsIds: docIds
        };
        console.log(event.detail.template);
        await sendEmail({
          emailData: sendData
        })
        .then(result => {
          if (result.isSuccess) {
            const evt = new ShowToastEvent({
              title: 'Success',
              message: 'You have sent result email to client!',
              variant: 'success'
            });
            this.dispatchEvent(evt);
          } else {
            const evt = new ShowToastEvent({
              title: 'Error',
              message: result.successMessage,
              variant: 'error'
            });
            this.dispatchEvent(evt);
          }
          this.isOpenResultModal = !this.isOpenResultModal;
          window.location.reload();
        }).catch(error => {
          const evt = new ShowToastEvent({
            title: 'Error',
            message:  error.body.message,
            variant: 'error'
          });
          this.dispatchEvent(evt);
          this.isOpenResultModal = !this.isOpenResultModal;
        });
  }
}