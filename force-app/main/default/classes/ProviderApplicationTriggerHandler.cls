public with sharing class ProviderApplicationTriggerHandler {
    @TestVisible private static Boolean bypassTrigger = false;
    private static Boolean isExecuting = false;

    public static void handleAfterInsert(List<Provider_Application__c> newRecords) {
        if (bypassTrigger || isExecuting || newRecords == null || newRecords.isEmpty()) {
            return;
        }
        isExecuting = true;
        try {
            List<Id> eligibleIds = ProviderApplicationDomain.filterEligibleForVerification(newRecords);
            if (!eligibleIds.isEmpty()) {
                System.enqueueJob(new ProviderVerificationQueueable(eligibleIds, 100));
            }
        } finally {
            isExecuting = false;
        }
    }
}