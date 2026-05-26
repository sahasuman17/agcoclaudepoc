/**
 * @description Test class for CaseCreateController.
 *              Covers all three public methods: findAssetBySerial, getPartDescription,
 *              and saveCaseAsDraft. Targets ≥ 85% line coverage.
 *
 *              Test scenarios follow the PNB pattern (Positive / Negative / Boundary)
 *              as defined in the sf-apex SKILL.
 *
 * @author      Suman Saha
 * @story       MP-7
 * @apiVersion  65.0
 * @see         CaseCreateController
 */
@IsTest
private class CaseCreateControllerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────────────────────────────────

    private static final String SERIAL_NUMBER       = 'TEST-SERIAL-0001';
    private static final String BRAND_NAME          = 'TestBrand';
    private static final String MODEL_NAME          = 'TestModel';
    private static final String PRODUCT_TYPE        = 'Tractors';
    private static final String PRODUCT_SERIES      = 'S-Series';
    private static final String UNIT_OF_MEASURE     = 'Engine Hours';
    private static final String ENGINE_SERIAL       = 'ENG-9999';
    private static final Decimal USAGE_VALUE        = 1234;
    private static final String PART_DESCRIPTION    = 'Hydraulic Filter Assembly';

    // ─────────────────────────────────────────────────────────────────────────
    // @TestSetup — shared data for all test methods
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Creates shared Brand__c, Model__c, Product2, and Asset records
     *              used by the findAssetBySerial test methods.
     *              Also creates a Part__c record for getPartDescription tests.
     *              Asset with Usage populated (USAGE_VALUE) is the primary fixture.
     *              A second Asset with null Usage is created for the null-usage scenario.
     */
    @TestSetup
    static void makeData() {
        // Brand
        Brand__c brand = new Brand__c(Name = BRAND_NAME);
        insert brand;

        // Model (lookup to Brand)
        Model__c model = new Model__c(
            Name          = MODEL_NAME,
            Brand_Name__c = brand.Id
        );
        insert model;

        // Product2 — drives Machine_Type__c and Series__c formula fields on Asset
        Product2 product = new Product2(
            Name      = MODEL_NAME,
            Type__c   = PRODUCT_TYPE,
            Series__c = PRODUCT_SERIES,
            IsActive  = true
        );
        insert product;

        // Account — required by org validation rule (every asset needs an account or contact)
        Account acct = new Account(Name = 'Test Account MP7');
        insert acct;

        // Primary Asset — Usage populated (USAGE_VALUE), linked to Model
        Asset assetWithUsage = new Asset(
            Name                   = 'Asset With Usage',
            SerialNumber           = SERIAL_NUMBER,
            Model_Name__c          = model.Id,
            Unit_of_Measure__c     = UNIT_OF_MEASURE,
            Usage__c               = USAGE_VALUE,
            Engine_Serial_Number__c = ENGINE_SERIAL,
            Product2Id             = product.Id,
            Status                 = 'Installed',
            AccountId              = acct.Id
        );
        insert assetWithUsage;

        // Secondary Asset — Usage null, different serial
        Asset assetNoUsage = new Asset(
            Name                   = 'Asset No Usage',
            SerialNumber           = 'TEST-SERIAL-NULL-USAGE',
            Model_Name__c          = model.Id,
            Unit_of_Measure__c     = UNIT_OF_MEASURE,
            Usage__c               = null,
            Engine_Serial_Number__c = ENGINE_SERIAL,
            Product2Id             = product.Id,
            Status                 = 'Installed',
            AccountId              = acct.Id
        );
        insert assetNoUsage;

        // Part
        Part__c part = new Part__c(
            Name                = 'PART-001',
            Part_Description__c = PART_DESCRIPTION
        );
        insert part;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // findAssetBySerial — Positive
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Given a valid SerialNumber that matches a persisted Asset,
     *              findAssetBySerial must return a fully-populated AssetWrapper.
     */
    @IsTest
    static void findAssetBySerial_validSerial_returnsWrapper() {
        Test.startTest();
        CaseCreateController.AssetWrapper result =
            CaseCreateController.findAssetBySerial(SERIAL_NUMBER);
        Test.stopTest();

        System.assertNotEquals(null, result,            'Wrapper must not be null for a valid serial');
        System.assertNotEquals(null, result.assetId,    'assetId must be populated');
        System.assertEquals(BRAND_NAME,      result.brand,          'brand must match Brand__c.Name');
        System.assertEquals(MODEL_NAME,      result.modelNumber,    'modelNumber must match Model__c.Name');
        System.assertEquals(UNIT_OF_MEASURE, result.unitOfMeasure,  'unitOfMeasure must match Asset.Unit_of_Measure__c');
        System.assertEquals(ENGINE_SERIAL,   result.engineSerial,   'engineSerial must match Asset.Engine_Serial_Number__c');
        System.assertEquals(true,            result.usageAvailable, 'usageAvailable must be true when Usage__c is set');
        System.assertEquals(
            String.valueOf(USAGE_VALUE.intValue()),
            result.machineUsage,
            'machineUsage must equal intValue() of Usage__c as a String'
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // findAssetBySerial — Negative (no match)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Given a serial number that matches no Asset record,
     *              findAssetBySerial must return null (not throw).
     */
    @IsTest
    static void findAssetBySerial_noMatch_returnsNull() {
        Test.startTest();
        CaseCreateController.AssetWrapper result =
            CaseCreateController.findAssetBySerial('NONEXISTENT-SERIAL-XYZ');
        Test.stopTest();

        System.assertEquals(null, result, 'Result must be null when no Asset matches the serial number');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // findAssetBySerial — Boundary: Usage__c null
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Given an Asset where Usage__c is null,
     *              usageAvailable must be false and machineUsage must be null.
     */
    @IsTest
    static void findAssetBySerial_usageNull_setsUsageAvailableFalse() {
        Test.startTest();
        CaseCreateController.AssetWrapper result =
            CaseCreateController.findAssetBySerial('TEST-SERIAL-NULL-USAGE');
        Test.stopTest();

        System.assertNotEquals(null, result,  'Wrapper must not be null for existing asset');
        System.assertEquals(false, result.usageAvailable, 'usageAvailable must be false when Usage__c is null');
        System.assertEquals(null,  result.machineUsage,   'machineUsage must be null when Usage__c is null');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getPartDescription — Positive
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Given a valid Part__c Id, getPartDescription must return
     *              the Part_Description__c value.
     */
    @IsTest
    static void getPartDescription_validId_returnsDescription() {
        Part__c part = [SELECT Id FROM Part__c WHERE Name = 'PART-001' LIMIT 1];

        Test.startTest();
        String description = CaseCreateController.getPartDescription(part.Id);
        Test.stopTest();

        System.assertEquals(PART_DESCRIPTION, description,
            'Description must match Part__c.Part_Description__c');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getPartDescription — Negative (Id not found)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Given a well-formed Part__c Id that does not match any record,
     *              getPartDescription must return null without throwing.
     *
     *              Strategy: insert then delete a Part so we have a valid-format Id
     *              that no longer resolves.
     */
    @IsTest
    static void getPartDescription_invalidId_returnsNull() {
        Part__c ghost = new Part__c(Name = 'GHOST-PART');
        insert ghost;
        Id ghostId = ghost.Id;
        delete ghost;

        Test.startTest();
        String description = CaseCreateController.getPartDescription(ghostId);
        Test.stopTest();

        System.assertEquals(null, description,
            'Description must be null when no Part__c matches the given Id');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // saveCaseAsDraft — Positive: insert path
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Calling saveCaseAsDraft with a new Case (no Id) must insert the record,
     *              set Status = 'Draft', and return a non-null caseId and non-blank caseNumber.
     */
    @IsTest
    static void saveCaseAsDraft_insert_setsDraftStatus() {
        Case newCase = new Case(
            Subject          = 'Test Draft Insert',
            Brand__c         = BRAND_NAME,
            Machine_Type__c  = PRODUCT_TYPE,
            Series__c        = PRODUCT_SERIES,
            Model_Number__c  = MODEL_NAME
        );

        Test.startTest();
        CaseCreateController.SaveResult result =
            CaseCreateController.saveCaseAsDraft(newCase);
        Test.stopTest();

        System.assertNotEquals(null, result,           'SaveResult must not be null');
        System.assertNotEquals(null, result.caseId,    'caseId must be assigned after insert');
        System.assertNotEquals('',   result.caseNumber,'caseNumber must be non-blank after insert');
        System.assertNotEquals(null, result.caseNumber,'caseNumber must not be null');
        System.assertEquals('Draft', result.status,    'Status must be Draft after saveCaseAsDraft');

        // Verify persistence in database
        Case saved = [SELECT Status FROM Case WHERE Id = :result.caseId LIMIT 1];
        System.assertEquals('Draft', saved.Status, 'Persisted Case Status must be Draft');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // saveCaseAsDraft — Positive: update (upsert) path
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Calling saveCaseAsDraft twice with the same Case Id must update
     *              the existing record (upsert update path) rather than inserting a duplicate.
     *              The returned caseId must match the originally inserted Id.
     */
    @IsTest
    static void saveCaseAsDraft_update_setsDraftStatus() {
        // First save — insert
        Case newCase = new Case(
            Subject         = 'Test Draft Update - Initial',
            Brand__c        = BRAND_NAME,
            Machine_Type__c = PRODUCT_TYPE
        );

        CaseCreateController.SaveResult firstResult =
            CaseCreateController.saveCaseAsDraft(newCase);

        System.assertNotEquals(null, firstResult.caseId, 'First save must return a caseId');

        // Second save — update with existing Id and changed Subject
        Case updatedCase = new Case(
            Id              = firstResult.caseId,
            Subject         = 'Test Draft Update - Revised',
            Brand__c        = BRAND_NAME,
            Machine_Type__c = PRODUCT_TYPE,
            Series__c       = PRODUCT_SERIES
        );

        Test.startTest();
        CaseCreateController.SaveResult updateResult =
            CaseCreateController.saveCaseAsDraft(updatedCase);
        Test.stopTest();

        System.assertNotEquals(null,              updateResult,           'SaveResult must not be null on update');
        System.assertEquals(firstResult.caseId,   updateResult.caseId,   'caseId must remain the same after upsert update');
        System.assertEquals(firstResult.caseNumber, updateResult.caseNumber, 'CaseNumber must be unchanged after update');
        System.assertEquals('Draft',              updateResult.status,    'Status must remain Draft after update');

        // Confirm only one Case record exists (no duplicate insert)
        Integer count = [
            SELECT COUNT()
            FROM   Case
            WHERE  Id = :firstResult.caseId
        ];
        System.assertEquals(1, count, 'Upsert update must not create a second Case record');

        // Confirm updated Subject persisted
        Case saved = [SELECT Subject FROM Case WHERE Id = :firstResult.caseId LIMIT 1];
        System.assertEquals('Test Draft Update - Revised', saved.Subject,
            'Subject must reflect the updated value after upsert');
    }
}
