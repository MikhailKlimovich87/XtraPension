import { LightningElement, api } from 'lwc';

export default class C2CheckConfirmModal extends LightningElement {
    @api title = 'Confirmation';
    @api message = 'Have you requested a copy?';
    @api isModalOpen = false;
    isOpenPaymentMadeClientQuestion = false;
    isOpenWhenQuestion = false;
    @api checkData;
    requestCopy;
    paymentMadeByClient;
    when;

    @api openModal() {
        this.isModalOpen = true;
    }

    closeModal() {
        this.isModalOpen = false;
    }

    handleChangePaymentMadeClient(event) {
        if(event.target.value == 'Yes') this.isOpenWhenQuestion = true;
        else this.isOpenWhenQuestion = false;
        this.paymentMadeByClient = event.target.value;
    }

    handleChangeCopyRequest(event) {
        if(event.target.value == 'Yes') this.isOpenPaymentMadeClientQuestion = true;
        else this.isOpenPaymentMadeClientQuestion = false;
        this.requestCopy = event.target.value;
    }

    handleChangeWhenDate(event) {
        this.when = event.target.value;
    }

    handleConfirm(event) {
        this.dispatchEvent(
            new CustomEvent('confirm', {
                "detail" : {
                    "requestCopy" : this.requestCopy,
                    "paymentMadeByClient" : this.paymentMadeByClient,
                    "whenData" : this.when
                }
            })
        );
        this.closeModal();
    }

    handleCancel() {
        this.dispatchEvent(
            new CustomEvent('cancel')
        );
        this.closeModal();
    }


    get options() {
        return [
            { label: 'Yes', value: 'Yes' },
            { label: 'No', value: 'No' }
        ];
    }
}