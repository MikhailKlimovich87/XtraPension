import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from "lightning/navigation";
import { getRecord } from 'lightning/uiRecordApi';
import STATUS from '@salesforce/schema/Basic__c.Status__c';
import getContentDocuments from '@salesforce/apex/BP_DocumentsContentController.getContentDocuments';
// import changeCustomLetter from '@salesforce/apex/DocumentsContentController.changeCustomLetter';
// import { ShowToastEvent } from 'lightning/platformShowToastEvent';
// import pdfAction from '@salesforce/apex/DocumentsContentController.pdfAction';
// import sendEmail from '@salesforce/apex/DocumentsContentController.sendHMRCResult';
// import sendMissingPaymentsEmail from '@salesforce/apex/DocumentsContentController.sendMissingApplicationPaymentEmail';

// abas:inicio
// As 3 abas dos devs (Stage 1, DocuSign, Stage 2) com as linhas no desenho do Docs do Sales (04/11/2026, o Fernando
// preferiu as abas à lista só). A aba vem do typeGroup do Apex (BP_DocumentsContentController, sem mudança); arquivo que o
// Apex não reconhece (typeGroup vazio) continua fora. A aba que abre segue o estágio; se ela estiver vazia, abre a
// primeira que tem arquivo. Clicar numa aba vale até recarregar a página.
const TABS = [
    { value: 'BigEnvelope', label: 'Stage 1', hint: 'Big Envelope: the wet-signature pack the printer posts to the client.', titles: ['Pink Page', 'Yellow Page', 'DWP Authority', 'IPCBR1 Wet', 'IPC1394 Wet', 'Payment Notes', 'Stage 1 ZIP (wet-signature pack)'] },
    { value: 'DocuSign', label: 'DocuSign', hint: 'What the client signs in DocuSign.', titles: ['Client Summary', 'DD Mandate'] },
    { value: 'FullForms', label: 'Stage 2', hint: 'Full forms: what the printer posts to the DWP.', titles: ['IPCBR1 Full Form', 'IPC1394 Full Form', 'Stage 2 ZIP (Big Envelope)'] }
];
// Nome curto na tela: a aba já diz o estágio.
const SHORT = { 'Stage 1 ZIP (wet-signature pack)': 'Stage 1 ZIP', 'Stage 2 ZIP (Big Envelope)': 'Stage 2 ZIP' };
// Estágio -> aba que abre: o Big Envelope sai até o Form completed; da revisão à assinatura o que importa é o pacote do
// DocuSign; depois de assinado, os formulários completos (Stage 2) que vão para o DWP.
const STAGE_TAB = {
    'Form In Progress': 'BigEnvelope', 'Validation Call': 'BigEnvelope', 'Form completed': 'BigEnvelope',
    'Pending Client': 'DocuSign', 'Agent Check': 'DocuSign', 'QC Approved': 'DocuSign', 'Sent for eSignature': 'DocuSign'
};

