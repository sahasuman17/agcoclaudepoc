# Design Requirements — MP-7: Support Cases — Product Information Section

| Field          | Value                                          |
|----------------|------------------------------------------------|
| Jira Key       | MP-7                                           |
| Title          | Support Cases: Product Information Section     |
| Case Type      | Parts Technical Help                           |
| Status         | In Progress                                    |
| Authoritative Design Source | `TDD/MP-7-Product-Information-Section.md` |
| Mockup         | `agent-output/jira-cache/MP-7/attachments/MP-7 Mockup.png` |
| API Version    | 65.0                                           |
| Package Dir    | `force-app/main/default`                       |

> The TDD (`TDD/MP-7-Product-Information-Section.md`) is the authoritative design solution and supersedes any Jira-attached document. This requirements file restates the TDD in admin/developer-actionable form for the specialist agents.

---

## 1. Story Summary

When a user creates a "Parts Technical Help" support case and enters a Serial Number, the **Product Information** section auto-populates equipment fields from the related Asset record. Some fields render as disabled text inputs (sourced from Asset), some are conditionally editable, and some are fully manual. On **Save**, only the Product Information fields are persisted to the Case, the Case is set to `Status = 'Draft'`, and the returned **CaseNumber** is displayed in the page header under the "Parts Technical Help" record type label.

**Scope:** Product Information section only. Asset/Serial Number Information shell, Case Information, Dealer, Comments, etc. are out of scope (handled by other stories — e.g. MP-5).

---

## 2. Acceptance Criteria (from Jira)

| AC | Description |
|----|-------------|
| AC-1 | **Engine Serial # — Pre-Population** — Auto-populates from the Asset record when a valid Asset/Serial Number is entered. Remains blank but editable if no Engine Serial Number exists. |
| AC-2 | **Engine Serial # — Editable Text Field** — Editable at all times. (See Section 9 — Open Question 1 — TDD conflict.) |
| AC-3 | **Part Number & No Part Reason — Both Optional** — User can save without providing values. |
| AC-4 | **Part Number — Lookup Search Across All Parts** — Search triggered across all `Part__c` records on user interaction. |
| AC-5 | **Part Description — Auto-Populated, Read-Only** — Auto-populates when a Part Number is selected; read-only. |
| AC-6 | **Part Number — Retained if Not Found** — User-typed Part Number remains visible if no system match. |
| AC-7 | **Mandatory Fields — Asterisk (\*)** — Brand, Machine Type, Series, Model Number, Asset/Serial Number are required. |
| AC-8 | **Save as Draft** — On Save with mandatory fields filled, Case is saved with `Status = 'Draft'`, all Product Information field values are persisted, confirmation displayed (Case Number shown in header). |

---

## 3. Admin Work Required

**Admin specialist: nothing to do — all metadata already exists.**

A full inventory of pre-existing metadata is in Section 6 (Data Model). Inventory verified against `force-app/main/default/`:

- Case standard fields and all required custom fields exist (see Section 6.1 — full list with paths).
- Asset has all required fields including `Machine_Type__c` (formula `TEXT(Product2.Type__c)`) and `Series__c` (formula `Product2.Series__c`).
- Custom objects `Brand__c`, `Model__c`, `Part__c` exist with required fields.
- Case RecordType `Parts_Technical` exists at `force-app/main/default/objects/Case/recordTypes/Parts_Technical.recordType-meta.xml`.
- `Case.No_Causal_Part_Reason__c` picklist values verified: `No Fault Found`, `Legacy Part`, `Missing Part`.

**Conclusion:** Skip the admin agent. Proceed directly to the developer agent.

---

## 4. Developer Work Required

### 4.1 Files to Create

| File | Action | Purpose |
|------|--------|---------|
| `force-app/main/default/classes/CaseCreateController.cls` | **Create** | Apex controller with `findAssetBySerial`, `getPartDescription`, `saveCaseAsDraft` |
| `force-app/main/default/classes/CaseCreateController.cls-meta.xml` | **Create** | Apex metadata, API 65.0, `status = Active` |
| `force-app/main/default/lwc/caseCreate/caseCreate.js` | **Create** | LWC controller with reactive properties + imperative calls |
| `force-app/main/default/lwc/caseCreate/caseCreate.html` | **Create** | UI markup per mockup |
| `force-app/main/default/lwc/caseCreate/caseCreate.css` | **Create** | Custom styling for success message + disabled-input look |
| `force-app/main/default/lwc/caseCreate/caseCreate.js-meta.xml` | **Create** | LWC metadata, `isExposed = true`, target `lightning__AppPage` (and any other targets needed by the consuming Lightning page) |

