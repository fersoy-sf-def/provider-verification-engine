trigger ProviderApplicationTrigger on Provider_Application__c (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        // Keep trigger thin; delegate all processing to handler and async service layer.
        ProviderApplicationTriggerHandler.handleAfterInsert(Trigger.new);
    }
}