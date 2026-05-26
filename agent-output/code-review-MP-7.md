# Code Review — MP-7: Support Cases — Product Information Section

| Field          | Value                                      |
|----------------|--------------------------------------------|
| Jira Key       | MP-7                                       |
| Reviewer       | salesforce-code-review agent               |
| Date           | 2026-05-26                                 |
| API Version    | 65.0                                       |
| Files Reviewed | 5                                          |

---

## Overall Verdict: WARNINGS

All Critical security and governor-limit requirements are met. Several Major and Minor issues require attention — primarily around FLS enforcement, a hard-coded picklist in LWC, a deprecated template directive, a duplicated test method, and accessibility gaps. None of the issues are show-stoppers for deployment, but the Major items should be addressed before the next story builds on this code.

---

## Summary Table

| Severity | Count | Files Affected |
|----------|-------|----------------|
| Critical | 0     | —              |
| Major    | 4     | Controller, LWC JS, LWC HTML, Test |
| Minor    | 6     | Controller, LWC JS, LWC HTML, CSS |
| Info     | 4     | Controller, LWC JS, LWC HTML |

---

## File-by-File Findings

---

### 1. `CaseCreateController.cls`

#### MAJOR-1 — No FLS / CRUD enforcement on Asset and Part__c queries
**Severity:** Major
**Lines:** 54–67 (`findAssetBySerial`), 105–112 (`getPartDescription`)

**Issue:** The class is declared `with sharing` (correct for record-level access), but neither method enforces Field-Level Security on the fields being read from `Asset` and `Part__c`. A running user without FLS access to, for example, `Usage__c`, `Engine_Serial_Number__c`, or `Part_Description__c` will still receive those field values because `with sharing` only enforces record visibility, not field-level access.

**Recommended Fix:** Use `Security.stripInaccessible(AccessType.READABLE, records)` after the query in both methods, or annotate with `@AuraEnabled(cacheable=false)` and add explicit FLS checks via `Schema.sObjectType.Asset.fields.Usage__c.isAccessible()`. The `stripInaccessible` approach is the modern Salesforce-preferred pattern:

```java
SObjectAccessDecision decision = Security.stripInaccessible(
    AccessType.READABLE, assets
);
Asset asset = (Asset) decision.getRecords()[0];
```

**Why it matters:** Without FLS enforcement, the component leaks field data to users who should not see it, violating Salesforce security review requirements and the principle of least privilege.

---

#### MAJOR-2 — `saveCaseAsDraft` performs two SOQL queries inside a single transaction with no necessity for the second query
**Severity:** Major (Governor Limit / Design)
**Lines:** 148–153

**Issue:** After `upsert caseRecord`, the method issues a second SOQL query to re-fetch `CaseNumber` and `Status`. While this is currently safe (1 SOQL hit, well within limits), the pattern is fragile: if this method is ever called in a loop or from a future trigger context the extra query will count twice per record. More critically, `Status` was just set programmatically to `'Draft'` on line 144 — it does not need to be re-queried. `CaseNumber` is the only value that genuinely requires a re-query, since it is system-assigned on insert.

**Recommended Fix:** Remove `Status` from the re-query. Assign it directly from the known value:

```java
result.status = 'Draft';  // known — just set it above
```
Keep the `CaseNumber` re-query or, for tighter bulkification, consider returning `caseRecord.Id` and using a separate cacheable wire for display-only fields in the LWC.

---

#### Minor-1 — `saveCaseAsDraft`: RecordType SOQL query runs every call
**Severity:** Minor
**Lines:** 132–138

**Issue:** The RecordType lookup (`SELECT Id FROM RecordType WHERE SObjectType = 'Case' AND DeveloperName = 'Parts_Technical'`) fires on every call to `saveCaseAsDraft`. RecordType Ids are org-constant and never change at runtime.

**Recommended Fix:** Cache the result in a static variable or use `Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('Parts_Technical').getRecordTypeId()` which is zero-SOQL and returns the same value without a query.

```java
Id rtId = Schema.SObjectType.Case
    .getRecordTypeInfosByDeveloperName()
    .get('Parts_Technical')
    .getRecordTypeId();
```

---

#### Minor-2 — Generic exception message leaks internal details
**Severity:** Minor
**Lines:** 90–93, 115–118, 163–166