> Note: All six files were deleted in the current working tree (per git status). The developer agent recreates them from scratch following the TDD specifications below.

### 4.2 Apex Controller — `CaseCreateController`

**Class signature:** `public with sharing class CaseCreateController`

#### 4.2.1 Method: `findAssetBySerial(String serialNumber)` — `@AuraEnabled(cacheable=false)`

Called when the user enters a Serial Number and confirms with Enter/Tab.

**SOQL (exact — from TDD §6.2):**
```sql
SELECT Id,
       Engine_Serial_Number__c,
       Machine_Type__c,
       Series__c,
       Model_Name__c,
       Model_Name__r.Name,
       Model_Name__r.Brand_Name__r.Name,
       Unit_of_Measure__c,
       Usage__c
FROM Asset
WHERE SerialNumber = :serialNumber
LIMIT 1
```

**Return type:** `AssetWrapper` (inner class)
```java
public class AssetWrapper {
    @AuraEnabled public Id assetId;
    @AuraEnabled public String brand;
    @AuraEnabled public String machineType;
    @AuraEnabled public String series;
    @AuraEnabled public String modelNumber;
    @AuraEnabled public String unitOfMeasure;
    @AuraEnabled public String machineUsage;
    @AuraEnabled public Boolean usageAvailable;
    @AuraEnabled public String engineSerial;
}
```

**Mapping logic (from TDD §6.2):**
```java
AssetWrapper info  = new AssetWrapper();
info.assetId       = asset.Id;
info.brand         = asset.Model_Name__r?.Brand_Name__r?.Name;
info.machineType   = asset.Machine_Type__c;
info.series        = asset.Series__c;
info.modelNumber   = asset.Model_Name__r?.Name;
info.unitOfMeasure = asset.Unit_of_Measure__c;
info.machineUsage  = asset.Usage__c != null
                     ? String.valueOf(asset.Usage__c.intValue()) : null;
info.usageAvailable = asset.Usage__c != null;
info.engineSerial   = asset.Engine_Serial_Number__c;
```

**Behavior:** Return `null` (or empty wrapper) when no Asset matches — the LWC handles the "not found" UI state.

#### 4.2.2 Method: `getPartDescription(Id partId)` — `@AuraEnabled(cacheable=true)`

```sql
SELECT Id, Part_Description__c
FROM Part__c
WHERE Id = :partId
LIMIT 1
```

**Return type:** `String` (the `Part_Description__c` value, or null).

#### 4.2.3 Method: `saveCaseAsDraft(Case caseRecord)` — `@AuraEnabled(cacheable=false)`

The LWC passes a Case sObject containing only the 11 Product Information fields (see Section 5.1). The controller sets `Status = 'Draft'`, upserts, then re-queries the Case to return the CaseNumber.

**Return type:** `SaveResult` (inner class)
```java
public class SaveResult {
    @AuraEnabled public Id caseId;
    @AuraEnabled public String caseNumber;
    @AuraEnabled public String status;   // "Draft"
}
```

**Implementation (from TDD §6.4):**
```java
@AuraEnabled
public static SaveResult saveCaseAsDraft(Case caseRecord) {
    caseRecord.Status = 'Draft';
    upsert caseRecord;
    Case saved = [SELECT CaseNumber, Status FROM Case
                  WHERE Id = :caseRecord.Id LIMIT 1];
    SaveResult result = new SaveResult();
    result.caseId     = caseRecord.Id;
    result.caseNumber = saved.CaseNumber;
    result.status     = saved.Status;
    return result;
}
```

**Error handling:** Wrap DML in try/catch and rethrow as `AuraHandledException` with a user-friendly message.

#### 4.2.4 Out of Scope for MP-7

`submitCase(Id caseId)` is reserved for MP-5 — do **not** implement it here.

---

### 4.3 LWC — `caseCreate`

#### 4.3.1 Reactive Properties (from TDD §7.3)

