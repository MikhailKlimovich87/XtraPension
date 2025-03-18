import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class ReportInfo extends NavigationMixin(LightningElement) {
    viewReport( event ) {
        this[ NavigationMixin.Navigate ]({
            type: 'standard__recordPage',
            attributes: {
                recordId: '00O7Y000001kWHGUA2',
                objectApiName: 'Report',
                actionName: 'view'
            }
        });

    }
}