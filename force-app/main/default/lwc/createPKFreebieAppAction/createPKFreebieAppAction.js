import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class CreatePKFreebieAppAction extends LightningElement {
    connectedCallback() {
        this.openAction();
    }

    openAction() {
        this[NavigationMixin.Navigate]({
            type: 'standard__quickAction',
            attributes: {
                actionName: 'Global.Create_App_Test'
            }
        });
    }
}