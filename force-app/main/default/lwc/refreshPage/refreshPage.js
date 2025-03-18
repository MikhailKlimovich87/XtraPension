import { LightningElement } from 'lwc';

export default class RefreshPage extends LightningElement {
    disconnectedCallback() {
        window.location.reload();
    }
}