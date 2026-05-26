/**
 * @description Controller for the caseCreate LWC.
 *              Handles the Product Information section (MP-7):
 *              serial-number lookup, asset field population, part picker,
 *              and save-as-draft flow.
 *
 *              Submit / Resolve are stub buttons wired in MP-5.
 *
 * @author      Suman Saha
 * @story       MP-7 — Support Cases: Product Information Section
 * @apiVersion  66.0
 */
import { LightningElement } from 'lwc';
import findAssetBySerial from '@salesforce/apex/CaseCreateController.findAssetBySerial';
import getPartDescription from '@salesforce/apex/CaseCreateController.getPartDescription';
import saveCaseAsDraft from '@salesforce/apex/CaseCreateController.saveCaseAsDraft';

/** @type {Array<{label:string, value:string}>} */
const NO_PART_REASON_OPTIONS = [
    { label: 'No Fault Found', value: 'No Fault Found' },
    { label: 'Legacy Part',    value: 'Legacy Part'    },
    { label: 'Missing Part',   value: 'Missing Part'   }
];

export default class CaseCreate extends LightningElement {

    // ── Section collapse state ────────────────────────────────────────────────
    /** @type {boolean} */
    isAssetSectionOpen   = true;
    /** @type {boolean} */
    isProductSectionOpen = true;

    // ── Serial Number / Asset toggle ──────────────────────────────────────────
    /** @type {string} */
    serialNumber = '';
    /** @type {boolean} */
    serialNotApplicable = false;

    // ── Asset lookup state ────────────────────────────────────────────────────
    /** @type {string|null} Salesforce Id of the matched Asset */
    assetId = null;
    /** @type {boolean} Controls success message visibility */
    assetFound = false;

    // ── Row 1 — Equipment identity (disabled, populated from Asset) ───────────
    /** @type {string} */ brand       = '';
    /** @type {string} */ machineType = '';
    /** @type {string} */ series      = '';
    /** @type {string} */ modelNumber = '';

    // ── Row 2 — Usage info ────────────────────────────────────────────────────
    /** @type {string} */  unitOfMeasure  = '';
    /** @type {string} */  machineUsage   = '';
    /** @type {boolean} */ usageAvailable = false;  // drives Machine Usage disabled state
    /** @type {string} */  usedWith       = '';
    /** @type {string} */  engineSerial   = '';

    // ── Row 3 — Part information ──────────────────────────────────────────────
    /** @type {string|null} Id of the selected Part__c record */
    partNumberId    = null;
    /** @type {string} */
    partDescription = '';
    /** @type {string} */
    noPartReason    = '';

    // ── Post-save header state ────────────────────────────────────────────────
    /** @type {string|null} Id stored for subsequent upserts */
    caseId     = null;
    /** @type {string} */
    caseNumber = '';
    /** @type {string} */
    caseStatus = '';

    // ── UI feedback ───────────────────────────────────────────────────────────
    /** @type {string} */
    errorMessage = '';
    /** @type {boolean} */
    isSaving = false;

    // ── Static options ────────────────────────────────────────────────────────
    get noPartReasonOptions() {
        return NO_PART_REASON_OPTIONS;
    }

    // ── Computed getters ──────────────────────────────────────────────────────

    get isAssetSectionClosed() {
        return !this.isAssetSectionOpen;
    }

    get isProductSectionClosed() {
        return !this.isProductSectionOpen;
    }

    /** Displays 'New' until the case is first saved, then shows the draft status. */
    get statusDisplay() {
        return this.caseStatus ? this.caseStatus : 'New';
    }

    // ── Section collapse handlers ─────────────────────────────────────────────

    toggleAssetSection() {
        this.isAssetSectionOpen = !this.isAssetSectionOpen;
    }

    toggleProductSection() {
        this.isProductSectionOpen = !this.isProductSectionOpen;
    }

    // ── Serial Number handlers ────────────────────────────────────────────────

    /** Keeps the local serialNumber property in sync with the raw input value. */
    handleSerialInput(event) {
        this.serialNumber = event.target.value;
    }

    /**
     * Triggers the asset lookup when the user confirms with Enter or Tab.
     * @param {KeyboardEvent} event
     */
    handleSerialKeydown(event) {
        if (event.key === 'Enter' || event.key === 'Tab') {
            this._lookupAsset();
        }
    }

    /**
     * Triggers the asset lookup on blur when the field is not empty.
     * @param {FocusEvent} event
     */
    handleSerialBlur(event) {
        if (this.serialNumber) {
            this._lookupAsset();
        }
    }

    /** Static toggle — no wiring required in MP-7. */
    handleSerialNotApplicableToggle(event) {
        this.serialNotApplicable = event.target.checked;
    }

    /**
     * Client-side clear: resets all asset-populated fields and the success flag.
     * No Apex call needed.
     */
    handleClearSearch() {
        this.serialNumber   = '';
        this.assetId        = null;
        this.assetFound     = false;
        this.brand          = '';
        this.machineType    = '';
        this.series         = '';
        this.modelNumber    = '';
        this.unitOfMeasure  = '';
        this.machineUsage   = '';
        this.usageAvailable = false;
        this.engineSerial   = '';
        this.errorMessage   = '';
    }

    // ── Row 2 editable handlers ───────────────────────────────────────────────

    handleMachineUsageChange(event) {
        this.machineUsage = event.detail.value;
    }

