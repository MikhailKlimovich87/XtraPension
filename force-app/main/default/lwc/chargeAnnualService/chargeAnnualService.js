import { LightningElement } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class ChargeAnnualService extends LightningElement {
    closeModal() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}