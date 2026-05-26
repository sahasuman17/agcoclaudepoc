/**
 * @description Controller for the caseCreate LWC.
 *              Implements the Product Information section for the "Parts Technical Help" case type.
 *              MP-7 scope: asset lookup, part description auto-population, and save-as-draft.
 * @author      Suman Saha
 * @story       MP-7
 */
import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getPicklistValues, getObjectInfo } from 'lightning/uiObjectInfoApi';
import NO_CAUSAL_PART_REASON_FIELD from '@salesforce/schema/Case.No_Causal_Part_Reason__c';

import findAssetBySerial  from '@salesforce/apex/CaseCreateController.findAssetBySerial';
import getPartDescription from '@salesforce/apex/CaseCreateController.getPartDescription';
import saveCaseAsDraft    from '@salesforce/apex/CaseCreateController.saveCaseAsDraft';

export default class CaseCreate extends LightningElement {

    // ─────────────────────────────────────────────────────────────────────────
    // Reactive Properties
    // ─────────────────────────────────────────────────────────────────────────

    // Case identifiers (populated after save)
    @track caseId;
    @track caseNumber = '';
    @track status = '';

    // Serial / Asset
    @track serialNumber = '';
    @track assetId;
    @track assetFound = false;
    @track assetNotApplicable = false;

    // Row 1 — disabled after asset lookup
    @track brand = '';
    @track machineType = '';
    @track series = '';
    @track modelNumber = '';

    // Row 2 — conditional editability
    @track unitOfMeasure = '';
    @track machineUsage = '';
    @track usageAvailable = false;
    @track usedWith = '';
    @track engineSerial = '';

    // Row 3 — part information
    @track partNumberId;
    @track partDescription = '';
    @track noPartReason = '';
    @track noPartReasonOptions = [];

    // Collapsible section state
    @track assetSectionOpen = true;
    @track productSectionOpen = true;

    // ─────────────────────────────────────────────────────────────────────────
    // Wire — Picklist values for No_Causal_Part_Reason__c
    // ─────────────────────────────────────────────────────────────────────────