    handleUsedWithChange(event) {
        this.usedWith = event.detail.value;
    }

    // ── Row 3 handlers ────────────────────────────────────────────────────────

    /**
     * Called when the Part Number record picker value changes.
     * Fetches Part Description imperatively; clears description when de-selected.
     * @param {CustomEvent} event
     */
    handlePartChange(event) {
        const selectedId = event.detail.recordId;
        this.partNumberId = selectedId ?? null;

        if (this.partNumberId) {
            getPartDescription({ partId: this.partNumberId })
                .then(description => {
                    this.partDescription = description ?? '';
                })
                .catch(error => {
                    this.partDescription = '';
                    this._setError(error);
                });
        } else {
            this.partDescription = '';
        }
    }

    handleNoPartReasonChange(event) {
        this.noPartReason = event.detail.value;
    }

    // ── Footer handlers ───────────────────────────────────────────────────────

    /**
     * Builds a Case sObject from the 11 Product Information fields (TDD §4.4)
     * and calls saveCaseAsDraft.  Engine Serial # is intentionally excluded.
     */
    handleSave() {
        this.errorMessage = '';
        this.isSaving     = true;

        const caseRecord = {
            ...(this.caseId ? { Id: this.caseId } : {}),
            AssetId:                  this.assetId        || undefined,
            Brand__c:                 this.brand          || undefined,
            Machine_Type__c:          this.machineType    || undefined,
            Series__c:                this.series         || undefined,
            Model_Number__c:          this.modelNumber    || undefined,
            Unit_of_Measure__c:       this.unitOfMeasure  || undefined,
            Machine_Usage__c:         this.machineUsage   || undefined,
            Part_Number__c:           this.partNumberId   || undefined,
            Part_Description__c:      this.partDescription || undefined,
            No_Causal_Part_Reason__c: this.noPartReason   || undefined,
            Used_With__c:             this.usedWith       || undefined
        };

        saveCaseAsDraft({ caseRecord })
            .then(result => {
                this.caseId     = result.caseId;
                this.caseNumber = result.caseNumber;
                this.caseStatus = result.status;
                this.isSaving   = false;
            })
            .catch(error => {
                this.isSaving = false;
                this._setError(error);
            });
    }

    /** Stub — to be implemented in MP-5. */
    handleSubmit() {
        // No-op in MP-7 scope
    }

    /** Stub — to be implemented in MP-5. */
    handleResolve() {
        // No-op in MP-7 scope
    }

    /**
     * Resets all reactive properties to their initial state.
     * Stays on page — no navigation.
     */
    handleCancel() {
        this.serialNumber        = '';
        this.serialNotApplicable = false;
        this.assetId             = null;
        this.assetFound          = false;
        this.brand               = '';
        this.machineType         = '';
        this.series              = '';
        this.modelNumber         = '';
        this.unitOfMeasure       = '';
        this.machineUsage        = '';
        this.usageAvailable      = false;
        this.usedWith            = '';
        this.engineSerial        = '';
        this.partNumberId        = null;
        this.partDescription     = '';
        this.noPartReason        = '';
        this.caseId              = null;
        this.caseNumber          = '';
        this.caseStatus          = '';
        this.errorMessage        = '';
        this.isSaving            = false;
    }

    // ── Stub action button handlers (header) ──────────────────────────────────

    handleAddFavorite() { /* stub */ }
    handleCopy()        { /* stub */ }
    handlePrint()       { /* stub */ }

    // ── Private helpers ───────────────────────────────────────────────────────

    /**
     * Calls findAssetBySerial imperatively.
     * Populates product info fields on success; shows an error on failure.
     */
    _lookupAsset() {
        const serial = (this.serialNumber ?? '').trim();
        if (!serial) {
            return;
        }

        this.errorMessage = '';

        findAssetBySerial({ serialNumber: serial })
            .then(info => {
                if (info) {
                    this.assetId        = info.assetId;
                    this.brand          = info.brand          ?? '';
                    this.machineType    = info.machineType    ?? '';
                    this.series         = info.series         ?? '';
                    this.modelNumber    = info.modelNumber    ?? '';
                    this.unitOfMeasure  = info.unitOfMeasure  ?? '';
                    this.machineUsage   = info.machineUsage   ?? '';
                    this.usageAvailable = info.usageAvailable ?? false;
                    this.engineSerial   = info.engineSerial   ?? '';
                    this.assetFound     = true;
                } else {
                    // Serial number not matched — clear fields
                    this._clearAssetFields();
                    this.assetFound = false;
                }
            })
            .catch(error => {
                this._clearAssetFields();
                this.assetFound = false;
                this._setError(error);
            });
    }

    /** Resets all asset-sourced fields without touching serial number or other user input. */
    _clearAssetFields() {
        this.assetId        = null;
        this.brand          = '';
        this.machineType    = '';
        this.series         = '';
        this.modelNumber    = '';
        this.unitOfMeasure  = '';
        this.machineUsage   = '';
        this.usageAvailable = false;
        this.engineSerial   = '';
    }

    /**
     * Extracts a human-readable message from an Apex or JS error and stores it.
     * @param {Error|{body:{message:string}}|{message:string}} error
     */
    _setError(error) {
        if (error?.body?.message) {
            this.errorMessage = error.body.message;
        } else if (error?.message) {
            this.errorMessage = error.message;
        } else {
            this.errorMessage = 'An unexpected error occurred. Please try again.';
        }
    }
}
