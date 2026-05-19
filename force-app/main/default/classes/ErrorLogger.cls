public class ErrorLogger {
    private static List<Error_Log__c> buffer = new List<Error_Log__c>();
    private static final Integer MAX_BUFFER_SIZE = 1000;
    private static final Integer MAX_MESSAGE_LENGTH = 32000;
    private static final Integer MAX_TEXT_LENGTH = 100;

    public static void log(String className, String methodName, Id recordId, String errorType, String message) {
        if (buffer.size() >= MAX_BUFFER_SIZE) {
            System.debug(
                LoggingLevel.ERROR,
                'ErrorLogger buffer limit reached. Additional log skipped. ' +
                'Class=' + className + ', Method=' + methodName + ', RecordId=' + String.valueOf(recordId)
            );
            return;
        }
        buffer.add(new Error_Log__c(
            Class_Name__c = abbreviate(className, MAX_TEXT_LENGTH),
            Method_Name__c = abbreviate(methodName, MAX_TEXT_LENGTH),
            Record_ID__c = recordId == null ? null : String.valueOf(recordId),
            Exception_Type__c = abbreviate(errorType, MAX_TEXT_LENGTH),
            Message__c = abbreviate(message, MAX_MESSAGE_LENGTH)
        ));
    }

    public static void log(String className, String methodName, Id recordId, String errorType, Exception ex) {
        String message = ex == null
            ? 'Unknown exception'
            : ex.getTypeName() + ': ' + ex.getMessage() + ' | Stack: ' + ex.getStackTraceString();
        log(className, methodName, recordId, errorType, message);
    }

    public static void flush() {
        if (buffer.isEmpty()) {
            return;
        }
        List<Error_Log__c> logsToInsert = new List<Error_Log__c>(buffer);
        buffer.clear();
        try {
            List<Database.SaveResult> results = Database.insert(logsToInsert, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    for (Database.Error err : results[i].getErrors()) {
                        System.debug(
                            LoggingLevel.ERROR,
                            'CRITICAL: Error_Log__c insert failed: ' + err.getMessage()
                        );
                    }
                }
            }
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.ERROR,
                'CRITICAL: ErrorLogger.flush() failed: ' + ex.getTypeName() + ': ' + ex.getMessage()
            );
        }
    }

    public static Integer getBufferSize() {
        return buffer.size();
    }

    @TestVisible
    private static void clearBuffer() {
        buffer.clear();
    }

    private static String abbreviate(String value, Integer maxLength) {
        if (String.isBlank(value)) {
            return value;
        }
        return value.length() <= maxLength ? value : value.substring(0, maxLength);
    }
}