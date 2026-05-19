public with sharing class VerificationEventTriggerHandler {

    public static void handleAfterInsert(List<Verification_Event__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }

        try {
            List<Compliance_Task__c> tasks = new List<Compliance_Task__c>();

            for (Verification_Event__e eventRecord : events) {
                if (String.isBlank(eventRecord.Provider_Application_ID__c)) {
                    ErrorLogger.log(
                        'VerificationEventTriggerHandler',
                        'handleAfterInsert',
                        null,
                        'INVALID_VERIFICATION_EVENT',
                        'Missing Provider_Application_ID__c. NPI=' + eventRecord.NPI_Number__c
                    );
                    continue;
                }

                tasks.add(new Compliance_Task__c(
                    Subject__c = buildSubject(eventRecord),
                    Provider_Application__c = (Id) eventRecord.Provider_Application_ID__c,
                    Risk_Category__c = eventRecord.Risk_Category__c,
                    Verification_ID__c = eventRecord.Verification_ID__c
                ));
            }

            if (!tasks.isEmpty()) {
                List<Database.SaveResult> results = Database.insert(tasks, false);

                for (Integer i = 0; i < results.size(); i++) {
                    if (!results[i].isSuccess()) {
                        String errorMsg = '';
                        for (Database.Error err : results[i].getErrors()) {
                            errorMsg += err.getMessage() + '; ';
                        }
                        ErrorLogger.log(
                            'VerificationEventTriggerHandler',
                            'handleAfterInsert',
                            tasks[i].Provider_Application__c,
                            'COMPLIANCE_TASK_DML_FAILURE',
                            errorMsg
                        );
                    }
                }
            }
        } finally {
            ErrorLogger.flush();
        }
    }

    private static String buildSubject(Verification_Event__e eventRecord) {
        return 'High Risk Provider Review - NPI: ' + eventRecord.NPI_Number__c;
    }
}