import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class DoneButtonAction extends LightningElement {
    @api recordId;

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}