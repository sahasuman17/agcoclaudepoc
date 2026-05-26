/**
 * @description Controller for the caseCreate LWC component.
 *              Handles asset serial-number lookup, part description retrieval,
 *              and case draft persistence for the Product Information section (MP-7).
 *              Additional methods for Case Information and other sections will be
 *              added in future stories (MP-5, etc.).
 *
 * @author      Suman Saha
 * @story       MP-7 — Support Cases: Product Information Section
 * @apiVersion  66.0
 */
public with sharing class CaseCreateController {

    // ─── Inner Classes ────────────────────────────────────────────────────────

    /**
     * @description Wrapper returned by findAssetBySerial.
     *              All fields are @AuraEnabled so the LWC can bind to them directly.
     */
    public class AssetWrapper {
        @AuraEnabled public Id      assetId;          // Asset.Id → Case.AssetId
        @AuraEnabled public String  brand;            // Model_Name__r.Brand_Name__r.Name
        @AuraEnabled public String  machineType;      // Asset.Machine_Type__c (formula)
        @AuraEnabled public String  series;           // Asset.Series__c (formula)
        @AuraEnabled public String  modelNumber;      // Asset.Model_Name__r.Name
        @AuraEnabled public String  unitOfMeasure;    // Asset.Unit_of_Measure__c
        @AuraEnabled public String  machineUsage;     // String representation of Asset.Usage__c
        @AuraEnabled public Boolean usageAvailable;   // true when Usage__c is not null
        @AuraEnabled public String  engineSerial;     // Asset.Engine_Serial_Number__c (UI display only)
    }

    /**
     * @description Wrapper returned by saveCaseAsDraft.
     *              Carries back the persisted Case Id, Case Number, and Status
     *              so the LWC can update the page header.
     */
    public class SaveResult {
        @AuraEnabled public Id     caseId;      // Case.Id — stored for subsequent upserts
        @AuraEnabled public String caseNumber;  // Case.CaseNumber — displayed in page header
        @AuraEnabled public String status;      // Case.Status — 'Draft' on first save
    }

    // ─── Public Methods ───────────────────────────────────────────────────────

    /**
     * @description Looks up an Asset by its SerialNumber field and returns a
     *              populated AssetWrapper.  Returns null when no match is found.
     *              Cacheable so repeated lookups do not count against the DML
     *              governor and can leverage client-side caching.
     *
     * @param  serialNumber  The serial number entered by the user.
     * @return               AssetWrapper with product information, or null.
     */
    @AuraEnabled(cacheable=true)
    public static AssetWrapper findAssetBySerial(String serialNumber) {
        if (String.isBlank(serialNumber)) {
            return null;
        }

        List<Asset> assets = [
            SELECT Id,
                   Engine_Serial_Number__c,
                   Machine_Type__c,
                   Series__c,
                   Model_Name__c,
                   Model_Name__r.Name,
                   Model_Name__r.Brand_Name__r.Name,
                   Unit_of_Measure__c,
                   Usage__c
            FROM   Asset
            WHERE  SerialNumber = :serialNumber
            LIMIT  1
        ];

        if (assets.isEmpty()) {
            return null;
        }

        Asset asset       = assets[0];
        AssetWrapper info = new AssetWrapper();

        info.assetId        = asset.Id;
        info.brand          = asset.Model_Name__r?.Brand_Name__r?.Name;
        info.machineType    = asset.Machine_Type__c;
        info.series         = asset.Series__c;
        info.modelNumber    = asset.Model_Name__r?.Name;
        info.unitOfMeasure  = asset.Unit_of_Measure__c;
        info.machineUsage   = asset.Usage__c != null
                              ? String.valueOf(asset.Usage__c.intValue()) : null;
        info.usageAvailable = asset.Usage__c != null;
        info.engineSerial   = asset.Engine_Serial_Number__c;

        return info;
    }

    /**
     * @description Returns the Part_Description__c value for a given Part__c record.
     *              Returns null (empty string in LWC) when the Part is not found.
     *              Cacheable to minimise server round-trips on repeated selections.
     *
     * @param  partId  The Salesforce Id of the selected Part__c record.
     * @return         Part_Description__c text, or null.
     */
    @AuraEnabled(cacheable=true)
    public static String getPartDescription(Id partId) {
        if (partId == null) {
            return null;
        }

        List<Part__c> parts = [
            SELECT Id, Part_Description__c
            FROM   Part__c
            WHERE  Id = :partId
            LIMIT  1
        ];

        return parts.isEmpty() ? null : parts[0].Part_Description__c;
    }

    /**
     * @description Upserts a Case sObject as a Draft.
     *              The LWC passes only the 11 Product Information fields (TDD §4.4).
     *              This method sets Status = 'Draft', resolves the RecordTypeId from
     *              DeveloperName so no Id is hardcoded, then upserts the record.
     *              Returns a SaveResult with caseId, caseNumber and status for
     *              display in the LWC page header.
     *
     * @param  caseRecord  Case sObject built by the LWC with Product Info fields only.
     * @return             SaveResult containing caseId, caseNumber, and status.
     */
    @AuraEnabled
    public static SaveResult saveCaseAsDraft(Case caseRecord) {
        try {
            // Resolve RecordTypeId by DeveloperName — never hardcode the Id
            if (caseRecord.RecordTypeId == null) {
                List<RecordType> rtList = [
                    SELECT Id
                    FROM   RecordType
                    WHERE  SObjectType = 'Case'
                    AND    DeveloperName = 'Parts_Technical'
                    LIMIT  1
                ];
                if (!rtList.isEmpty()) {
                    caseRecord.RecordTypeId = rtList[0].Id;
                }
            }

            caseRecord.Status = 'Draft';
            upsert caseRecord;

            Case saved = [
                SELECT CaseNumber, Status
                FROM   Case
                WHERE  Id = :caseRecord.Id
                LIMIT  1
            ];

            SaveResult result    = new SaveResult();
            result.caseId        = caseRecord.Id;
            result.caseNumber    = saved.CaseNumber;
            result.status        = saved.Status;

            return result;

        } catch (DmlException dmlEx) {
            throw new AuraHandledException(
                'Save failed: ' + dmlEx.getDmlMessage(0)
            );
        } catch (Exception ex) {
            throw new AuraHandledException(
                'An unexpected error occurred: ' + ex.getMessage()
            );
        }
    }
}