```javascript
@track caseId;
@track caseNumber = '';
@track status = '';

// Serial / Asset
@track serialNumber = '';
@track assetId;
@track assetFound = false;
@track assetNotApplicable = false;   // tied to the "Asset/Serial Number Not Applicable" toggle

// Row 1 — disabled-after-lookup
@track brand = '';
@track machineType = '';
@track series = '';
@track modelNumber = '';

// Row 2
@track unitOfMeasure = '';
@track machineUsage = '';
@track usageAvailable = false;
@track usedWith = '';
@track engineSerial = '';

// Row 3
@track partNumberId;
@track partDescription = '';
@track noPartReason = '';
```

#### 4.3.2 Imperative Calls / Triggers (from TDD §7.4)

| Trigger | Apex Method | Action on Response |
|---------|-------------|---------------------|
| Serial Number confirmed (Enter / Tab / blur with non-empty value) | `findAssetBySerial` | Populate Row 1 + Row 2 fields, set `assetFound = true`. If no record, set `assetFound = false` and surface a user-facing message. |
| Clear Search link click | (client-side only) | Clear all product info fields, reset `assetFound = false`, `assetId = null`. |
| Part Number record-picker change | `getPartDescription` | Populate `partDescription`, or clear if the Part is removed. |
| Save button click | `saveCaseAsDraft` | Build Case sObject from the 11 Product Information fields only (Section 5.1), display returned `caseNumber` in header. |

> **No Submit / Resolve / Cancel logic in MP-7.** Render the buttons (per mockup) but leave the click handlers as no-ops or stubs that surface an "Available in a future story" toast. Confirm this with the user if uncertain — see Open Question 2.

#### 4.3.3 UI State Matrix (from TDD §7.5)

| State | Row 1 fields | UoM | Machine Usage | Engine Serial # | Part Description |
|-------|--------------|-----|---------------|------------------|------------------|
| No Asset selected | Empty (disabled) | Empty (disabled) | Editable | Empty (disabled) | Empty (disabled) |
| Asset found, `Usage__c` available | Disabled (filled) | Disabled (filled) | Disabled (filled) | Disabled (filled) | Empty (disabled) |
| Asset found, `Usage__c` NOT available | Disabled (filled) | Disabled (filled) | **Editable** | Disabled (filled) | Empty (disabled) |
| Part Number selected | (unchanged) | (unchanged) | (unchanged) | (unchanged) | Disabled (filled) |

---

## 5. LWC UI Specification (from mockup)

The mockup at `agent-output/jira-cache/MP-7/attachments/MP-7 Mockup.png` is the source of truth for the layout and look-and-feel. Build exactly what is shown.

### 5.1 Page Layout (per mockup)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ (dark top bar)          Create a Support Case                               │
├─────────────────────────────────────────────────────────────────────────────┤
│ Parts Technical Help                  ★ Add Favorite   Copy   Print to PDF │
│ 1247008                                              * = Required Information│
│ Status                                                                       │
│ New                                                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│ ▼ Asset /Serial Number Information                                          │
│   [⚪Toggle] Asset/Serial Number Not Applicable                              │
│   ASSET/SERIAL NUMBER *  [____________]   Clear Search                      │
│   ✅ VIN/Serial Number found. Product information has been added below.    │
├─────────────────────────────────────────────────────────────────────────────┤
│ ▼ Product Information                                                       │
│   Row 1: BRAND *      MACHINE TYPE *     SERIES *      MODEL NUMBER *      │
│          [Fendt]      [Tractor]          [series]      [FV2984720]         │
│                                                                             │
│   Row 2: UNIT OF MEAS. MACHINE USAGE     USED WITH     ENGINE SERIAL #     │
│          [Engine Hours][               ] [           ] [Fserial]            │
│                                                                             │
│   Row 3: PART NUMBER  PART DESCRIPTION   NO PART REASON                    │
│          [🔍 Search]  [               ]  [Select       ▼]                  │
├─────────────────────────────────────────────────────────────────────────────┤
│       [ Save ]   [ Submit ]   [ Resolve ]   [ Cancel ]                     │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.2 Header Block

