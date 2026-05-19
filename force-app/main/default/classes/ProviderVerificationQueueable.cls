public class ProviderVerificationQueueable implements Queueable, Database.AllowsCallouts {
    public static final Integer MAX_RECORDS_PER_EXECUTION = 100;
    private List<Id> recordIds;
    private Integer chunkSize;
    private ICredentialingAPI apiClient;

    public ProviderVerificationQueueable(List<Id> recordIds) {
        this(recordIds, MAX_RECORDS_PER_EXECUTION, null);
    }

    public ProviderVerificationQueueable(List<Id> recordIds, Integer chunkSize) {
        this(recordIds, chunkSize, null);
    }

    @TestVisible
    private ProviderVerificationQueueable(List<Id> recordIds, Integer chunkSize, ICredentialingAPI apiClient) {
        this.recordIds = recordIds != null ? recordIds.clone() : new List<Id>();
        this.chunkSize = chunkSize == null || chunkSize <= 0
            ? MAX_RECORDS_PER_EXECUTION
            : Math.min(chunkSize, MAX_RECORDS_PER_EXECUTION);
        this.apiClient = apiClient;
    }

    public void execute(QueueableContext context) {
        if (recordIds == null || recordIds.isEmpty()) {
            return;
        }

        List<Id> currentChunk = new List<Id>();
        List<Id> remainingChunk = new List<Id>();
        for (Integer i = 0; i < recordIds.size(); i++) {
            if (i < chunkSize) {
                currentChunk.add(recordIds[i]);
            } else {
                remainingChunk.add(recordIds[i]);
            }
        }

        try {
            List<Provider_Application__c> applications =
                ProviderApplicationSelector.selectById(new Set<Id>(currentChunk));
            if (!applications.isEmpty()) {
                ProviderVerificationService service = apiClient != null
                    ? new ProviderVerificationService(apiClient)
                    : new ProviderVerificationService();
                ProviderVerificationService.ProcessingContext ctx =
                    service.processVerifications(applications);
                executeDmlPhase(ctx);
            }
        } catch (Exception ex) {
            ErrorLogger.log(
                'ProviderVerificationQueueable',
                'execute',
                null,
                'UNEXPECTED_QUEUEABLE_FAILURE',
                ex
            );
        } finally {
            ErrorLogger.flush();
        }

        chainIfNeeded(remainingChunk);
    }

    private void executeDmlPhase(ProviderVerificationService.ProcessingContext ctx) {
        if (ctx == null) {
            return;
        }
        insertAccountsAndContacts(ctx);
        Set<Id> successfullyUpdatedAppIds = updateApplications(ctx);
        publishEventsForSuccessfulApplications(ctx, successfullyUpdatedAppIds);
    }

    private void insertAccountsAndContacts(ProviderVerificationService.ProcessingContext ctx) {
        if (ctx.accountsToInsert.isEmpty()) {
            return;
        }
        List<Database.SaveResult> accResults = Database.insert(ctx.accountsToInsert, false);
        parseSaveResults(accResults, ctx.accountsToInsert, 'Account');

        List<Contact> contactsReadyToInsert = new List<Contact>();
        for (Integer i = 0; i < ctx.accountsToInsert.size(); i++) {
            if (accResults[i].isSuccess() &&
                ctx.accountsToInsert[i].Id != null &&
                i < ctx.contactsToInsert.size()) {
                Contact con = ctx.contactsToInsert[i];
                con.AccountId = ctx.accountsToInsert[i].Id;
                contactsReadyToInsert.add(con);
            }
        }
        if (!contactsReadyToInsert.isEmpty()) {
            List<Database.SaveResult> conResults = Database.insert(contactsReadyToInsert, false);
            parseSaveResults(conResults, contactsReadyToInsert, 'Contact');
        }
    }

    private Set<Id> updateApplications(ProviderVerificationService.ProcessingContext ctx) {
        Set<Id> successfullyUpdatedAppIds = new Set<Id>();
        if (ctx.applicationsToUpdate.isEmpty()) {
            return successfullyUpdatedAppIds;
        }
        List<Database.SaveResult> appResults = Database.update(ctx.applicationsToUpdate, false);
        parseSaveResults(appResults, ctx.applicationsToUpdate, 'Provider_Application__c');
        for (Integer i = 0; i < appResults.size(); i++) {
            if (appResults[i].isSuccess()) {
                successfullyUpdatedAppIds.add(ctx.applicationsToUpdate[i].Id);
            }
        }
        return successfullyUpdatedAppIds;
    }

    private void publishEventsForSuccessfulApplications(
        ProviderVerificationService.ProcessingContext ctx,
        Set<Id> successfullyUpdatedAppIds
    ) {
        if (ctx.eventsToPublish.isEmpty() || successfullyUpdatedAppIds.isEmpty()) {
            return;
        }
        List<Verification_Event__e> safeEventsToPublish = new List<Verification_Event__e>();
        for (Verification_Event__e eventRecord : ctx.eventsToPublish) {
            Id appId = (Id) eventRecord.Provider_Application_ID__c;
            if (successfullyUpdatedAppIds.contains(appId)) {
                safeEventsToPublish.add(eventRecord);
            }
        }
        if (safeEventsToPublish.isEmpty()) {
            return;
        }
        List<Database.SaveResult> eventResults = EventBus.publish(safeEventsToPublish);
        for (Integer i = 0; i < eventResults.size(); i++) {
            if (!eventResults[i].isSuccess()) {
                String errors = '';
                for (Database.Error err : eventResults[i].getErrors()) {
                    errors += err.getMessage() + '; ';
                }
                ErrorLogger.log(
                    'ProviderVerificationQueueable',
                    'publishEventsForSuccessfulApplications',
                    null,
                    'EVENT_PUBLISH_FAILURE',
                    errors
                );
            }
        }
    }

    private void parseSaveResults(List<Database.SaveResult> results, List<SObject> records, String objectType) {
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                String errorMsg = '';
                for (Database.Error err : results[i].getErrors()) {
                    errorMsg += err.getMessage() + '; ';
                }
                Id recordId = records[i].Id != null ? records[i].Id : null;
                ErrorLogger.log(
                    'ProviderVerificationQueueable',
                    'parseSaveResults',
                    recordId,
                    objectType + '_DML_FAILURE',
                    errorMsg
                );
            }
        }
    }

    private void chainIfNeeded(List<Id> remainingIds) {
        if (remainingIds == null || remainingIds.isEmpty()) {
            return;
        }
        try {
            System.enqueueJob(
                new ProviderVerificationQueueable(remainingIds, chunkSize, apiClient)
            );
        } catch (Exception ex) {
            ErrorLogger.log(
                'ProviderVerificationQueueable',
                'chainIfNeeded',
                null,
                'QUEUEABLE_CHAIN_FAILURE',
                ex
            );
            ErrorLogger.flush();
        }
    }
}