**Issue:** All three catch blocks rethrow with `e.getMessage()` appended to a user-facing label (e.g., `'Error retrieving asset: ' + e.getMessage()`). In production this can expose internal SOQL error messages, field names, or DML constraint details to end users.

**Recommended Fix:** Log the full exception internally (e.g., via a Platform Event or custom log object) and present only a generic user message from the `AuraHandledException`:

```java
// Log e internally if a logging framework exists
throw new AuraHandledException('Error retrieving asset. Please contact your administrator.');
```

---

#### Info-1 — `findAssetBySerial` accepts a raw `String` with no null/blank guard
**Severity:** Info
**Lines:** 52

**Issue:** If the LWC sends a `null` or blank string (e.g., user blurs an empty field), the SOQL `WHERE SerialNumber = :serialNumber` will execute with a null bind, returning no rows (safe), but it wastes a SOQL call.

**Recommendation:** Add an early-exit guard:

```java
if (String.isBlank(serialNumber)) { return null; }
```

---

### 2. `CaseCreateControllerTest.cls`

#### MAJOR-3 — Duplicate test method: `findAssetBySerial_usagePresent_setsUsageAvailableTrue` is redundant
**Severity:** Major
**Lines:** 176–190 vs 109–127

**Issue:** Test method `findAssetBySerial_usagePresent_setsUsageAvailableTrue` (line 176) asserts exactly the same conditions as `findAssetBySerial_validSerial_returnsWrapper` (line 109) — both use `SERIAL_NUMBER`, both assert `usageAvailable == true` and `machineUsage` string value. This is dead test code that inflates apparent coverage without adding any new assertion paths. It also misleads future developers about what scenarios are actually being tested.

**Recommended Fix:** Remove the duplicate method. If the intent was to isolate the usage-flag assertion into its own test, remove the usage-related assertions from `findAssetBySerial_validSerial_returnsWrapper` instead and keep only `findAssetBySerial_usagePresent_setsUsageAvailableTrue`. One or the other, not both.

---

#### Minor-3 — No negative test for `saveCaseAsDraft` error path
**Severity:** Minor

**Issue:** There is no test that exercises the `catch` block in `saveCaseAsDraft` (lines 162–166 of the controller). The happy-path and upsert-update paths are covered, but a failing DML (e.g., a required field not provided triggering a DmlException) is not tested.

**Recommended Fix:** Add a test that passes a Case with an intentionally invalid state (e.g., missing a validation-rule–required field if any exist, or mocking a DML failure via Test.setCreatedDate tricks) and asserts that an `AuraHandledException` is thrown.

---

#### Minor-4 — `getPartDescription_invalidId_returnsNull` uses insert-then-delete; may fail if hard-delete is disabled
**Severity:** Minor
**Lines:** 225–228

**Issue:** The test inserts a `Part__c` record, captures its Id, then deletes it to obtain a "valid-format but non-existent" Id. If the org has Recycle Bin disabled or the running user lacks delete permission, this will fail. Additionally, deleted records are still accessible via SOQL `ALL ROWS`, so in a rare edge case this could return the record instead of null if `getPartDescription` used `ALL ROWS`.

**Recommended Fix:** Use a fabricated 18-character Id of the correct prefix instead:

```java
Id fakeId = Part__c.SObjectType.newSObject().Id; // will be null — generate manually
// Or construct a fake Id string matching Part__c prefix and verify it against schema
```
A simpler approach: query a valid Part Id, add `'000'` to shift the suffix, making it syntactically valid but non-matching. Confirm the Part__c key prefix from org schema.

---

#### Info-2 — `@TestSetup` creates `Asset` with `AccountId = null`; may conflict with org validation rules
**Severity:** Info
**Lines:** 74

**Issue:** `AccountId = null` is explicitly set on the Asset. Some orgs enforce a validation rule requiring Asset.AccountId or Asset.ContactId. If such a rule exists, `makeData()` will fail silently (the test will error, not fail, making diagnosis harder).

**Recommendation:** Document this assumption or wrap the Asset insert in a try-catch with a clear `System.assert(false, ...)` message if it fails, so the root cause is immediately obvious.

---

### 3. `caseCreate.js`

#### MAJOR-4 — Picklist options for `No Part Reason` are hard-coded in JS
**Severity:** Major
**Lines:** 16–21

