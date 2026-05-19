# High-Volume Provider Verification Engine

## Overview

A production-grade, bulkified Salesforce solution that automates provider onboarding by verifying NPI numbers against an external Credentialing API. The system evaluates risk profiles and orchestrates downstream actions — automatically provisioning Accounts and Contacts for low-risk providers, or triggering a compliance workflow for high-risk providers.

Built entirely in Apex using enterprise design patterns, with zero Flow or Process Builder dependencies.

---

## Architecture

### Design Patterns Used

| Layer | Pattern | Responsibility |
|-------|---------|--------------|
| **Trigger** | Trigger Handler | Thin routing layer — no business logic in triggers |
| **Service** | Service Layer | `ProviderVerificationService` orchestrates the verification workflow |
| **Selector** | Selector Layer | `ProviderApplicationSelector` centralizes all SOQL queries |
| **Domain** | Domain Layer | `ProviderApplicationDomain` encapsulates business rules and validation |
| **Integration** | Interface + DI | `ICredentialingAPI` enables testable, swappable API clients |
| **Async** | Self-Chaining Queueable | `ProviderVerificationQueueable` processes 200+ records in 100-callout chunks |
| **Event** | Platform Event | `Verification_Event__e` decouples high-risk compliance from verification |
| **Utility** | Static Accumulator | `ErrorLogger` bulk-safely captures failures without crashing the transaction |

### Data Flow Diagram

```
Provider_Application__c Insert
        |
        v
ProviderApplicationTrigger (after insert)
        |
        v
ProviderApplicationTriggerHandler
  [Filter: Status='New' AND NPI!=null]
        |
        v
System.enqueueJob(ProviderVerificationQueueable)
        |
        v
ProviderVerificationQueueable (chunk <=100)
        |
        v
ProviderVerificationService
        |
        +--> ICredentialingAPI.verifyProviders()
        |           |
        |           v
        |    CredentialingAPIImpl (production)
        |    OR CredentialingAPIMockImpl (tests)
        |
        v
Process Results
        |
        +--> Low Risk: Account + Contact
        |           |
        |           v
        |    Database.insert(accounts, false)
        |    Database.insert(contacts, false)
        |
        +--> High Risk: Verification_Event__e
        |           |
        |           v
        |    EventBus.publish(events)
        |           |
        |           v
        |    VerificationEventTriggerHandler
        |           |
        |           v
        |    Compliance_Task__c
        |
        v
Database.update(applications, false)
        |
        v
ErrorLogger.flush()  [bulk insert error logs]
        |
        v
Chain next Queueable (if records remain)
```

### Why Queueable Over Future or Batch?

- **Future**: Cannot accept sObjects, cannot chain, no job monitoring
- **Batch**: Overkill for real-time trigger flows; designed for scheduled background jobs
- **Queueable**: Supports complex state, sObject passing, job chaining (critical for >100 callouts), and `AsyncApexJob` monitoring

### Scalability Strategy

| Batch Size | Callouts | Queueable Jobs | DML Rows (approx) |
|------------|----------|----------------|-------------------|
| 200 | 100 + 100 | 1 (enqueued) + 1 (chained) | 600 |
| 500 | 100 x 5 | 1 + 4 chained | 1,500 |
| 2,000 | 100 x 20 | 1 + 19 chained | 6,000 |

All values safely within Governor Limits. The Queueable splits records into chunks of <=100, performs **all callouts first** (zero DML during callout phase), then executes **all DML** with `Database.*` methods and `allOrNone=false`.

---

## Data Model

### Custom Objects & Fields

#### Provider_Application__c
| Field | Type | Purpose |
|-------|------|---------|
| First_Name__c | Text(80) | Provider first name |
| Last_Name__c | Text(80) | Provider last name |
| Email__c | Email | Contact email |
| NPI_Number__c | Text(10) | National Provider Identifier (10 digits) |
| Status__c | Picklist | New, Verified, Failed |
| Risk_Tier__c | Picklist | Low, High |
| Verification_ID__c | Text(100) | External API verification ID (from sample response payload) |
| API_Response_JSON__c | Long Text Area | Raw JSON response for audit and vendor dispute debugging |
| Error_Details__c | Long Text Area | Surface-level failure reason visible to support teams without querying Error_Log__c |
| Processed_Timestamp__c | DateTime | Proves the Queueable executed and aids SLA reporting |
| Retry_Count__c | Number(3,0) | Reserved for future transient failure retry logic |