- "Create a Support Case" — top dark bar (page title).
- "Parts Technical Help" — record type label (h1 / h2 styling).
- Beneath: the placeholder `1247008` shown in the mockup is the **Case Number**. Display it only **after** `saveCaseAsDraft` returns. Before save, render nothing (or a "—" placeholder).
- "Status / New" — initial render shows "New" (or empty). After successful save, show "Draft" (from `SaveResult.status`).
- Right side: `Add Favorite`, `Copy`, `Print to PDF` action buttons (UI only — no logic in MP-7; treat as styling stubs).
- `* = Required Information` legend at top-right.

### 5.3 Asset / Serial Number Information Section (UI shell only — out of scope for behavior)

> Per TDD §1 and §2, only the Product Information section is wired in MP-7. The Asset/Serial Number Information block is rendered as a UI shell so the page matches the mockup.

- Collapsible section heading: "Asset /Serial Number Information" with caret.
- Toggle: "Asset/Serial Number Not Applicable" — render with `lightning-input type="toggle"`. Bound to `assetNotApplicable`; no business logic in MP-7 beyond visual state.
- "ASSET/SERIAL NUMBER *" — text input. **This is the field that triggers `findAssetBySerial` on Enter/Tab** (the only piece of behavior in this section).
- "Clear Search" link (red) — client-side clearing of Product Information fields + serial.
- Success message: green check + italic green text `"VIN/Serial Number found. Product information has been added below."` — displayed only when `assetFound === true`.

### 5.4 Product Information Section

- Section heading: "Product Information" with caret.
- **4-column responsive grid** (use `slds-grid` + `slds-size_1-of-4` on `slds-large-screen`, fall back to 2-of-4 / 1-of-1 on smaller screens).
- All asset-populated fields render as `lightning-input type="text"` with `disabled` attribute (NOT `readonly`). This preserves the input border per TDD §2 — mockup confirms boxed look.
- All labels uppercase per mockup (e.g., `BRAND`, `MACHINE TYPE`); SLDS form-element default already does this with proper class — verify visually.

| Row | Field Label | Input | Required | Source | Render |
|-----|-------------|-------|----------|--------|--------|
| 1 | BRAND * | `lightning-input` | Yes | `brand` | Disabled text input |
| 1 | MACHINE TYPE * | `lightning-input` | Yes | `machineType` | Disabled text input |
| 1 | SERIES * | `lightning-input` | Yes | `series` | Disabled text input |
| 1 | MODEL NUMBER * | `lightning-input` | Yes | `modelNumber` | Disabled text input |
| 2 | UNIT OF MEASURE | `lightning-input` | No | `unitOfMeasure` | Disabled text input |
| 2 | MACHINE USAGE | `lightning-input` | No | `machineUsage` | Disabled IF `usageAvailable === true`, editable otherwise |
| 2 | USED WITH | `lightning-input` | No | `usedWith` | Always editable |
| 2 | ENGINE SERIAL # | `lightning-input` | No | `engineSerial` | Disabled text input (see Open Question 1) |
| 3 | PART NUMBER | `lightning-record-picker` `object-api-name="Part__c"` | No | `partNumberId` | Search-enabled |
| 3 | PART DESCRIPTION | `lightning-input` | No | `partDescription` | Disabled text input |
| 3 | NO PART REASON | `lightning-combobox` | No | `noPartReason` | Picklist values from `Case.No_Causal_Part_Reason__c` (3 values — see Open Question 4) |

### 5.5 Footer Buttons

Per mockup: four buttons centered at the bottom — Save (red filled — `slds-button_brand`), Submit, Resolve, Cancel (all `slds-button_neutral`).

- **Save** — wires `saveCaseAsDraft`.
- **Submit** — UI stub (MP-5 will wire). Disabled or shows "Coming soon" toast.
- **Resolve** — UI stub. Same treatment.
- **Cancel** — client-side: clear form / navigate away. Confirm desired behavior — see Open Question 3.

### 5.6 Field Mapping — Save Payload (the 11 Product Information fields only)

This is the exact payload the LWC builds on Save (from TDD §4.4 / §8):

```javascript
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
```

> **Important — Engine Serial # is NOT saved to Case in MP-7** per TDD §4.1 / §4.4. It is displayed on the UI only. (This conflicts with AC-1/AC-2 wording — see Open Question 1.)

> **RecordTypeId not in payload** — per the TDD save snippet, only the 11 fields above are sent. If the consuming Lightning page or org setup requires `RecordTypeId = Parts_Technical`, the controller may need to look it up on save. Confirm — see Open Question 5.

