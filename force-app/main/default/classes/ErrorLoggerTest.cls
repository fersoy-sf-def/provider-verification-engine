@IsTest
private class ErrorLoggerTest {

    @IsTest
    static void testLogAccumulatesInBuffer() {
        ErrorLogger.clearBuffer();
        ErrorLogger.log('TestClass', 'testMethod', null, 'TEST_ERROR', 'Test message');
        System.assertEquals(1, ErrorLogger.getBufferSize(), 'Logger should accumulate one log record in memory.');
    }

    @IsTest
    static void testFlushInsertsRecordsAndClearsBuffer() {
        ErrorLogger.clearBuffer();
        ErrorLogger.log('TestClass', 'testMethod', null, 'TEST_ERROR', 'Test message');
        ErrorLogger.log('TestClass', 'testMethod2', null, 'TEST_ERROR2', 'Test message 2');
        ErrorLogger.flush();
        List<Error_Log__c> logs = [
            SELECT Id, Class_Name__c, Method_Name__c, Exception_Type__c, Message__c
            FROM Error_Log__c
            ORDER BY CreatedDate
        ];
        System.assertEquals(2, logs.size(), 'Two error logs should be inserted.');
        System.assertEquals(0, ErrorLogger.getBufferSize(), 'Buffer should be cleared after flush.');
        System.assertEquals('TestClass', logs[0].Class_Name__c);
        System.assertEquals('testMethod', logs[0].Method_Name__c);
        System.assertEquals('TEST_ERROR', logs[0].Exception_Type__c);
        System.assertEquals('Test message', logs[0].Message__c);
    }

    @IsTest
    static void testFlushWithEmptyBufferDoesNothing() {
        ErrorLogger.clearBuffer();
        ErrorLogger.flush();
        System.assertEquals(0, [SELECT COUNT() FROM Error_Log__c], 'No logs should be inserted when buffer is empty.');
        System.assertEquals(0, ErrorLogger.getBufferSize(), 'Buffer should remain empty.');
    }

    @IsTest
    static void testLogWithExceptionCapturesExceptionDetails() {
        ErrorLogger.clearBuffer();
        try {
            Integer x = 1 / 0;
        } catch (Exception ex) {
            ErrorLogger.log('TestClass', 'testMethod', null, 'MATH_EXCEPTION', ex);
        }
        ErrorLogger.flush();
        Error_Log__c log = [
            SELECT Id, Class_Name__c, Method_Name__c, Exception_Type__c, Message__c
            FROM Error_Log__c
            LIMIT 1
        ];
        System.assertEquals('TestClass', log.Class_Name__c);
        System.assertEquals('testMethod', log.Method_Name__c);
        System.assertEquals('MATH_EXCEPTION', log.Exception_Type__c);
        System.assert(
            log.Message__c.contains('MathException') || log.Message__c.contains('Divide'),
            'Log message should contain exception details.'
        );
        System.assertEquals(0, ErrorLogger.getBufferSize());
    }

    @IsTest
    static void testLogHandlesNullValuesSafely() {
        ErrorLogger.clearBuffer();
        ErrorLogger.log(null, null, null, null, (String) null);
        ErrorLogger.flush();
        System.assertEquals(1, [SELECT COUNT() FROM Error_Log__c], 'Logger should not fail when optional values are null.');
    }

    @IsTest
    static void testLongMessageDoesNotBreakLogging() {
        ErrorLogger.clearBuffer();
        String longMessage = 'A'.repeat(50000); // Exceeds field limit
        ErrorLogger.log('TestClass', 'testMethod', null, 'LONG_MSG', longMessage);
        ErrorLogger.flush();
        Error_Log__c log = [
            SELECT Message__c FROM Error_Log__c LIMIT 1
        ];
        System.assertNotEquals(null, log.Message__c, 'Long message should be truncated and inserted.');
        System.assert(log.Message__c.length() <= 32000, 'Message should be truncated to field limit.');
    }

    @IsTest
    static void testBufferLimitDoesNotAutoFlush() {
        ErrorLogger.clearBuffer();
        for (Integer i = 0; i < 1000; i++) {
            ErrorLogger.log('TestClass', 'testMethod' + i, null, 'TEST_ERROR', 'Message ' + i);
        }
        System.assertEquals(1000, ErrorLogger.getBufferSize());
        ErrorLogger.log('TestClass', 'overflow', null, 'OVERFLOW', 'This should be skipped');
        System.assertEquals(1000, ErrorLogger.getBufferSize());
    }
}