**Issue:** `NO_PART_REASON_OPTIONS` is a hard-coded constant. The TDD Open Question 4 (design-requirements.md §9, item 4) explicitly flags this as requiring confirmation — the project recommendation was to use `getPicklistValues` wire adapter for future-proofing. Picklist values on `Case.No_Causal_Part_Reason__c` could be updated in the org without a code deploy, but the hard-coded LWC will silently serve stale values to users.

**Recommended Fix:** Use the `@salesforce/ui-api/record-ui` approach with `getPicklistValues` to retrieve live picklist values from the org schema:

```javascript
import { getPicklistValues } from 'lightning/uiObjectInfoApi';
import NO_CAUSAL_PART_REASON_FIELD from '@salesforce/schema/Case.No_Causal_Part_Reason__c';
```

At minimum, document this limitation prominently in a code comment so the next developer knows values must be manually synced if the field picklist changes.

---

#### Minor-5 — Overuse of `@track` — unnecessary for primitive values in modern LWC
**Severity:** Minor
**Lines:** 30–60

**Issue:** In the current LWC engine (API v40+), `@track` is only required for object/array mutations. All primitive-typed properties (`String`, `Boolean`, `Number`) are reactive by default without `@track`. Decorating every property with `@track` is legacy practice carried over from pre-Spring '20 LWC, and adds noise that misleads future maintainers.

**Recommended Fix:** Remove `@track` from all primitive properties. Keep `@track` only on object or array properties where deep mutation tracking is needed (none in this component currently).

---

#### Minor-6 — Double lookup trigger: `onblur` fires after `onkeyup` Enter, causing two Apex calls
**Severity:** Minor
**Lines:** 119–129

**Issue:** When the user types a serial number and presses Enter, `handleSerialNumberKeyUp` fires and calls `_lookupAsset()`. The browser then fires a `blur` event as focus leaves the field, which triggers `handleSerialNumberBlur` and calls `_lookupAsset()` a second time. This results in two identical Apex calls for the same serial.

**Recommended Fix:** Add a flag to track whether a lookup is in progress or has already been completed for the current serial:

```javascript
_lastLookedUpSerial = '';

handleSerialNumberKeyUp(event) {
    if (event.key === 'Enter' && this.serialNumber
        && this.serialNumber !== this._lastLookedUpSerial) {
        this._lastLookedUpSerial = this.serialNumber;
        this._lookupAsset();
    }
}

handleSerialNumberBlur() {
    if (this.serialNumber && this.serialNumber !== this._lastLookedUpSerial) {
        this._lastLookedUpSerial = this.serialNumber;
        this._lookupAsset();
    }
}
```

---

#### Info-3 — `handleSubmit` and `handleResolve` are stubs without `disabled` attribute
**Severity:** Info
**Lines:** 276–291

**Issue:** The Submit and Resolve buttons fire toasts saying "Not Available". While this is acceptable per the TDD, the buttons remain visually enabled. A user seeing an active button that does nothing but show "Not Available" is a confusing UX pattern.

**Recommendation:** Add a `disabled` attribute to both buttons until MP-5 wires them, or change the toast variant to `warning`. This is a UX suggestion, not a defect.

---

### 4. `caseCreate.html`

#### MAJOR (via Minor elevation) — `if:true` template directive is deprecated at API v65
**Severity:** Major
**Lines:** 120

**Issue:** `<template if:true={assetFound}>` uses the legacy `if:true` directive. At API version 65.0, this directive is deprecated in favor of `lwc:if`. While it still functions, Salesforce has indicated `if:true` / `if:false` will be removed in a future release. Using the deprecated form at new API versions creates forward-compatibility risk and generates a lint warning.

**Recommended Fix:**

```html
<template lwc:if={assetFound}>
```

---

#### Minor-7 — `lightning-record-picker` missing `label` attribute value and accessible outer label has no `for` linkage
**Severity:** Minor
**Lines:** 248–258

**Issue:** The `lightning-record-picker` is nested inside a manually constructed `slds-form-element` with a `<label>` that reads "PART NUMBER". However:
1. The `lightning-record-picker` has `label=""` (empty string), which means screen readers get no label from the component itself.
2. The outer `<label class="slds-form-element__label">` has no `for` attribute linking it to the inner input rendered by `lightning-record-picker` (whose internal input Id is not predictable).

**Recommended Fix:** Use the built-in `label` attribute of `lightning-record-picker` directly and remove the wrapping manual `slds-form-element`:

