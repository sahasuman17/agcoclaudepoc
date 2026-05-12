/**
 * @description Apex controller for the caseCreate LWC. Provides asset lookup,
 *              part description retrieval, and case draft save functionality.
 * @author      Suman Saha
 * @date        2026-05-12
 */
public with sharing class CaseCreateController {

    // ─────────────────────────────────────────────────────────────────────────
    // Inner Classes
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Wrapper exposing Asset fields needed by the Product Information section.
     */
    public class AssetWrapper {
        @AuraEnabled public Id     assetId;
        @AuraEnabled public String brand;
        @AuraEnabled public String machineType;
        @AuraEnabled public String series;
        @AuraEnabled public String modelNumber;
        @AuraEnabled public String unitOfMeasure;
        @AuraEnabled public String machineUsage;      // intValue() as String, or null
        @AuraEnabled public Boolean usageAvailable;   // true when Usage__c is populated
        @AuraEnabled public String engineSerial;
    }

    /**
     * @description Wrapper returned after a successful case upsert.
     */
    public class SaveResult {
        @AuraEnabled public Id     caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String status;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Public Methods
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Finds an Asset by its serial number and returns a populated AssetWrapper.
     *              Throws AuraHandledException when no matching asset is found.
     * @param  serialNumber The serial number to look up.
     * @return AssetWrapper populated with product information fields.
     */
    @AuraEnabled(cacheable=true)
    public static AssetWrapper findAssetBySerial(String serialNumber) {
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
            throw new AuraHandledException(
                'No asset found for serial number: ' + serialNumber
            );
        }

        Asset asset = assets[0];

        AssetWrapper info = new AssetWrapper();
        info.assetId        = asset.Id;
        info.brand          = asset.Model_Name__r?.Brand_Name__r?.Name;
        info.machineType    = asset.Machine_Type__c;
        info.series         = asset.Series__c;
        info.modelNumber    = asset.Model_Name__r?.Name;
        info.unitOfMeasure  = asset.Unit_of_Measure__c;
        info.machineUsage   = asset.Usage__c != null
                                ? String.valueOf(asset.Usage__c.intValue())
                                : null;
        info.usageAvailable = asset.Usage__c != null;
        info.engineSerial   = asset.Engine_Serial_Number__c;

        return info;
    }

    /**
     * @description Retrieves the Part_Description__c value for a given Part__c record.
     * @param  partId The Id of the Part__c record.
     * @return The Part_Description__c value, or an empty string when the part is not found.
     */
    @AuraEnabled(cacheable=true)
    public static String getPartDescription(Id partId) {
        List<Part__c> parts = [
            SELECT Part_Description__c
            FROM   Part__c
            WHERE  Id = :partId
            LIMIT  1
        ];

        if (parts.isEmpty()) {
            return '';
        }

        return parts[0].Part_Description__c ?? '';
    }

    /**
     * @description Upserts the supplied Case record with Status = 'Draft' and returns
     *              a SaveResult containing the case Id, number, and status.
     * @param  caseRecord The Case sObject to upsert (Id field optional for insert).
     * @return SaveResult with caseId, caseNumber, and status.
     */
    @AuraEnabled
    public static SaveResult saveCaseAsDraft(Case caseRecord) {
        try {
            caseRecord.Status = 'Draft';
            upsert caseRecord;

            Case saved = [
                SELECT CaseNumber, Status
                FROM   Case
                WHERE  Id = :caseRecord.Id
                LIMIT  1
            ];

            SaveResult result = new SaveResult();
            result.caseId     = caseRecord.Id;
            result.caseNumber = saved.CaseNumber;
            result.status     = saved.Status;

            return result;

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
