import { LightningElement, api } from 'lwc';

export default class EditRefundRequestModal extends LightningElement {
    @api recordId;
    @api firstName;
    @api secondName;
    @api nino;
    @api phone;
    @api fullAddress;

    allowedFormats = [
        'font',
        'size',
        'bold',
        'italic',
        'underline',
        'strike',
        'list',
        'indent',
        'align',
        'link',
        'image',
        'clean',
        'table',
        'header',
        'color',
        'background',
        'code',
        'code-block',
        'script',
        'blockquote',
        'direction',
    ];

    closeAction() {
        this.dispatchEvent(new CustomEvent('hidepopup'));
    }

    handleCreatePDF() {
        this.dispatchEvent(new CustomEvent(
            'generatepdf', {
                detail: {}
           })
        );
        this.closeAction();
    }
}