> **Note on Audit Fields:** The assignment specifies First Name, Last Name, Email, NPI, Status, and Risk Tier. I added `Verification_ID__c`, `API_Response_JSON__c`, `Error_Details__c`, `Processed_Timestamp__c`, and `Retry_Count__c` as production audit fields. A senior integration without observability is unmaintainable at 2 AM — these fields allow support teams to debug vendor responses, verify Queueable execution, and retry transient failures without escalating to engineering.

#### Compliance_Task__c
| Field | Type | Purpose |
|-------|------|---------|
| Subject__c | Text(255) | Task description |
| Provider_Application__c | Lookup | Related provider application |
| Risk_Category__c | Text(100) | High risk classification |
| Verification_ID__c | Text(100) | External verification reference |

#### Error_Log__c
| Field | Type | Purpose |
|-------|------|---------|
| Class_Name__c | Text(100) | Apex class where error occurred |
| Method_Name__c | Text(100) | Method name |
| Record_ID__c | Text(18) | Related record ID |
| Exception_Type__c | Text(100) | Error classification |
| Message__c | Long Text Area | Full error message and stack trace |

### Platform Event

- **Verification_Event__e** — Bridges verification logic to compliance workflow. Published **only after** parent DML succeeds, guaranteeing no orphaned Compliance Tasks.
  - Fields: Provider_Application_ID__c, NPI_Number__c, Risk_Category__c, Verification_ID__c

### Custom Metadata Type

- **API_Configuration__mdt** — Metadata-driven endpoint and timeout configuration. No hardcoded URLs in Apex.
  - Fields: Endpoint_URL__c (URL), Timeout_Milliseconds__c (Number), Active__c (Checkbox)

---

## Error Handling Strategy

### Framework Design

Every DML operation uses `Database.*(records, false)` with explicit `SaveResult` parsing:

- **API failure** -> Record marked `Failed`, error logged, transaction continues
- **DML validation rule failure** -> Other records in batch still succeed
- **Total API meltdown** -> All records in chunk marked `Failed`, error logged once
- **Platform Event publish failure** -> Captured and logged without crashing DML

### Critical Safety: No Orphaned Compliance Tasks

The Queueable **only publishes Platform Events for Provider Applications whose update succeeded**. If a high-risk application's DML update fails, its event is filtered out before `EventBus.publish()`:

```apex
Set<Id> successfullyUpdatedAppIds = updateApplications(ctx);
publishEventsForSuccessfulApplications(ctx, successfullyUpdatedAppIds);
```

This guarantees: **no Compliance Task exists without a matching Verified/High provider record.**

### ErrorLogger

- Static `List<Error_Log__c>` buffer accumulates errors in-memory
- **No auto-flush** during `log()` — prevents `Uncommitted work pending` during callout phase
- Bulk `Database.insert(buffer, false)` flushes at end of transaction
- If even logging fails -> debug log fallback (last-resort survival)

### Partial Success Guarantee

One bad record (malformed NPI, validation rule, API timeout) cannot poison the entire batch. This was validated in unit tests with controlled DML failures.

---

## Testing Approach

### Test Coverage: >85% (27 test methods)

