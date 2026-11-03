import {LightningElement, track, wire} from 'lwc';
import {ShowToastEvent} from "lightning/platformShowToastEvent";
import { NavigationMixin } from 'lightning/navigation';
// Controllers
import getDataFromUploadFile from '@salesforce/apex/HMRC_ReplyTab.getTextRecognitionData';
import uploadFile from '@salesforce/apex/HMRC_ReplyTab.uploadFile';
//
import APPLICATION_OBJECT from '@salesforce/schema/Application__c';
import TYPE_OF_EMPLOYMENT_FIELD from "@salesforce/schema/Application__c.HMRC_Reply_Status__c";
import {getObjectInfo, getPicklistValues} from "lightning/uiObjectInfoApi";

export default class HmrcReplyTab extends NavigationMixin(LightningElement) {
    // Variables
    file;
    isLoadingFile = false;
    isLoadingUpdate = false;
    extractedData = {
        currentReplyType: {fieldValue: '', isMatch: false},
        letterDate: {fieldValue: '', isMatch: false},
        shortfall: {fieldValue: '', isMatch: false},
        caseworker: {fieldValue: '', isMatch: false},
        moveToStatus: {fieldValue: '', isMatch: false},
        xpReceivedDate: {fieldValue: '', isMatch: false},

        niNumber: {fieldValue: '', isMatch: false},
        ourReference: {fieldValue: '', isMatch: false},
        yourReference: {fieldValue: '', isMatch: false},
        qualifyingYears: {fieldValue: '', isMatch: false},
        overseasReference: {fieldValue: '', isMatch: false},
        paymentReference: {fieldValue: '', isMatch: false},

        fileData: {fieldValue: '', isMatch: false},
        appId: {fieldValue: '', isMatch: false}
    }
    isShowForm = false;

    typesOfHMRCReply = [];
    moveToStatus = 'Not Move';
    todayDate = new Date();

