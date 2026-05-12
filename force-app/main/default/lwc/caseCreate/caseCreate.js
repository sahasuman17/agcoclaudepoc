import { LightningElement } from 'lwc';
import findAssetBySerial from '@salesforce/apex/CaseCreateController.findAssetBySerial';
import getPartDescription from '@salesforce/apex/CaseCreateController.getPartDescription';
import saveCaseAsDraft   from '@salesforce/apex/CaseCreateController.saveCaseAsDraft';

export default class CaseCreate extends LightningElement {

    // ── Asset lookup state ────────────────────────────────────────────────────
    assetId;
    assetFound  = false;
    serialNumber = '';

    // ── Row 1 — populated from asset lookup, always disabled ─────────────────
    brand       = '';
    machineType = '';
    series      = '';
    modelNumber = '';

    // ── Row 2 ─────────────────────────────────────────────────────────────────
    unitOfMeasure  = '';
    machineUsage   = '';   // Text 255 on Case — always a String
    usageAvailable = false;
    usedWith       = '';
    engineSerial   = '';

    // ── Row 3 ─────────────────────────────────────────────────────────────────
    partNumberId    = null;
    partDescription = '';
    noPartReason    = '';

    // ── Post-save state ───────────────────────────────────────────────────────
    caseId      = null;
    caseNumber  = '';
    savedStatus = '';

    // ── UI state ──────────────────────────────────────────────────────────────
    isLoading    = false;
    errorMessage = '';

    // ── Computed getters ──────────────────────────────────────────────────────

    /**
     * Machine Usage input is disabled when usage data is already available
     * from the asset (usageAvailable = true). Users may only enter it manually
     * when the asset has no recorded usage.
     */
    get machineUsageDisabled() {
        return this.usageAvailable;
    }

    /**
     * Options for the No Causal Part Reason combobox.
     */
    get noPartReasonOptions() {
        return [
            { label: 'No Fault Found', value: 'No Fault Found' },
            { label: 'Legacy Part',    value: 'Legacy Part'    },
            { label: 'Missing Part',   value: 'Missing Part'   }
        ];
    }

    // ── Handlers — Serial Number / Asset lookup ───────────────────────────────

    handleSerialNumberChange(event) {
        this.serialNumber = event.target.value;
    }

    handleSerialNumberKeyDown(event) {
        const key = event.key;
        if ((key === 'Enter' || key === 'Tab') && this.serialNumber) {
            this._lookupAsset();
        }
    }

    handleClearSearch() {
        this.assetId       = undefined;
        this.assetFound    = false;
        this.serialNumber  = '';
        this.brand         = '';
        this.machineType   = '';
        this.series        = '';
        this.modelNumber   = '';
        this.unitOfMeasure = '';
        this.machineUsage  = '';
        this.usageAvailable = false;
        this.engineSerial  = '';
        this.errorMessage  = '';
    }

    // ── Handlers — Row 2 ─────────────────────────────────────────────────────

    handleMachineUsageChange(event) {
        this.machineUsage = event.target.value;
    }

    handleUsedWithChange(event) {
        this.usedWith = event.target.value;
    }

    // ── Handlers — Row 3 ─────────────────────────────────────────────────────

    handlePartNumberChange(event) {
        const recordId = event.detail.recordId;
        this.partNumberId = recordId || null;

        if (recordId) {
            getPartDescription({ partId: recordId })
                .then(description => {
                    this.partDescription = description;
                })
                .catch(() => {
                    this.partDescription = '';
                });
        } else {
            this.partDescription = '';
        }
    }

    handleNoPartReasonChange(event) {
        this.noPartReason = event.detail.value;
    }

    // ── Handlers — Footer buttons ─────────────────────────────────────────────

    handleSave() {
        this.isLoading    = true;
        this.errorMessage = '';

        const caseRecord = {
            AssetId:                  this.assetId       || undefined,
            Brand__c:                 this.brand,
            Machine_Type__c:          this.machineType,
            Series__c:                this.series,
            Model_Number__c:          this.modelNumber,
            Unit_of_Measure__c:       this.unitOfMeasure,
            Machine_Usage__c:         this.machineUsage,
            Part_Number__c:           this.partNumberId  || undefined,
            Part_Description__c:      this.partDescription,
            No_Causal_Part_Reason__c: this.noPartReason,
            Used_With__c:             this.usedWith
        };

        // Include Id on the record for upsert when re-saving an existing draft
        if (this.caseId) {
            caseRecord.Id = this.caseId;
        }

        saveCaseAsDraft({ caseRecord })
            .then(result => {
                this.caseId     = result.caseId;
                this.caseNumber = result.caseNumber;
                this.savedStatus = result.status;
                this.isLoading  = false;
            })
            .catch(error => {
                this.errorMessage = error?.body?.message ?? 'An error occurred while saving.';
                this.isLoading    = false;
            });
    }

    // Stub handlers — wired to actions in future stories (MP-8, MP-9, MP-10)
    handleSubmit() {}
    handleResolve() {}
    handleCancel()  {}

    // ── Private helpers ───────────────────────────────────────────────────────

    _lookupAsset() {
        this.isLoading    = true;
        this.errorMessage = '';

        findAssetBySerial({ serialNumber: this.serialNumber })
            .then(wrapper => {
                this.assetId        = wrapper.assetId;
                this.brand          = wrapper.brand          ?? '';
                this.machineType    = wrapper.machineType    ?? '';
                this.series         = wrapper.series         ?? '';
                this.modelNumber    = wrapper.modelNumber    ?? '';
                this.unitOfMeasure  = wrapper.unitOfMeasure  ?? '';
                this.machineUsage   = wrapper.machineUsage   ?? '';
                this.usageAvailable = wrapper.usageAvailable ?? false;
                this.engineSerial   = wrapper.engineSerial   ?? '';
                this.assetFound     = true;
                this.isLoading      = false;
            })
            .catch(error => {
                this.errorMessage = error?.body?.message ?? 'Asset not found.';
                this.assetFound   = false;
                this.isLoading    = false;
            });
    }
}
