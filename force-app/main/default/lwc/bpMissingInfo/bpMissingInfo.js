import { LightningElement, api } from 'lwc';

import getMissing from '@salesforce/apex/BP_PortalUtils.getMissing';
import setMissing from '@salesforce/apex/BP_PortalUtils.setMissing';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class BpMissingInfo extends LightningElement {
    _recordId;

    missingItems = [];
    isLoading = false;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;

        if (value) {
            this.loadMissing();
        }
    }

    get hasMissing() {
        return this.missingItems.length > 0;
    }

    async loadMissing() {
        this.isLoading = true;

        try {
            this.missingItems = await getMissing({
                basicId: this.recordId
            });
        } catch (error) {
            this.showToast('Error', this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleCheckMissing() {
        this.isLoading = true;

        try {
            await setMissing({
                basicId: this.recordId
            });

            await this.loadMissing();

            this.showToast(
                'Success',
                'Missing information has been refreshed.',
                'success'
            );
        } catch (error) {
            this.showToast('Error', this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map(e => e.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unknown error';
    }
}