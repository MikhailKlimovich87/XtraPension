import { LightningElement, api } from 'lwc';

export default class PrintingHouseReply extends LightningElement {
    isOpenReplyModal = false;
    @api recordId;
    handleOpenModal() {
        this.isOpenReplyModal = !this.isOpenReplyModal;
    }
}