    @wire(getObjectInfo, { objectApiName: 'Case' })
    caseObjectInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$caseObjectInfo.data.defaultRecordTypeId',
        fieldApiName: NO_CAUSAL_PART_REASON_FIELD
    })
    wiredNoPartReasonValues({ data, error }) {
        if (data) {
            this.noPartReasonOptions = data.values.map(item => ({
                label: item.label,
                value: item.value
            }));
        } else if (error) {
            this.noPartReasonOptions = [];
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Getters
    // ─────────────────────────────────────────────────────────────────────────

    get isMachineUsageDisabled() {
        return this.usageAvailable;
    }

    get assetSectionClass() {
        return this.assetSectionOpen
            ? 'slds-section slds-is-open'
            : 'slds-section';
    }

    get productSectionClass() {
        return this.productSectionOpen
            ? 'slds-section slds-is-open'
            : 'slds-section';
    }

    get displayCaseNumber() {
        return this.caseNumber ? this.caseNumber : '—';
    }

    get displayStatus() {
        return this.status ? this.status : 'New';
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Header / Section Toggle Handlers
    // ─────────────────────────────────────────────────────────────────────────

    handleToggleAssetSection() {
        this.assetSectionOpen = !this.assetSectionOpen;
    }

    handleToggleProductSection() {
        this.productSectionOpen = !this.productSectionOpen;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Asset / Serial Number Handlers
    // ─────────────────────────────────────────────────────────────────────────

    handleAssetNotApplicableChange(event) {
        this.assetNotApplicable = event.target.checked;
    }

    handleSerialNumberChange(event) {
        this.serialNumber = event.target.value;
    }

    /** Trigger asset lookup on Enter key */
    handleSerialNumberKeyUp(event) {
        if (event.key === 'Enter' && this.serialNumber) {
            this._lookupAsset();
        }
    }

    /** Trigger asset lookup on blur when field has a value */
    handleSerialNumberBlur() {
        if (this.serialNumber) {
            this._lookupAsset();
        }
    }

    // Guard: prevents double Apex call when Enter (onkeyup) is followed by blur
    _lastLookedUpSerial = '';

    /** Imperative call to findAssetBySerial */
    _lookupAsset() {
        if (!this.serialNumber || this.serialNumber === this._lastLookedUpSerial) {
            return;
        }
        this._lastLookedUpSerial = this.serialNumber;

        findAssetBySerial({ serialNumber: this.serialNumber })
            .then(result => {
                if (result) {
                    this.assetId        = result.assetId;
                    this.brand          = result.brand          || '';
                    this.machineType    = result.machineType    || '';
                    this.series         = result.series         || '';
                    this.modelNumber    = result.modelNumber    || '';
                    this.unitOfMeasure  = result.unitOfMeasure  || '';
                    this.machineUsage   = result.machineUsage   || '';
                    this.usageAvailable = result.usageAvailable || false;
                    this.engineSerial   = result.engineSerial   || '';
                    this.assetFound     = true;
                } else {
                    this._clearProductFields();
                    this.dispatchEvent(new ShowToastEvent({
                        title:   'Asset Not Found',
                        message: 'No asset was found for the entered serial number.',
                        variant: 'warning'
                    }));
                }
            })
            .catch(error => {
                this._clearProductFields();
                this.dispatchEvent(new ShowToastEvent({
                    title:   'Error',
                    message: error.body?.message || 'An error occurred while searching for the asset.',
                    variant: 'error'
                }));
            });
    }

    /** Clear Search button — resets all product info fields client-side */
    handleClearSearch() {
        this.serialNumber = '';
        this._lastLookedUpSerial = '';
        this._clearProductFields();
    }

    _clearProductFields() {
        this.assetId        = undefined;
        this.assetFound     = false;
        this.brand          = '';
        this.machineType    = '';
        this.series         = '';
        this.modelNumber    = '';
        this.unitOfMeasure  = '';
        this.machineUsage   = '';
        this.usageAvailable = false;
        this.engineSerial   = '';
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Product Information — Row 2 Handlers
    // ─────────────────────────────────────────────────────────────────────────

    handleMachineUsageChange(event) {
        this.machineUsage = event.target.value;
    }

    handleUsedWithChange(event) {
        this.usedWith = event.target.value;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Product Information — Row 3 Handlers
    // ─────────────────────────────────────────────────────────────────────────

    /** lightning-record-picker change — fires when user selects or clears a Part */
    handlePartNumberChange(event) {
        const selectedId = event.detail.recordId;

        if (selectedId) {
            this.partNumberId = selectedId;
            getPartDescription({ partId: selectedId })
                .then(description => {
                    this.partDescription = description || '';
                })
                .catch(error => {
                    this.partDescription = '';
                    this.dispatchEvent(new ShowToastEvent({
                        title:   'Error',
                        message: error.body?.message || 'Could not retrieve part description.',
                        variant: 'error'
                    }));
                });
        } else {
            // Part removed — clear description
            this.partNumberId    = undefined;
            this.partDescription = '';
        }
    }

    handleNoPartReasonChange(event) {
        this.noPartReason = event.detail.value;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Footer Button Handlers
    // ─────────────────────────────────────────────────────────────────────────

    handleSave() {
        const caseRecord = {
            AssetId:                  this.assetId,
            Brand__c:                 this.brand,
            Machine_Type__c:          this.machineType,
            Series__c:                this.series,
            Model_Number__c:          this.modelNumber,
            Unit_of_Measure__c:       this.unitOfMeasure,
            Machine_Usage__c:         this.machineUsage,
            Part_Number__c:           this.partNumberId,
            Part_Description__c:      this.partDescription,
            No_Causal_Part_Reason__c: this.noPartReason,
            Used_With__c:             this.usedWith
        };

        // Include the caseId for upsert on subsequent saves
        if (this.caseId) {
            caseRecord.Id = this.caseId;
        }

        saveCaseAsDraft({ caseRecord })
            .then(result => {
                this.caseId     = result.caseId;
                this.caseNumber = result.caseNumber;
                this.status     = result.status;

                this.dispatchEvent(new ShowToastEvent({
                    title:   'Case Saved',
                    message: 'Case ' + result.caseNumber + ' saved as Draft.',
                    variant: 'success'
                }));
            })
            .catch(error => {
                this.dispatchEvent(new ShowToastEvent({
                    title:   'Save Failed',
                    message: error.body?.message || 'An error occurred while saving the case.',
                    variant: 'error'
                }));
            });
    }

    /** Submit — out of scope for MP-7; stub only */
    handleSubmit() {
        this.dispatchEvent(new ShowToastEvent({
            title:   'Not Available',
            message: 'Submit will be available in a future release.',
            variant: 'info'
        }));
    }

    /** Resolve — out of scope for MP-7; stub only */
    handleResolve() {
        this.dispatchEvent(new ShowToastEvent({
            title:   'Not Available',
            message: 'Resolve will be available in a future release.',
            variant: 'info'
        }));
    }

    /** Cancel — clears all reactive properties */
    handleCancel() {
        this.caseId              = undefined;
        this.caseNumber          = '';
        this.status              = '';
        this.serialNumber        = '';
        this._lastLookedUpSerial = '';
        this.assetNotApplicable  = false;
        this._clearProductFields();
        this.usedWith           = '';
        this.partNumberId       = undefined;
        this.partDescription    = '';
        this.noPartReason       = '';
    }
}