---

## 6. Data Model — Object Relationships (Reference)

### 6.1 Pre-Existing Metadata (verified in `force-app/main/default/`)

**Case custom fields used in MP-7:**
- `Brand__c` — Text(255)
- `Machine_Type__c` — Text(255)
- `Series__c` — Text(255)
- `Model_Number__c` — Text(255)
- `Unit_of_Measure__c` — Text(255)
- `Machine_Usage__c` — Text(255)
- `Used_With__c` — Text
- `Part_Number__c` — Lookup(`Part__c`)
- `Part_Description__c` — Text(255)
- `No_Causal_Part_Reason__c` — Picklist (`No Fault Found`, `Legacy Part`, `Missing Part`)
- `Engine_Serial_Number__c` — Text (present on Case but NOT in MP-7 save payload — see Open Question 1)

**Asset fields used:**
- `SerialNumber` (standard) — WHERE-clause key
- `Model_Name__c` — Lookup(`Model__c`)
- `Machine_Type__c` — formula `TEXT(Product2.Type__c)`
- `Series__c` — formula `Product2.Series__c`
- `Unit_of_Measure__c` — Picklist (queried as text)
- `Usage__c` — Number(18,0)
- `Engine_Serial_Number__c` — Text

**Other objects:**
- `Model__c` with `Name` and `Brand_Name__c` (Lookup to `Brand__c`)
- `Brand__c` with `Name`
- `Part__c` with `Name` and `Part_Description__c`

**Record Type:** `Case.Parts_Technical` (`force-app/main/default/objects/Case/recordTypes/Parts_Technical.recordType-meta.xml`)

### 6.2 Relationship Diagram

```
Case
 ├── AssetId (standard Lookup → Asset)
 │    ├── Model_Name__c (Lookup → Model__c)
 │    │    ├── Name                                → Case.Model_Number__c
 │    │    └── Brand_Name__c (Lookup → Brand__c)
 │    │         └── Name                           → Case.Brand__c
 │    ├── Machine_Type__c (formula)                → Case.Machine_Type__c
 │    ├── Series__c (formula)                      → Case.Series__c
 │    ├── Unit_of_Measure__c (Picklist)            → Case.Unit_of_Measure__c
 │    ├── Usage__c (Number)                        → Case.Machine_Usage__c
 │    └── Engine_Serial_Number__c (Text)           → UI display only (NOT saved)
 │
 └── Part_Number__c (Lookup → Part__c)
      ├── Name (labeled "Part Number")
      └── Part_Description__c                      → Case.Part_Description__c
```

---

## 7. Acceptance Criteria → Implementation Mapping