    // Wire
    @wire(getObjectInfo, {objectApiName: APPLICATION_OBJECT})
    applicationInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$applicationInfo.data.defaultRecordTypeId',
        fieldApiName: TYPE_OF_EMPLOYMENT_FIELD
    })
    replyTypes({error, data}) {
        if (data) {
            console.log('data', data);
            this.typesOfHMRCReply = [...data.values];
            this.typesOfHMRCReply.push({value: 'VOLUNTARY NI PAYMENT RECEIPT', label: 'VOLUNTARY NI PAYMENT RECEIPT'});
        }
        if (error) {
            console.log('Error uploading picklist values');
        }
    }

    async handleChooseFile(event) {
        try {
            // Create a hidden file input element
            const fileInput = document.createElement('input');
            fileInput.type = 'file';
            fileInput.style.display = 'none';

            // Set accepted formats
            const formats = [".pdf"];
            fileInput.accept = formats.join(',');

            const self = this;
            // Add event listener for when a file is selected
            fileInput.addEventListener('change', async function (event) {
                const file = event.target.files[0];
                if (file) {
                    // Validate file format
                    const extension = file.name.toLowerCase().substring(file.name.lastIndexOf('.'));
                    if (!formats.includes(extension)) {
                        self.toast(`Invalid file format. Please upload: ${formats.join(', ')}`, "error");
                        return;
                    }

                    // Validate file size (optional)
                    const maxSize = 4 * 1024 * 1024; // 4MB
                    if (file.size > maxSize) {
                        self.toast(`File is too large. Maximum size is 4MB.`, "error");
                        return;
                    }

                    // Handle the selected file
                    console.log('File selected:', file.name);
                    console.log('File type:', file.type);
                    console.log('File size:', file.size, 'bytes');
                    self.file = file;
                }
            });

            // Add to document and trigger click
            document.body.appendChild(fileInput);
            fileInput.click();

            // Clean up
            document.body.removeChild(fileInput);
        } catch (err) {
            console.error(err);
            this.toast(err.message, 'error');
        }
    }

    async handleUploadFile() {
        if (!this.file) {
            this.toast(`File is not chosen.`, "error");
            return;
        }
        this.isLoadingFile = true;
        this.isShowForm = false;
        try {
            const {base64} = await this.convertFileToBase64(this.file);
            const {isSuccess, errorMessage, extractedData} = await getDataFromUploadFile({base64: base64});
            
            if (isSuccess === false) {
                this.toast(extractedData?.errorMessage ?? 'An error occurred while extracting data from the file. Error: ' + errorMessage, 'error');
            } else if (isSuccess === true) {
                this.extractedData = this.formatExtractedData(extractedData ?? {});
                console.log('Extracted Data:', this.extractedData);
                
                this.extractedData.fileData = { fieldValue: base64, isMatch: false };
                this.isShowForm = true;
            }
        } catch (err) {
            console.error(err);
            this.toast(err.message, 'error');
        } finally {
            this.isLoadingFile = false;
        }
    }

    navigateToCurrentApplication(appId) {
        console.log('Navigating to application with Id:', appId);
        if (!appId || appId.trim() === '') {
            console.error('Application ID is missing or empty');
            this.toast('Cannot navigate: Application ID not found', 'error');
            return;
        }
        try {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: appId,
                    objectApiName: APPLICATION_OBJECT,
                    actionName: 'view'
                }
            });
        } catch (err) {
            console.error('Navigation error:', err);
            this.toast('Failed to navigate to application: ' + err.message, 'error');
        }
    }

    formatExtractedData(extractedData = {}) {
        return {
            currentReplyType: { fieldValue: extractedData?.currentReplyType?.fieldValue ?? '', isMatch: extractedData?.currentReplyType?.isMatch ?? false },
            letterDate: extractedData?.letterDate ? { fieldValue: this.formatDate(extractedData?.letterDate?.fieldValue), isMatch: extractedData?.letterDate?.isMatch ?? false } : { fieldValue: '', isMatch: false },
            shortfall: { fieldValue: extractedData?.shortfall?.fieldValue ?? '', isMatch: extractedData?.shortfall?.isMatch ?? false },
            caseworker: { fieldValue: extractedData?.caseworker?.fieldValue ?? '', isMatch: extractedData?.caseworker?.isMatch ?? false },
            moveToStatus: { fieldValue: extractedData?.moveToStatus?.fieldValue ?? 'Not Move', isMatch: extractedData?.moveToStatus?.isMatch ?? false },
            xpReceivedDate: { fieldValue: extractedData?.xpReceivedDate?.fieldValue ?? '', isMatch: extractedData?.xpReceivedDate?.isMatch ?? false },
            appId: { fieldValue: extractedData?.appId?.fieldValue ?? '', isMatch: extractedData?.appId?.isMatch ?? false },

            niNumber: { fieldValue: extractedData?.niNumber?.fieldValue ?? '', isMatch: extractedData?.niNumber?.isMatch ?? false },
            ourReference: { fieldValue: extractedData?.ourReference?.fieldValue ?? '', isMatch: extractedData?.ourReference?.isMatch ?? false },
            yourReference: { fieldValue: extractedData?.yourReference?.fieldValue ?? '', isMatch: extractedData?.yourReference?.isMatch ?? false },
            qualifyingYears: { fieldValue: extractedData?.qualifyingYears?.fieldValue ?? 0, isMatch: extractedData?.qualifyingYears?.isMatch ?? false },
            overseasReference: { fieldValue: extractedData?.overseasReference?.fieldValue ?? '', isMatch: extractedData?.overseasReference?.isMatch ?? false },
            paymentReference: { fieldValue: extractedData?.paymentReference?.fieldValue ?? '', isMatch: extractedData?.paymentReference?.isMatch ?? false },

            fileData: { fieldValue: extractedData?.fileData?.fieldValue ?? '', isMatch: extractedData?.fileData?.isMatch ?? false }
        }
    }

    formatDate(dateValue){
        const monthMap = {
            'January': '01', 'February': '02', 'March': '03', 'April': '04',
            'May': '05', 'June': '06', 'July': '07', 'August': '08',
            'September': '09', 'October': '10', 'November': '11', 'December': '12'
        };

        const parts = dateValue.split(' '); // ["25", "March", "2026"]
        const day = parts[0].padStart(2, '0'); // Ensures "05" instead of "5"
        const month = monthMap[parts[1]];
        const year = parts[2];

        const formattedDate = `${year}-${month}-${day}`; // "2026-03-25"

        return formattedDate; 
    }

    clearExtractedData() {
        this.extractedData = {
            currentReplyType: '',
            letterDate: '',
            shortfall: '',
            caseworker: '',
            moveToStatus: 'Not Move',
            xpReceivedDate: '',

            niNumber: '',
            ourReference: '',
            yourReference: '',
            qualifyingYears: 0,
            overseasReference: '',
            paymentReference: '',
            fileData: '',
            appId: ''
        }
    }

    handleCancel() {
        this.file = null;
        this.isShowForm = false;
        this.clearExtractedData();
    }

    handleInputChange(event) {
        try {
            console.log(event);
            const fieldName = event.target.dataset.fieldName;
            const value = event.detail.value;
            console.log(fieldName, value);
            event.detail.value = value;
            this.extractedData[fieldName].fieldValue = value;
        } catch (err) {
            console.error(err);
        }
    }

    async handleUpdate() {
        // if (this.isFormInputValid()) {
        //     return;
        // }
        this.isLoadingUpdate = true;
        try {
            const uploadResult = await uploadFile({request: this.extractedData});
            console.log('uploadFile result:', uploadResult);

            if (uploadResult?.isSuccess) {
                this.toast('Application has been updated successfully', 'success');
                // Save the appId before clearing data
                const appIdToNavigate = this.extractedData.appId.fieldValue;
                this.handleCancel();
                // Navigate using the saved appId
                if (appIdToNavigate) {
                    this.navigateToCurrentApplication(appIdToNavigate);
                }
            } else if (!uploadResult?.isSuccess) {
                this.toast(uploadResult?.errorMessage ?? 'An error occurred while updating the application. Error: ' + uploadResult?.errorMessage, 'error');
            }
            console.log(this.extractedData);
        } catch (err) {
            this.toast(err.message, 'error');
        } finally {
            this.isLoadingUpdate = false
        }

    }

    isFormInputValid() {
        let isValid = true;
        let inputFields = this.template.querySelectorAll(".form-input");
        let isScrollToElement = true;
        inputFields.forEach((inputField) => {
            if (!inputField.checkValidity()) {
                inputField.reportValidity();
                if (isScrollToElement) {
                    inputField.scrollIntoView({behavior: "smooth", block: "center", inline: "nearest"});
                    isScrollToElement = false;
                }
                isValid = false;
            }
        });
        if (!inputFields.length) {
            isValid = false;
        }
        return isValid;
    }

    get shortfallOptions() {
        return [
            {label: 'Yes', value: 'Yes'},
            {label: 'No', value: 'No'}
        ];
    }

    get moveToStatusOptions() {
        return [
            {label: 'Not Move', value: 'Not Move'},
            {label: '64-8 Bounce', value: '64-8 Bounce'},
            {label: 'HMRC Reply 1', value: 'HMRC Reply 1'},
            {label: 'HMRC Reply 2', value: 'HMRC Reply 2'},
            {label: 'Send to Client', value: 'Send to Client'}
        ];
    }

    get fileSize() {
        return this.formatFileSize(this.file.size ?? 0);
    }

    get disableUploadFile() {
        return this.isLoadingFile || this.isLoadingUpdate
    }

    get disableUpdate() {
        return this.isLoadingUpdate
    }

    get todayPlaceholder() {
        return this.todayDate.toLocaleDateString('en-GB');
    }

    get isRequiredLetterDate() {
        const type = this.extractedData.currentReplyType;
        return type === '2024ANNUAL' ||
            type === 'C2' ||
            type === 'C3' ||
            type === 'C2 AGT' ||
            type === 'BadStatement';
    }

    formatFileSize(bytes = 0) {
        if (bytes === 0) return '0 Bytes';
        const k = 1024;
        const sizes = ['Bytes', 'KB', 'MB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    }

    convertFileToBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();

            reader.onload = function (e) {
                // Extract base64 data (remove data:image/png;base64, prefix)
                const base64Data = e.target.result.split(',')[1];
                const fileType = file.type.split("/")[1];
                resolve({
                    base64: base64Data,
                    fileType: fileType,
                    fileName: file.name,
                    fileSize: file.size
                });
            };

            reader.onerror = function (error) {
                reject(error);
            };

            reader.readAsDataURL(file);
        });
    }

    toast(title, variantType) {
        const toastEvent = new ShowToastEvent({
            title,
            variant: variantType
        })
        this.dispatchEvent(toastEvent)
    }
}