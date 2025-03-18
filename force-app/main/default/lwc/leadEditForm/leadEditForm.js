import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, getFieldValue } from "lightning/uiRecordApi";

import PHONE_FIELD from "@salesforce/schema/Lead.Phone";
import ESTIMATE_FIELD from "@salesforce/schema/Lead.Estimate__c";

const fields = [PHONE_FIELD, ESTIMATE_FIELD];

export default class LeadEditForm extends LightningElement {
    @api recordId;
    @api objectApiName;
    isShowEditForm = false;

    @wire(getRecord, { recordId: "$recordId", fields })
    lead;

    handleSuccess() {
        this.showMessage('Success!', 'Lead edited successfully.', 'success');
        this.handleOpenModal();
    }

    showMessage(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(evt);
    }

    handleOpenModal() {
        this.isShowEditForm = !this.isShowEditForm;
    }

    handleClose() {
        this.handleOpenModal();
    }

    get phone() {
        return getFieldValue(this.lead.data, PHONE_FIELD);
    }

    get estimate() {
        return getFieldValue(this.lead.data, ESTIMATE_FIELD);
    }

    handleCopy() {
        const input = document.createElement("textarea");
        document.body.appendChild(input);
        input.select();
        if(navigator.clipboard){
            copy(this.phone);
        } else {
            // deprecated but still a good fallback because it is supported in most of the browsers
            console.log('In else');
            document.execCommand('copy');
        }
        document.body.removeChild(input);
    }
}

export const copy = async textToCopy =>
    await navigator.clipboard.writeText(textToCopy)
                             .catch(err =>
                                console.error(JSON.stringify(err)),
                                err => console.error(JSON.stringify(err)
                                )
                            );