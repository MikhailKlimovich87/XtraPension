import { LightningElement } from 'lwc';

export default class EditHRMCReplyModal extends LightningElement {
    closeAction() {
        this.dispatchEvent(new CustomEvent('hidepopup'));
    }
}