| Test | What It Proves |
|------|----------------|
| `testLowRiskPath_ProducesCorrectContext` | Service-layer verification -> Account + Contact prepared in ProcessingContext |
| `testHighRiskPath_ProducesEventAndCorrectContext` | High risk -> Platform Event prepared, no Account/Contact |
| `testHighRiskPath_PublishesPlatformEvent_CreatesComplianceTask` | End-to-end: Event publish -> `Test.getEventBus().deliver()` -> Compliance Task created |
| `testApiTotalFailure_MarksAllFailed` | Total API exception -> all records marked Failed with error details |
| `testPartialDmlFailure_OtherRecordsSucceed` | `allOrNone=false` preserves partial success (one bad Account doesn't kill the batch) |
| `testMixedResults_LowHighAndFailure` | Per-NPI mock mapping: Low, High, and Error records coexist in one batch |
| `testBulkProcessing_RecordsChunked` | 200-record trigger -> Queueable processes 100, chains remaining 100 |
| `testQueueableSplitsCurrentAndRemainingChunks` | Chained job created for remaining records |
| `testHttpIntegration_LowRiskResponse` | Real HTTP layer with `HttpCalloutMock` |
| `testEndToEnd_LowRiskViaTrigger_WithHttpMock` | Full trigger -> Queueable -> Service -> DML flow with real HTTP mock |
| `testEventCreatesComplianceTask` | Platform Event subscriber creates tasks |
| `testBulkEventsCreateMultipleTasks` | 50 events -> 50 Compliance Tasks |
| `testEventWithoutProviderApplicationIdDoesNotCreateTask` | Invalid events are skipped, no orphan tasks |
| `testFlushInsertsRecordsAndClearsBuffer` | ErrorLogger bulk accumulation with field assertions |
| `testLogWithExceptionCapturesExceptionDetails` | Exception type and stack trace captured |
| `testLogHandlesNullValuesSafely` | Null inputs do not crash the logger |
| `testLongMessageDoesNotBreakLogging` | 50KB message truncated to field limit |
| `testBufferLimitDoesNotAutoFlush` | Buffer cap prevents memory overflow |
| `testValidNpi` | Domain layer NPI validation with trim |
| `testInvalidNpi` | Null, blank, short, non-numeric NPIs rejected |
| `testRiskMapping` | API "Low Risk" -> Salesforce "Low" |
| `testIsLowRiskAndIsHighRisk` | Case-insensitive risk category matching |
| `testFilterEligibleForVerification` | Only New + valid NPI records are eligible |
| `testFilterEligibleWithNullList` | Null input returns empty list |
| `testIsEligibleForVerification` | Status and NPI rules enforced |

### Mock Strategy

- **Interface mock** (`CredentialingAPIMockImpl`) for fast service-layer tests
- **HttpCalloutMock** (`CredentialingAPIHttpMock`) for integration-layer validation
- Both strategies coexist to demonstrate testable architecture

### Why No TestDataFactory?

A `TestDataFactory` is standard practice for large suites with 20+ tests creating complex object hierarchies. For this assignment:
- Each test creates 1-5 records inline via a private `createProvider()` helper
- No complex 5-object hierarchies requiring consistent seed data
- No shared validation-rule-dependent field combinations across tests
- Adding a factory would add a class and deployment step with minimal payoff for this scope

**Future enhancement:** Extract the inline helpers into `ProviderVerificationTestDataFactory` as the suite grows beyond 20+ methods or when multiple developers need shared seed data.

---

## Assumptions & Design Rationale

### Questions Asked
- Confirmed mock API depth requirements with hiring team
- Confirmed idempotency expectations for Compliance Tasks (new task per high-risk verification)

### Assumptions Made

1. **API Granularity**: One callout per NPI. In production, if the external API supports bulk verification, the chunking strategy would shift to batch-level callouts.
2. **Duplicate Management**: Each Provider Application creates a new Account and Contact. In production, I would implement `Datacloud.FindDuplicates` or email-based upsert to prevent duplicates.
3. **Error Retention**: `Error_Log__c` is sufficient for demo scale. At >10,000 errors/day, I would migrate to a Big Object or external logging service.
4. **Retry Policy**: No automatic retry on transient timeout. In production, I would add a scheduled reconciliation job with exponential backoff using the `Retry_Count__c` field.
5. **Named Credentials**: Not implemented for the mock endpoint. In production, the endpoint and authentication would use Salesforce Named Credentials for secure secret management and org-wide endpoint rotation without code changes.
6. **Trigger Dispatcher**: Not implemented. For a single-object assignment, a generic `TriggerDispatcher` + `ITriggerHandler` framework adds indirection without value. In a production org with 10+ triggered objects, I would promote this to a formal dispatcher to standardize routing.
7. **Custom Tabs**: Included (`Provider_Application__c`, `Compliance_Task__c`, `Error_Log__c`) to simplify reviewer testing and manual validation in the Salesforce UI.

---

## AI-Augmented Development Disclosure

### 1. Complex Prompt Used

> "You are a Salesforce enterprise architect. I need to design a bulk-safe Queueable Apex pattern that processes 200+ records requiring individual HTTP callouts to an external NPI verification API. Constraints: maximum 100 callouts per Queueable execution; must support partial DML success (one bad record cannot fail the batch); must use dependency injection for the API client to enable unit testing; must separate callout phase from DML phase to avoid uncommitted work errors; must chain additional Queueable jobs for records beyond the first 100. Design the class structure, interface definitions, and error handling strategy. Provide the Queueable execute() method logic showing exactly how to chunk records, perform callouts, collect results, and execute bulk DML with Database.SaveResult error handling. Also explain how to test this pattern given that Test.stopTest() only executes one Queueable depth in unit tests."

**This prompt** asks for a **pattern** under explicit constraints. It names governor limits (100 callouts), design patterns (dependency injection, Database.SaveResult), and testing pitfalls (Queueable depth). This demonstrates that the engineer knows what can go wrong before the AI writes a line.

### 2. AI Hallucination Caught & Corrected

**The Hallucination:**
During the project, the AI suggested using `new System.CalloutException('Simulated timeout')` inside an Apex mock class to simulate API timeouts in unit tests.

**Why It Is Wrong:**
`System.CalloutException` is a system-thrown exception in Apex. It cannot be instantiated with the `new` keyword in user code. Attempting to do so results in a compile-time error.

**How I Caught It:**
I attempted to save the class and received a compile error: "Invalid constructor name." I then checked the official Apex Developer Guide under "Exception Classes" and confirmed that `CalloutException` is listed as a system exception with no public constructor.

**The Correction:**
I created a custom exception class instead:
```apex
public class MockCalloutException extends Exception {}
```
This custom exception is thrown inside the mock implementation when the test requests a timeout scenario, achieving the same test behavior without violating Apex language rules.

### 3. Top Three Enterprise AI Rules

**Rule 1: Verify every governor limit claim against Salesforce documentation.**
AI tools frequently confuse synchronous vs. asynchronous limits (e.g., claiming Queueable allows 200 callouts or 150 DML statements). A senior engineer never trusts an AI-generated limit. They open the [Apex Governor Limits](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_gov_limits.htm) page and validate before merging. In this project, the AI initially suggested processing all 200 records in one Queueable job. I rejected this after confirming the 100-callout limit and implemented chunked self-chaining instead.

**Rule 2: Reject any integration code that lacks dependency injection or hardcodes credentials.**
AI often generates `HttpRequest` code with hardcoded API keys or direct `new Http().send()` calls inside service classes. Enterprise standard demands: (a) an `interface` for the API client, (b) constructor injection, (c) Named Credentials or Protected Custom Metadata for secrets. If the AI output cannot be unit-tested without a real endpoint, it is rejected. In this project, every AI-generated HTTP callout block was rewritten behind the `ICredentialingAPI` interface.

**Rule 3: Require `allOrNone=false` and SaveResult handling on all AI-generated DML.**
AI defaults to `insert records;` and `update records;`. In production, this is a batch-killer. My rule: every AI-generated DML block must be rewritten to use `Database.insert(records, false)` with explicit `Database.SaveResult` iteration. If the AI cannot generate that, the engineer writes it manually. In this project, all DML in the Queueable, Service, and Event Handler uses `allOrNone=false` with per-record error parsing.

---

## Deployment Instructions

### Prerequisites
- Salesforce CLI (`sf`) installed
- A Salesforce Developer Org or Scratch Org

### Deploy
```bash
sf org login web --target-org <your-org-alias>
sf project deploy start --source-dir force-app --target-org <your-org-alias> --wait 30
```

### Run Tests
```bash
sf apex run test --target-org <your-org-alias> --wait 10 --result-format human
```

### Manual Test
1. Create a `Provider_Application__c` record with Status = `New` and a valid NPI
2. The trigger enqueues `ProviderVerificationQueueable`
3. Check **Apex Jobs** for completion
4. For Low Risk: verify Account and Contact created
5. For High Risk: verify Compliance Task created via Platform Event

---

## Future Enhancements

- **TestDataFactory**: Extract inline `createProvider()` helpers into `ProviderVerificationTestDataFactory` as the suite grows
- **Constants Class**: Centralize string literals into a `ProviderVerificationConstants` class
- **Named Credentials**: Replace hardcoded endpoint with `callout:Credentialing_API` for production security
- **Transaction Finalizer** (API v60+): Attach `System.Finalizer` to the Queueable for fatal governor limit recovery
- **Circuit Breaker**: Stop burning callouts during API outages using a `Circuit_Open__c` flag
- **Retry with exponential backoff**: Use `Retry_Count__c` with a scheduled job for transient failures
- **Duplicate Management API**: Use `Datacloud.FindDuplicates` for Contact matching by email
- **Platform Cache**: Cache `API_Configuration__mdt` to eliminate per-chunk SOQL