| AC | TDD Section | Implementation Note |
|----|-------------|---------------------|
| AC-1 | §4.1 (#8), §5.2 | `findAssetBySerial` returns `engineSerial`; LWC sets `this.engineSerial` |
| AC-2 | §5.2 | **TDD makes Engine Serial # disabled, Jira AC says editable.** Open Question 1. |
| AC-3 | §5.3 | No `required` attribute on Part Number or No Part Reason |
| AC-4 | §7 (Part Row) | `lightning-record-picker object-api-name="Part__c"` |
| AC-5 | §4.2 / §5.3 | `getPartDescription` populates `partDescription` (disabled) |
| AC-6 | §5.3 | `lightning-record-picker` retains free-text input on no match |
| AC-7 | §5.1, §5.2 | `required` flag on Brand, Machine Type, Series, Model Number, Asset/Serial Number |
| AC-8 | §6.4, §8 | `saveCaseAsDraft` sets `Status = 'Draft'`, upserts, returns `caseNumber` shown in header |

---

## 8. Test Class Specification (if confirmed at Gate 1)

`force-app/main/default/classes/CaseCreateControllerTest.cls`

**Required coverage scenarios:**
1. `findAssetBySerial_validSerial_returnsWrapper` — set up Brand/Model/Product2/Asset; assert wrapper fields populate.
2. `findAssetBySerial_noMatch_returnsNull` — call with nonexistent serial; assert null/empty.
3. `findAssetBySerial_usageNull_setsUsageAvailableFalse` — Asset with `Usage__c = null`; assert `usageAvailable == false`.
4. `findAssetBySerial_usagePresent_setsUsageAvailableTrue` — Asset with `Usage__c = 1234`; assert `usageAvailable == true` and `machineUsage == '1234'`.
5. `getPartDescription_validId_returnsDescription` — create Part, assert description returned.
6. `getPartDescription_invalidId_returnsNull` — query non-matching Id.
7. `saveCaseAsDraft_insert_setsDraftStatus` — assert `Status == 'Draft'` and `caseNumber` returned.
8. `saveCaseAsDraft_update_setsDraftStatus` — pass existing `caseRecord.Id`; assert upsert path works.

**Targets:** > 85% line coverage on `CaseCreateController` (project standard).

---

## 9. Open Questions / Assumptions

> The Design Agent does NOT auto-resolve these. The main agent should surface them in the Gate 1 prompt OR the developer can default to the TDD answer (TDD is authoritative).

1. **Engine Serial # — editable vs disabled.** Jira AC-1/AC-2 state Engine Serial # is "editable text field … allowing users to type or override values" and **save** is implied. The TDD (§4.1, §5.2, §4.4) states Engine Serial # is rendered **disabled** and is **NOT** saved to Case (UI display only). The TDD is authoritative per project rules — defaulting to **disabled & not-saved**. **Confirm with user if Jira behavior is required instead.**
2. **Submit / Resolve buttons.** TDD does not wire these in MP-7. Default: render per mockup as visible but non-functional (e.g., disabled or "Coming soon" toast). Confirm whether Submit must at least save-then-display a toast.
3. **Cancel button.** No TDD spec. Default: clear all reactive properties and remain on the page (no navigation). Confirm if it should navigate away.
4. **No Part Reason picklist source.** Defaulting to the 3 hard-coded TDD values (`No Fault Found`, `Legacy Part`, `Missing Part`) which match the `Case.No_Causal_Part_Reason__c` field metadata. Confirm whether to fetch via `getPicklistValues` (recommended for future-proofing) or hardcode.
5. **RecordTypeId on Save.** TDD's save payload (§8) omits `RecordTypeId`. If the org has multiple Case record types and "Parts Technical" must be enforced, the controller should set `caseRecord.RecordTypeId = <Parts_Technical Id>` before upsert. **Defaulting to: controller resolves the `Parts_Technical` RecordTypeId by `DeveloperName` and assigns it on save.** Confirm this addition.
6. **Serial Number trigger event.** TDD §7.2 says Enter/Tab. Implementing both `onkeyup` (Enter key → `event.key === 'Enter'`) AND `onblur` (Tab/click-away). Confirm this is acceptable.
7. **Part Number not-found behavior (AC-6).** `lightning-record-picker` natively supports search across an object but does NOT retain free-typed values when no match is selected. To meet AC-6 strictly we would need a custom typeahead. **Defaulting to: use `lightning-record-picker` and document this limitation.** Confirm whether a custom lookup is required.

---

## 10. Routing Recommendation (for Main Agent)

| Agent | Action |
|-------|--------|
| salesforce-admin | **Skip** — no admin work needed (all metadata pre-exists; verified). |
| salesforce-developer | **Run** — create Apex controller + LWC per Sections 4 & 5. Reference: `TDD/MP-7-Product-Information-Section.md`. |
| salesforce-developer (test class) | Run **if user confirms at Gate 1**. Spec in Section 8. |
| salesforce-code-review | Run **if user confirms at Gate 1**. |
| salesforce-devops | Run **at Gate 2 / Gate 3** as confirmed. |

---

## 11. Reference Files

| File | Purpose |
|------|---------|
| `TDD/MP-7-Product-Information-Section.md` | **Authoritative design solution** — developer must follow exactly |
| `agent-output/jira-cache/MP-7/issue.json` | Cached Jira issue |
| `agent-output/jira-cache/MP-7/attachments/MP-7 Mockup.png` | Authoritative UI mockup |
| `force-app/main/default/objects/Case/fields/*.field-meta.xml` | Pre-existing Case field metadata |
| `force-app/main/default/objects/Asset/fields/*.field-meta.xml` | Pre-existing Asset field metadata (incl. formula fields) |
| `force-app/main/default/objects/Case/recordTypes/Parts_Technical.recordType-meta.xml` | Required RecordType |
