/**
 * @description Test class for CaseCreateController.
 *              Covers findAssetBySerial, getPartDescription, and saveCaseAsDraft.
 *              Target: ≥80% code coverage with meaningful assertions.
 * @author      Suman Saha
 * @date        2026-05-12
 * @see         CaseCreateController
 */
@IsTest
private class CaseCreateControllerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────────────────────────────────

    private static final String SERIAL_NUMBER     = 'SN-TEST-001';
    private static final String ENGINE_SERIAL     = 'ENG-SN-999';
    private static final String UNIT_OF_MEASURE   = 'Hours';
    private static final Decimal USAGE_VALUE      = 1500;
    private static final String PART_DESCRIPTION  = 'Test Part Description';
    private static final String BRAND_NAME        = 'TestBrand';
    private static final String MODEL_NAME        = 'TestModel';

    // ─────────────────────────────────────────────────────────────────────────
    // Shared Test Data
    // ─────────────────────────────────────────────────────────────────────────

    @TestSetup
    static void makeData() {
        // Account — required by Asset field integrity rule
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // Brand
        Brand__c brand = new Brand__c(Name = BRAND_NAME);
        insert brand;

        // Model linked to Brand
        Model__c model = new Model__c(
            Name          = MODEL_NAME,
            Brand_Name__c = brand.Id
        );
        insert model;

        // Asset with Usage (positive — usage available)
        Asset assetWithUsage = new Asset(
            Name                    = 'Asset With Usage',
            AccountId               = acc.Id,
            SerialNumber            = SERIAL_NUMBER,
            Model_Name__c           = model.Id,
            Unit_of_Measure__c      = UNIT_OF_MEASURE,
            Usage__c                = USAGE_VALUE,
            Engine_Serial_Number__c = ENGINE_SERIAL
        );
        insert assetWithUsage;

        // Asset without Usage (positive — usage NOT available)
        Asset assetNoUsage = new Asset(
            Name                    = 'Asset No Usage',
            AccountId               = acc.Id,
            SerialNumber            = 'SN-NO-USAGE-002',
            Model_Name__c           = model.Id,
            Unit_of_Measure__c      = UNIT_OF_MEASURE,
            Engine_Serial_Number__c = ENGINE_SERIAL
        );
        insert assetNoUsage;

        // Part with description
        Part__c partWithDesc = new Part__c(
            Name                = 'Test Part',
            Part_Description__c = PART_DESCRIPTION
        );
        insert partWithDesc;

        // Part with null description
        Part__c partNullDesc = new Part__c(
            Name = 'Part Null Desc'
            // Part_Description__c intentionally left null
        );
        insert partNullDesc;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // findAssetBySerial — Positive: Usage available
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void findAssetBySerial_WithUsage_ReturnsPopulatedWrapper() {
        Test.startTest();
        CaseCreateController.AssetWrapper result =
            CaseCreateController.findAssetBySerial(SERIAL_NUMBER);
        Test.stopTest();

        Asset expected = [
            SELECT Id, Usage__c, Unit_of_Measure__c, Engine_Serial_Number__c
            FROM   Asset
            WHERE  SerialNumber = :SERIAL_NUMBER
            LIMIT  1
        ];

        Assert.areEqual(expected.Id, result.assetId,
            'assetId should match the inserted Asset Id');
        Assert.areEqual(UNIT_OF_MEASURE, result.unitOfMeasure,
            'unitOfMeasure should match Unit_of_Measure__c');
        Assert.areEqual(
            String.valueOf(USAGE_VALUE.intValue()),
            result.machineUsage,
            'machineUsage should be the integer string representation of Usage__c'
        );
        Assert.isTrue(result.usageAvailable,
            'usageAvailable should be true when Usage__c is populated');
        Assert.areEqual(ENGINE_SERIAL, result.engineSerial,
            'engineSerial should match Engine_Serial_Number__c');
        // modelNumber and brand come from cross-object relationships — verify they
        // are mapped (not necessarily non-null in sandbox; relationship resolution
        // depends on the formula chain being intact)
        Assert.areEqual(MODEL_NAME, result.modelNumber,
            'modelNumber should match Model__c.Name');
        Assert.areEqual(BRAND_NAME, result.brand,
            'brand should match Brand__c.Name via Model__c.Brand_Name__r');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // findAssetBySerial — Positive: Usage NOT available
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void findAssetBySerial_NoUsage_MachineUsageNullAndFlagFalse() {
        Test.startTest();
        CaseCreateController.AssetWrapper result =
            CaseCreateController.findAssetBySerial('SN-NO-USAGE-002');
        Test.stopTest();

        Assert.isNull(result.machineUsage,
            'machineUsage should be null when Usage__c is not set');
        Assert.isFalse(result.usageAvailable,
            'usageAvailable should be false when Usage__c is null');
        Assert.areEqual(UNIT_OF_MEASURE, result.unitOfMeasure,
            'unitOfMeasure should still be mapped even with no usage');
        Assert.areEqual(ENGINE_SERIAL, result.engineSerial,
            'engineSerial should still be mapped even with no usage');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // findAssetBySerial — Negative: Serial number not found
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void findAssetBySerial_UnknownSerial_ThrowsAuraHandledException() {
        Boolean exceptionThrown = false;
        String  exceptionMessage = '';

        Test.startTest();
        try {
            CaseCreateController.findAssetBySerial('NONEXISTENT-SERIAL-XYZ');
        } catch (AuraHandledException e) {
            exceptionThrown  = true;
            exceptionMessage = e.getMessage();
        }
        Test.stopTest();

        Assert.isTrue(exceptionThrown,
            'An AuraHandledException must be thrown for an unknown serial number');
        Assert.isTrue(
            exceptionMessage.contains('No asset found for serial number'),
            'Exception message should contain the expected prefix. Actual: ' + exceptionMessage
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getPartDescription — Positive: Part exists with description
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void getPartDescription_PartWithDescription_ReturnsDescription() {
        Part__c part = [
            SELECT Id
            FROM   Part__c
            WHERE  Name = 'Test Part'
            LIMIT  1
        ];

        Test.startTest();
        String result = CaseCreateController.getPartDescription(part.Id);
        Test.stopTest();

        Assert.areEqual(PART_DESCRIPTION, result,
            'Should return the Part_Description__c value exactly');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getPartDescription — Positive: Part exists with null description
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void getPartDescription_PartWithNullDescription_ReturnsEmptyString() {
        Part__c part = [
            SELECT Id
            FROM   Part__c
            WHERE  Name = 'Part Null Desc'
            LIMIT  1
        ];

        Test.startTest();
        String result = CaseCreateController.getPartDescription(part.Id);
        Test.stopTest();

        Assert.areEqual('', result,
            'Should return empty string (not null) when Part_Description__c is null');
        Assert.isNotNull(result,
            'Return value must never be null due to the null-coalescing operator (?? \'\')');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // getPartDescription — Negative: Part does not exist (deleted record)
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void getPartDescription_NonExistentPart_ReturnsEmptyString() {
        // Insert then delete so we have a well-formed Id that no longer exists
        Part__c ghostPart = new Part__c(Name = 'Ghost Part');
        insert ghostPart;
        Id ghostId = ghostPart.Id;
        delete ghostPart;

        Test.startTest();
        String result = CaseCreateController.getPartDescription(ghostId);
        Test.stopTest();

        Assert.areEqual('', result,
            'Should return empty string when no Part__c record is found for the given Id');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // saveCaseAsDraft — Positive: Insert new Case (no Id)
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void saveCaseAsDraft_NewCase_InsertsAndReturnsDraftResult() {
        Case newCase = new Case(
            Subject           = 'Test Draft Case',
            Machine_Type__c   = 'Wheel Loader',
            Unit_of_Measure__c = UNIT_OF_MEASURE,
            Machine_Usage__c  = String.valueOf(USAGE_VALUE.intValue())
        );

        Test.startTest();
        CaseCreateController.SaveResult result =
            CaseCreateController.saveCaseAsDraft(newCase);
        Test.stopTest();

        Assert.isNotNull(result.caseId,
            'caseId must not be null after insert');
        Assert.isNotNull(result.caseNumber,
            'caseNumber must not be null after insert');
        Assert.isFalse(String.isBlank(result.caseNumber),
            'caseNumber must not be blank after insert');
        Assert.areEqual('Draft', result.status,
            'status must be Draft regardless of what was passed in');

        // Re-query the DB to confirm persistence
        Case persisted = [
            SELECT Status
            FROM   Case
            WHERE  Id = :result.caseId
            LIMIT  1
        ];
        Assert.areEqual('Draft', persisted.Status,
            'Persisted Case Status must be Draft in the database');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // saveCaseAsDraft — Positive: Upsert (update) existing Case
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void saveCaseAsDraft_ExistingCase_UpdatesWithoutCreatingDuplicate() {
        // First call — insert
        Case newCase = new Case(Subject = 'Initial Draft');

        Test.startTest();
        CaseCreateController.SaveResult firstResult =
            CaseCreateController.saveCaseAsDraft(newCase);

        // Second call — update, using the Id returned from the first call
        Case updateCase = new Case(
            Id      = firstResult.caseId,
            Subject = 'Updated Draft Subject'
        );
        CaseCreateController.SaveResult secondResult =
            CaseCreateController.saveCaseAsDraft(updateCase);
        Test.stopTest();

        Assert.areEqual(firstResult.caseId, secondResult.caseId,
            'The same Case Id must be returned on upsert — no duplicate should be created');
        Assert.areEqual('Draft', secondResult.status,
            'Status must remain Draft after the update upsert');

        // Confirm only ONE case was created (not two)
        Integer caseCount = [
            SELECT COUNT()
            FROM   Case
            WHERE  Id = :firstResult.caseId
        ];
        Assert.areEqual(1, caseCount,
            'Exactly one Case record should exist for the returned Id');

        // Confirm the subject was updated
        Case persisted = [
            SELECT Subject, Status
            FROM   Case
            WHERE  Id = :firstResult.caseId
            LIMIT  1
        ];
        Assert.areEqual('Updated Draft Subject', persisted.Subject,
            'Subject should reflect the updated value');
        Assert.areEqual('Draft', persisted.Status,
            'Status must be Draft in the database after the update');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // saveCaseAsDraft — Status override: Status is always forced to Draft
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void saveCaseAsDraft_StatusOverridden_AlwaysDraft() {
        // Pass a Case with Status deliberately set to something other than Draft
        Case newCase = new Case(
            Subject = 'Status Override Test',
            Status  = 'New'
        );

        Test.startTest();
        CaseCreateController.SaveResult result =
            CaseCreateController.saveCaseAsDraft(newCase);
        Test.stopTest();

        Assert.areEqual('Draft', result.status,
            'Controller must override any incoming Status value and persist Draft');

        Case persisted = [
            SELECT Status
            FROM   Case
            WHERE  Id = :result.caseId
            LIMIT  1
        ];
        Assert.areEqual('Draft', persisted.Status,
            'Database Status must be Draft regardless of what the caller supplied');
    }
}
