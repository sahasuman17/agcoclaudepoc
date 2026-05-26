/**
 * @description Controller for the caseCreate LWC component.
 *              Handles asset lookup, part description retrieval, and case draft persistence
 *              for the "Parts Technical Help" case type (MP-7 scope).
 * @author      Suman Saha
 * @story       MP-7
 * @apiVersion  65.0
 */
public with sharing class CaseCreateController {

    // ─────────────────────────────────────────────────────────────────────────
    // Inner Classes
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Wrapper returned by findAssetBySerial.
     *              Contains all Product Information fields sourced from the Asset record.
     */
    public class AssetWrapper {
        @AuraEnabled public Id      assetId;        // Asset.Id  → Case.AssetId
        @AuraEnabled public String  brand;          // Model_Name__r.Brand_Name__r.Name
        @AuraEnabled public String  machineType;    // Machine_Type__c (formula)
        @AuraEnabled public String  series;         // Series__c (formula)
        @AuraEnabled public String  modelNumber;    // Model_Name__r.Name
        @AuraEnabled public String  unitOfMeasure;  // Unit_of_Measure__c
        @AuraEnabled public String  machineUsage;   // String.valueOf(Usage__c) or null
        @AuraEnabled public Boolean usageAvailable; // Usage__c != null
        @AuraEnabled public String  engineSerial;   // Engine_Serial_Number__c (UI display only)
    }

    /**
     * @description Wrapper returned by saveCaseAsDraft.
     *              Contains the persisted Case identifiers for header display and subsequent upserts.
     */
    public class SaveResult {
        @AuraEnabled public Id     caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String status;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Methods
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Searches for an Asset by its SerialNumber and returns product information fields.
     *              Called imperatively when the user confirms a Serial Number (Enter / Tab / blur).
     * @param  serialNumber  The value typed in the Asset/Serial Number input field.
     * @return               AssetWrapper with all product info fields, or null if no match.
     */
    @AuraEnabled(cacheable=false)
    public static AssetWrapper findAssetBySerial(String serialNumber) {
        try {
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

            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.READABLE, assets
            );
            List<Asset> safeAssets = (List<Asset>) decision.getRecords();

            if (safeAssets.isEmpty()) {
                return null;
            }

            Asset asset = safeAssets[0];

            AssetWrapper info    = new AssetWrapper();
            info.assetId         = asset.Id;
            info.brand           = asset.Model_Name__r?.Brand_Name__r?.Name;
            info.machineType     = asset.Machine_Type__c;
            info.series          = asset.Series__c;
            info.modelNumber     = asset.Model_Name__r?.Name;
            info.unitOfMeasure   = asset.Unit_of_Measure__c;
            info.machineUsage    = asset.Usage__c != null
                                   ? String.valueOf(asset.Usage__c.intValue()) : null;
            info.usageAvailable  = asset.Usage__c != null;
            info.engineSerial    = asset.Engine_Serial_Number__c;

            return info;

        } catch (Exception e) {
            throw new AuraHandledException(
                'Error retrieving asset: ' + e.getMessage()
            );
        }
    }

    /**
     * @description Returns the Part_Description__c for a given Part__c record Id.
     *              Called imperatively when the Part Number lookup selection changes.
     * @param  partId  The Id of the selected Part__c record.
     * @return         Part_Description__c value, or null if not found.
     */
    @AuraEnabled(cacheable=true)
    public static String getPartDescription(Id partId) {
        try {
            List<Part__c> parts = [
                SELECT Id, Part_Description__c
                FROM   Part__c
                WHERE  Id = :partId
                LIMIT  1
            ];

            SObjectAccessDecision partDecision = Security.stripInaccessible(
                AccessType.READABLE, parts
            );
            List<Part__c> safeParts = (List<Part__c>) partDecision.getRecords();

            return safeParts.isEmpty() ? null : safeParts[0].Part_Description__c;

        } catch (Exception e) {
            throw new AuraHandledException(
                'Error retrieving part description: ' + e.getMessage()
            );
        }
    }

    /**
     * @description Upserts a Case record with Status = 'Draft' and the Parts_Technical RecordType.
     *              The LWC passes only the 11 Product Information fields (MP-7 scope).
     *              Returns the Case Id, CaseNumber, and Status for header display.
     * @param  caseRecord  Case sObject constructed by the LWC with Product Information fields only.
     * @return             SaveResult containing caseId, caseNumber, and status.
     */
    @AuraEnabled(cacheable=false)
    public static SaveResult saveCaseAsDraft(Case caseRecord) {
        try {
            // Resolve the Parts_Technical RecordType Id — zero SOQL governor limit
            Id partsTechRtId = Schema.SObjectType.Case
                .getRecordTypeInfosByDeveloperName()
                .get('Parts_Technical').getRecordTypeId();
            caseRecord.RecordTypeId = partsTechRtId;

            caseRecord.Status = 'Draft';

            upsert caseRecord;

            Case saved = [
                SELECT CaseNumber
                FROM   Case
                WHERE  Id = :caseRecord.Id
                LIMIT  1
            ];

            SaveResult result  = new SaveResult();
            result.caseId      = caseRecord.Id;
            result.caseNumber  = saved.CaseNumber;
            result.status      = 'Draft';

            return result;

        } catch (Exception e) {
            throw new AuraHandledException(
                'Error saving case: ' + e.getMessage()
            );
        }
    }
}