```html
<lightning-record-picker
    label="PART NUMBER"
    object-api-name="Part__c"
    value={partNumberId}
    placeholder="Search"
    onchange={handlePartNumberChange}>
</lightning-record-picker>
```

---

#### Minor-8 — `href="javascript:void(0);"` on the Clear Search anchor
**Severity:** Minor
**Lines:** 110–113

**Issue:** `href="javascript:void(0);"` is considered a security anti-pattern (CSP violation risk in strict Lightning environments) and is inaccessible — screen readers announce it as a navigation link rather than a button. The inline comment `<!-- svelte-ignore a11y-invalid-attribute -->` acknowledges the issue but leaves it unresolved.

**Recommended Fix:** Replace the `<a>` element with a `<button>` styled as a link, which is the correct semantic element for a click action with no navigation:

```html
<button
    class="clear-search-link slds-button slds-button_reset"
    type="button"
    onclick={handleClearSearch}>
    Clear Search
</button>
```

---

#### Info-4 — Action buttons (Add Favorite, Copy, Print to PDF) have no `disabled` or `aria` state
**Severity:** Info
**Lines:** 33–47

**Issue:** The three header action buttons are rendered as fully active buttons with no functionality attached. As with Submit/Resolve, they are out of scope for MP-7, but without `disabled` or `aria-disabled="true"`, keyboard users can tab to them and activate them silently.

**Recommendation:** Add `disabled` attribute or `aria-disabled="true"` and `tabindex="-1"` to stub buttons until they are wired in future stories.

---

### 5. `caseCreate.css`

No critical or major issues found. The CSS is well-structured and uses standard SLDS tokens correctly.

**Observation:** The `:host lightning-input[disabled] .slds-input` overrides on lines 135–143 use internal SLDS class selectors that could break if Salesforce updates the SLDS `lightning-input` shadow DOM structure. This is an acceptable trade-off for mockup fidelity but should be noted in a comment as a potential upgrade risk (it already has a partial comment explaining the intent — the maintenance risk note is the missing piece).

---

## Recommended Fix Priority

| Priority | Issue | Effort |
|----------|-------|--------|
| 1 (before deploy) | MAJOR-1 — Add FLS enforcement (`Security.stripInaccessible`) | Medium |
| 2 (before deploy) | MAJOR-3 — Remove duplicate test method | Low |
| 3 (before deploy) | MAJOR-4 — Replace hard-coded picklist with `getPicklistValues` wire OR add clear comment | Low–Medium |
| 4 (before deploy) | MAJOR (HTML) — Replace `if:true` with `lwc:if` | Low |
| 5 (next sprint) | MAJOR-2 — Remove unnecessary `Status` re-query in `saveCaseAsDraft` | Low |
| 6 (next sprint) | Minor-1 — Use schema-based RecordType Id (zero SOQL) | Low |
| 7 (next sprint) | Minor-5 — Remove unnecessary `@track` decorators | Low |
| 8 (next sprint) | Minor-6 — Prevent double Apex call on Enter + blur | Low |
| 9 (next sprint) | Minor-7 — Fix `lightning-record-picker` accessibility | Low |
| 10 (next sprint) | Minor-8 — Replace `<a href="javascript:void(0)">` with `<button>` | Low |

---

## What Was Done Well

- `with sharing` is correctly declared — record-level security is enforced.
- All three `@AuraEnabled` methods use try/catch with `AuraHandledException` — no raw exceptions bubble to the UI.
- SOQL queries use bind variables exclusively — no dynamic SOQL, zero injection risk.
- `findAssetBySerial` uses safe-navigation (`?.`) for cross-object traversal — no null pointer risk on Brand/Model chain.
- `getPartDescription` is correctly marked `cacheable=true` — read-only, safe to cache.
- `@TestSetup` is used — shared test data created once, not per-method.
- `@SeeAllData` is absent — correct.
- Test methods follow PNB pattern (Positive/Negative/Boundary) as required by the project standard.
- LWC error handling uses `error.body?.message` optional chaining — safe against undefined error shapes.
- `_lookupAsset` and `_clearProductFields` are correctly prefixed with underscore to signal private methods — good convention.
- CSS uses SLDS spacing tokens and avoids magic numbers outside of brand colors.
- The component correctly builds the 11-field Case payload on Save without sending Engine Serial # — matches TDD §4.4 spec.
