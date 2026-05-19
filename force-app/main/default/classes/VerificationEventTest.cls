@IsTest
private class VerificationEventTest {

    @IsTest
    static void testEventCreatesComplianceTask() {
        ProviderApplicationTriggerHandler.bypassTrigger = true;

        Provider_Application__c app = new Provider_Application__c(
            First_Name__c = 'Event',
            Last_Name__c = 'Test',
            Email__c = 'event@test.com',
            NPI_Number__c = '9000000001',
            Status__c = 'Verified',
            Risk_Tier__c = 'High'
        );
        insert app;

        Verification_Event__e eventRecord = new Verification_Event__e(
            Provider_Application_ID__c = app.Id,
            NPI_Number__c = '9000000001',
            Risk_Category__c = 'High Risk',
            Verification_ID__c = 'V-999'
        );

        Test.startTest();
        Database.SaveResult sr = EventBus.publish(eventRecord);
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals(true, sr.isSuccess(), 'Platform Event should publish successfully.');

        List<Compliance_Task__c> tasks = [
            SELECT Id, Subject__c, Provider_Application__c
            FROM Compliance_Task__c
            WHERE Provider_Application__c = :app.Id
        ];
        System.assertEquals(1, tasks.size(), 'One Compliance Task should be created.');
        System.assertEquals(app.Id, tasks[0].Provider_Application__c);
        System.assert(tasks[0].Subject__c.contains('9000000001'), 'Subject should include NPI.');
    }

    @IsTest
    static void testBulkEventsCreateMultipleTasks() {
        ProviderApplicationTriggerHandler.bypassTrigger = true;

        List<Provider_Application__c> apps = new List<Provider_Application__c>();
        for (Integer i = 0; i < 50; i++) {
            apps.add(new Provider_Application__c(
                First_Name__c = 'Bulk',
                Last_Name__c = 'Event' + i,
                Email__c = 'bulk.event' + i + '@test.com',
                NPI_Number__c = String.valueOf(9100000000L + i),
                Status__c = 'Verified',
                Risk_Tier__c = 'High'
            ));
        }
        insert apps;

        List<Verification_Event__e> events = new List<Verification_Event__e>();
        Set<Id> appIds = new Set<Id>();
        for (Provider_Application__c app : apps) {
            appIds.add(app.Id);
            events.add(new Verification_Event__e(
                Provider_Application_ID__c = app.Id,
                NPI_Number__c = app.NPI_Number__c,
                Risk_Category__c = 'High Risk',
                Verification_ID__c = 'V-' + app.NPI_Number__c
            ));
        }

        Test.startTest();
        List<Database.SaveResult> results = EventBus.publish(events);
        Test.getEventBus().deliver();
        Test.stopTest();

        Integer successCount = 0;
        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) successCount++;
        }
        System.assertEquals(50, successCount, 'All Platform Events should publish successfully.');

        Integer taskCount = [
            SELECT COUNT()
            FROM Compliance_Task__c
            WHERE Provider_Application__c IN :appIds
        ];
        System.assertEquals(50, taskCount, 'One Compliance Task should be created per event.');
    }

    @IsTest
    static void testEventWithoutProviderApplicationIdDoesNotCreateTask() {
        Verification_Event__e eventRecord = new Verification_Event__e(
            Provider_Application_ID__c = null,
            NPI_Number__c = '9999999999',
            Risk_Category__c = 'High Risk',
            Verification_ID__c = 'V-MISSING'
        );

        Test.startTest();
        Database.SaveResult sr = EventBus.publish(eventRecord);
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals(true, sr.isSuccess(), 'Event publish itself should succeed.');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Compliance_Task__c],
            'Invalid event without Provider Application Id should not create a Compliance Task.'
        );
    }
}