function docsOf(docs, tab) {
    const list = Array.isArray(docs) ? docs : [];
    const rank = t => { const i = tab.titles.indexOf(t); return i < 0 ? tab.titles.length : i; };
    return list
        .filter(d => d && d.typeGroup === tab.value)
        .map((d, i) => ({ ...d, label: SHORT[d.title] || d.title, seq: i }))
        .sort((a, b) => rank(a.title) - rank(b.title) || (a.order ?? 99) - (b.order ?? 99) || a.seq - b.seq);
}
// abas:fim

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

    // Só depois da resposta do Apex aparece o "No documents yet." (sem arquivo o Apex devolve null).
    loaded = false;
    status;
    picked; // aba que o usuário clicou

    connectedCallback(){
        this.handleDocuments();
    }

    @wire(getRecord, { recordId: '$recordId', fields: [STATUS] })
    wiredStatus({ data }) {
        if (data) this.status = data.fields.Status__c.value;
    }

    get tabs() {
        return TABS.map(t => {
            const docs = docsOf(this.latestDocs, t);
            return { ...t, docs, isEmpty: this.loaded && !this.error && docs.length === 0 };
        });
    }

    get activeTab() {
        if (this.picked) return this.picked;
        const tabs = this.tabs;
        const byStage = STAGE_TAB[this.status] || (this.status ? 'FullForms' : 'BigEnvelope');
        const tab = tabs.find(t => t.value === byStage);
        if (tab && tab.docs.length) return byStage;
        const first = tabs.find(t => t.docs.length);
        return first ? first.value : byStage;
    }

    handleTabActive(event) {
        // o tabset também avisa quando a aba muda pelo estágio; só guarda o que foi clique de verdade
        if (event.target.value !== this.activeTab) this.picked = event.target.value;
    }

    @api async handleDocuments() {
        await getContentDocuments({
            recordId : this.recordId
        })
        .then(result => {
          
          this.latestDocs = result?.latestDocs;
          // this.allDocs                 = result?.latestDocs;
          // this.replyDocs               = result?.replyDocs;
          // this.application             = result?.application;
          // this.previuosAddresses       = result?.previousAddresses;
          // this.lastUKEmployer          = result?.lastUKEmployer;
          // this.abroadEmployers         = result?.abroadEmployers;
          // this.lastUKAddresses         = result?.latestUKAddress;
          // this.isSendToClientAppStatus = result?.isSendToClientAppStatus;
          // this.isPaidApplicationPayment= result?.isPaidApplicationPayment;
          // this.templates               = result?.templateData;
          // this.emailSubject            = result?.templateData?.emailSubject;
          // if(result.isSendToClientAppStatus) {
          //   let successReplyDoc = false;
          //   let rejectReplyDoc = false;
          //   this.replyDocs.some( doc => {
          //     if(doc.title.includes('C2')||doc.title.includes('C3')){
          //       successReplyDoc = true;
          //     } else if(doc.title.includes('Reject')) {
          //       rejectReplyDoc = true;
          //     }
          //   })
          //   if (successReplyDoc) {
          //     this.replyDocs.map( item =>{
          //       if (item.title.includes('C2') || item.title.includes('C3') || item.title.includes('Next Step 1') || item.title.includes('Next Step 2') || item.title.includes('Annual Service') || item.title.includes('Bank Transfer') || item.title.includes('Private Pensions')) {
          //         item["isCheck"] = true;
          //       } else item["isCheck"] = false;
          //     })
          //   }
          //   if (rejectReplyDoc) {
          //     this.replyDocs.map( item =>{
          //       if (item.title.includes('Reject') || item.title.includes('APPEAL')) {
          //         item["isCheck"] = true;
          //       } else item["isCheck"] = false;
          //     })
          //   }
          // }
        }).catch(error => {
          this.error = error;
        }).finally(() => {
          this.loaded = true;
        });
        // if (this.replyDocs) this.isExistReplyDocs = true;
    }
    navigateToFiles(event) {
        const documentName = event.currentTarget.getAttribute("value");
        const searchValue = this.latestDocs.find(el => el.title == documentName);
        // Sem structuredClone aqui: o item é um proxy do LWC e o clone dá DataCloneError antes de abrir o arquivo.
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

  //   navigateToReplyFiles(event) {
  //     var documentName = event.currentTarget.getAttribute("value");
  //     var searchValue = this.replyDocs.find(el => el.title == documentName);
  //     this[NavigationMixin.Navigate]({
  //       type: "standard__namedPage",
  //       attributes: {
  //         pageName: "filePreview",
  //       },
  //       state: {
  //         recordIds: searchValue.documentId
  //     },
  //   });
  // }

    handleDisplayAll() {
      this[ NavigationMixin.Navigate ]( {
        type: 'standard__recordRelationshipPage',
        attributes: {
            recordId: this.recordId,
            objectApiName: 'Basic__c',
            relationshipApiName: 'AttachedContentDocuments',
            actionName: 'view'
        }
    } );
    }
  //   handleOpenModal() {
  //     this.isOpenModal = !this.isOpenModal;
  // }
  // closePopup() {
  //   this.isOpenModal = false;
  // }

  // closeResultPopup() {
  //   this.isOpenResultModal = !this.isOpenResultModal;
  // }
  @api get isApproved() {
    return true;
  }

  // regenerateCustomLetter(event) {
  //   this.requestData = {
  //     applicationId    : this.recordId,
  //     freeformTextLine1: event.detail.freeformTextLine1,
  //     freeformTextLine2: event.detail.freeformTextLine2,
  //     freeformTextLine3: event.detail.freeformTextLine3,
  //     freeformTextLine4: event.detail.freeformTextLine4,
  //     freeformTextLine5: event.detail.freeformTextLine5,
  //     newPreviousAddressData: event.detail.newPreviousAddressData,
  //     newEmployerData: event.detail.newEmployerCheckboxData,
  //     customLetterDate : event.detail.currentDate
  //   }
  //   this.changeApplication();
  // }

  // changeApplication() {
  //   this.isShowSpinner = true;
  //   changeCustomLetter({
  //     letterData : JSON.parse(JSON.stringify(this.requestData))
  //   })
  //   .then(result => {
  //     if (result == 'true') {
  //       this.createNewContentDocument();
  //       const evt = new ShowToastEvent({
  //         title: 'Success',
  //         message: 'You have successfully changed the Custom Letter',
  //         variant: 'success'
  //       });
  //       this.dispatchEvent(evt);
  //       this.isShowSpinner = false;
  //     }
  //   }).catch(error => {
  //       this.dispatchEvent(new ShowToastEvent({
  //         title: 'Error',
  //         message: 'You didn\'t changed the Custom Letter. Error is: ' + error,
  //         variant: 'error',
  //     }));
  //     this.isShowSpinner = false;
  //     //this.isOpenModal = false;
  //   });
  // }
  // createNewContentDocument() {
  //   pdfAction({
  //     applicationId : this.recordId
  //   }).then(result => {
  //     window.location.reload();
  //   }).catch(error => {
  //     //this.isOpenModal = false;
  //   })
  // }

  // get colorValue() {
  //   let replyStatus = this.latestDocs.find( item => item.title == 'HMRC Assessment').hmrcReplyStatus;
  //   return replyStatus == 'APPROVED' ? 'color:green' :
  //             replyStatus == 'REJECT' ? 'color:red' :
  //                 replyStatus == 'UNKNOWN' ? 'color:blue' : null;
  // }

  // handleCheck(event) {
  //   let checkboxName = event.target.attributes["data-id"].nodeValue;
  //   let currentOject = this.replyDocs.find(doc =>
  //     doc.title == checkboxName
  //   )
  //   currentOject.isCheck = !currentOject.isCheck;
  // }

  // handleSendEmail() {
  //   this.replyDocs.map( item =>{
  //     if (item.title.includes('C2') || item.title.includes('C3')) {
  //       this.currentTemplate = this.templates.successTemplate;
  //     } else if (item.title.includes('Reject')) {
  //       this.currentTemplate = this.templates.rejectTempalte;
  //     }
  //   })
  //   this.isOpenResultModal = !this.isOpenResultModal;
  //   // if (this.isPaidApplicationPayment) {
  //   //   this.isOpenResultModal = !this.isOpenResultModal;
  //   // } else {
  //   //   this.dispatchEvent(new ShowToastEvent({
  //   //       title: 'Error',
  //   //       message: 'Application Fee NOT PAID',
  //   //       variant: 'error',
  //   //   }));
  //   //   sendMissingPaymentsEmail({
  //   //       appId: this.recordId
  //   //   })
  //   // }
  // }

  // handleSendMissingPaymentMessage() {
  //   this.isOpenResultModal = !this.isOpenResultModal;
  //   sendMissingPaymentsEmail({
  //     appId: this.recordId
  //   })
  // }

  // handleChangeBody(event) {
  //   this.currentTemplate = event.bodyHTML;
  // }

  // @api
  // async handleEventSend(event) {
  //   let docIds = new Array();
  //   this.replyDocs.map(doc => {
  //     if (doc.isCheck == true) {
  //       let docId = doc.documentId;
  //       docIds.push(docId);
  //     }
  //   });
  //   this.showMessageSpinner = !this.showMessageSpinner;
  //       let sendData = {
  //         applicationId: this.recordId,
  //         htmlBody: event.detail.template,
  //         subject : event.detail.subject,
  //         documentsIds: docIds
  //       };
  //       console.log(event.detail.template);
  //       await sendEmail({
  //         emailData: sendData
  //       })
  //       .then(result => {
  //         if (result.isSuccess) {
  //           const evt = new ShowToastEvent({
  //             title: 'Success',
  //             message: 'You have sent result email to client!',
  //             variant: 'success'
  //           });
  //           this.dispatchEvent(evt);
  //         } else {
  //           const evt = new ShowToastEvent({
  //             title: 'Error',
  //             message: result.successMessage,
  //             variant: 'error'
  //           });
  //           this.dispatchEvent(evt);
  //         }
  //         this.isOpenResultModal = !this.isOpenResultModal;
  //         window.location.reload();
  //       }).catch(error => {
  //         const evt = new ShowToastEvent({
  //           title: 'Error',
  //           message:  error.body.message,
  //           variant: 'error'
  //         });
  //         this.dispatchEvent(evt);
  //         this.isOpenResultModal = !this.isOpenResultModal;
  //       });
  // }
}