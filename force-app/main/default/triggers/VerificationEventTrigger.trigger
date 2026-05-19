trigger VerificationEventTrigger on Verification_Event__e (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        // Platform Event subscriber delegates all processing to handler.
        VerificationEventTriggerHandler.handleAfterInsert(Trigger.new);
    }
}