import { LightningElement, api } from 'lwc';

export default class C2CheckConfirmModal extends LightningElement {
    @api title = 'Confirmation';
    @api message = 'Have you requested a copy?';
    @api isModalOpen = false;

    @api openModal() {
        this.isModalOpen = true;
    }

    closeModal() {
        this.isModalOpen = false;
    }

    handleConfirm() {
        this.dispatchEvent(
            new CustomEvent('confirm', {
                "detail" : 'Yes'
            })
        );
        this.closeModal();
    }

    handleCancel() {
        this.dispatchEvent(
            new CustomEvent('confirm', {
                "detail" : 'No'
            })
        );
        this.closeModal();
    }
}