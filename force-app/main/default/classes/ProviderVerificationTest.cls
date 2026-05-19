@IsTest
private class ProviderVerificationTest {

    // ========================
    // SERVICE LAYER TESTS
    // ========================

    @IsTest
    static void testLowRiskPath_ProducesCorrectContext() {
        ProviderApplicationTriggerHandler.bypassTrigger = true;
        Provider_Application__c app = createProvider('John', 'Doe', 'john@example.com', '1000000001');
        insert app;

        CredentialingAPIMockImpl mock = new CredentialingAPIMockImpl(CredentialingAPIMockImpl.ResponseType.LOW_RISK);
        ProviderVerificationService service = new ProviderVerificationService(mock);

        List<Provider_Application__c> apps = ProviderApplicationSelector.selectById(new Set<Id>{app.Id});
        ProviderVerificationService.ProcessingContext ctx = service.processVerifications(apps);

        // Assert ProcessingContext contains correct DML-ready collections
        System.assertEquals(1, ctx.accountsToInsert.size(), 'Should prepare one Account');
        System.assertEquals(1, ctx.contactsToInsert.size(), 'Should prepare one Contact');
        System.assertEquals(1, ctx.applicationsToUpdate.size(), 'Should prepare one app update');
        System.assertEquals('Verified', ctx.applicationsToUpdate[0].Status__c);
        System.assertEquals('Low', ctx.applicationsToUpdate[0].Risk_Tier__c);
        System.assertEquals('V-1000000001', ctx.applicationsToUpdate[0].Verification_ID__c);
    }

    @IsTest
    static void testHighRiskPath_ProducesEventAndCorrectContext() {
        ProviderApplicationTriggerHandler.bypassTrigger = true;
        Provider_Application__c app = createProvider('Jane', 'Smith', 'jane@example.com', '2000000002');
        insert app;

        CredentialingAPIMockImpl mock = new CredentialingAPIMockImpl(CredentialingAPIMockImpl.ResponseType.HIGH_RISK);
        ProviderVerificationService service = new ProviderVerificationService(mock);

        List<Provider_Application__c> apps = ProviderApplicationSelector.selectById(new Set<Id>{app.Id});
        ProviderVerificationService.ProcessingContext ctx = service.processVerifications(apps);

        System.assertEquals(0, ctx.accountsToInsert.size(), 'High risk should not create Account');
        System.assertEquals(0, ctx.contactsToInsert.size(), 'High risk should not create Contact');
        System.assertEquals(1, ctx.eventsToPublish.size(), 'Should prepare one Platform Event');
        System.assertEquals(1, ctx.applicationsToUpdate.size());
        System.assertEquals('Verified', ctx.applicationsToUpdate[0].Status__c);
        System.assertEquals('High', ctx.applicationsToUpdate[0].Risk_Tier__c);
    }

    @IsTest
    static void testHighRiskPath_PublishesPlatformEvent_CreatesComplianceTask() {
        ProviderApplicationTriggerHandler.bypassTrigger = true;
        Provider_Application__c app = createProvider('Jane', 'Smith', 'jane@example.com', '2000000002');
        insert app;

        CredentialingAPIMockImpl mock = new CredentialingAPIMockImpl(CredentialingAPIMockImpl.ResponseType.HIGH_RISK);
        ProviderVerificationService service = new ProviderVerificationService(mock);

        List<Provider_Application__c> apps = ProviderApplicationSelector.selectById(new Set<Id>{app.Id});
        ProviderVerificationService.ProcessingContext ctx = service.processVerifications(apps);

        Test.startTest();
        if (!ctx.applicationsToUpdate.isEmpty()) {
            update ctx.applicationsToUpdate;
        }
        if (!ctx.eventsToPublish.isEmpty()) {
            EventBus.publish(ctx.eventsToPublish);
            Test.getEventBus().deliver();
        }
        Test.stopTest();

        Provider_Application__c updatedApp = [
            SELECT Status__c, Risk_Tier__c FROM Provider_Application__c WHERE Id = :app.Id
        ];
        System.assertEquals('Verified', updatedApp.Status__c);
        System.assertEquals('High', updatedApp.Risk_Tier__c);

        List<Compliance_Task__c> tasks = [
            SELECT Id, Subject__c FROM Compliance_Task__c WHERE Provider_Application__c = :app.Id
        ];
        System.assertEquals(1, tasks.size(), 'Compliance Task should be created by event subscriber');
    }

    @IsTest
    static void testApiTotalFailure_MarksAllFailed() {
        ProviderApplicationTriggerHandler.bypassTrigger = true;
        List<Provider_Application__c> apps = new List<Provider_Application__c>();
        for (Integer i = 0; i < 5; i++) {
            apps.add(createProvider('Fail', 'Test' + i, 'fail' + i + '@test.com', '300000000' + i));
        }
        insert apps;

        CredentialingAPIMockImpl mock = new CredentialingAPIMockImpl(CredentialingAPIMockImpl.ResponseType.UNEXPECTED_EXCEPTION);
        ProviderVerificationService service = new ProviderVerificationService(mock);

        List<Provider_Application__c> queriedApps = ProviderApplicationSelector.selectById(
            new Map<Id, Provider_Application__c>(apps).keySet()
        );

        ProviderVerificationService.ProcessingContext ctx = service.processVerifications(queriedApps);

        // Assert all marked Failed in context
        System.assertEquals(5, ctx.applicationsToUpdate.size());
        for (Provider_Application__c app : ctx.applicationsToUpdate) {
            System.assertEquals('Failed', app.Status__c);
            System.assert(app.Error_Details__c.contains('API service unavailable'));
        }
    }

    @IsTest
    static void testPartialDmlFailure_OtherRecordsSucceed() {
        ProviderApplicationTriggerHandler.bypassTrigger = true;
        Provider_Application__c app1 = createProvider('Good', 'Record', 'good@test.com', '4000000001');
        Provider_Application__c app2 = createProvider('Bad', 'Record', 'bad@test.com', '4000000002');
        insert new List<Provider_Application__c>{app1, app2};

        CredentialingAPIMockImpl mock = new CredentialingAPIMockImpl(CredentialingAPIMockImpl.ResponseType.LOW_RISK);
        ProviderVerificationService service = new ProviderVerificationService(mock);

        List<Provider_Application__c> apps = ProviderApplicationSelector.selectById(new Set<Id>{app1.Id, app2.Id});
        ProviderVerificationService.ProcessingContext ctx = service.processVerifications(apps);

        // Force first Account to fail by nulling required Name
        ctx.accountsToInsert[0].Name = null;

        Test.startTest();
        List<Database.SaveResult> results = Database.insert(ctx.accountsToInsert, false);
        Test.stopTest();

        System.assertEquals(false, results[0].isSuccess(), 'First Account should fail (Name is required)');
        System.assertEquals(true, results[1].isSuccess(), 'Second Account should succeed');
    }

    @IsTest
    static void testMixedResults_LowHighAndFailure() {
        ProviderApplicationTriggerHandler.bypassTrigger = true;
        Provider_Application__c lowApp = createProvider('Low', 'Risk', 'low@test.com', '1111111111');
        Provider_Application__c highApp = createProvider('High', 'Risk', 'high@test.com', '2222222222');
        Provider_Application__c failApp = createProvider('Fail', 'Test', 'fail@test.com', '3333333333');
        insert new List<Provider_Application__c>{lowApp, highApp, failApp};

        CredentialingAPIMockImpl mock = new CredentialingAPIMockImpl();
        mock.setResponseForNpi('1111111111', CredentialingAPIMockImpl.ResponseType.LOW_RISK);
        mock.setResponseForNpi('2222222222', CredentialingAPIMockImpl.ResponseType.HIGH_RISK);
        mock.setResponseForNpi('3333333333', CredentialingAPIMockImpl.ResponseType.API_ERROR);

        ProviderVerificationService service = new ProviderVerificationService(mock);
        List<Provider_Application__c> apps = ProviderApplicationSelector.selectById(
            new Set<Id>{lowApp.Id, highApp.Id, failApp.Id}
        );
        ProviderVerificationService.ProcessingContext ctx = service.processVerifications(apps);

        // Low risk: Account + Contact prepared
        System.assertEquals(1, ctx.accountsToInsert.size());
        System.assertEquals(1, ctx.contactsToInsert.size());

        // High risk: Event prepared
        System.assertEquals(1, ctx.eventsToPublish.size());

        // Failed: no Account, no Contact, no Event for failApp
        // All 3 apps in applicationsToUpdate
        System.assertEquals(3, ctx.applicationsToUpdate.size());
    }

    // ========================
    // QUEUEABLE TESTS
    // ========================

    @IsTest
    static void testBulkProcessing_RecordsChunked() {
        ProviderApplicationTriggerHandler.bypassTrigger = true;
        List<Provider_Application__c> apps = new List<Provider_Application__c>();
        for (Integer i = 0; i < 200; i++) {
            apps.add(createProvider('Bulk', 'User' + i, 'bulk' + i + '@test.com', String.valueOf(5000000000L + i)));
        }
        insert apps;

        List<Id> allIds = new List<Id>();
        for (Provider_Application__c app : apps) allIds.add(app.Id);

        CredentialingAPIMockImpl mock = new CredentialingAPIMockImpl(CredentialingAPIMockImpl.ResponseType.LOW_RISK);

        Test.startTest();
        ProviderVerificationQueueable q = new ProviderVerificationQueueable(allIds, 100, mock);
        q.execute(null);
        Test.stopTest();

        // Verify all 200 records were processed (100 in first chunk + 100 chained)
        List<Provider_Application__c> processed = [
            SELECT Status__c, Risk_Tier__c FROM Provider_Application__c WHERE Id IN :allIds
        ];
        Integer verifiedCount = 0;
        for (Provider_Application__c app : processed) {
            if (app.Status__c == 'Verified') verifiedCount++;
        }
        System.assertEquals(200, verifiedCount, 'All 200 bulk records should be Verified');
    }

    @IsTest
    static void testQueueableSplitsCurrentAndRemainingChunks() {
        ProviderApplicationTriggerHandler.bypassTrigger = true;
        List<Provider_Application__c> apps = new List<Provider_Application__c>();
        for (Integer i = 0; i < 150; i++) {
            apps.add(createProvider('Chunk', 'Test' + i, 'chunk' + i + '@test.com', String.valueOf(6000000000L + i)));
        }
        insert apps;

        List<Id> allIds = new List<Id>();
        for (Provider_Application__c app : apps) allIds.add(app.Id);

        CredentialingAPIMockImpl mock = new CredentialingAPIMockImpl(CredentialingAPIMockImpl.ResponseType.LOW_RISK);

        Test.startTest();
        ProviderVerificationQueueable q = new ProviderVerificationQueueable(allIds, 100, mock);
        q.execute(null);
        Test.stopTest();

        // Verify chained job was created for remaining 50
        List<AsyncApexJob> jobs = [
            SELECT Id FROM AsyncApexJob
            WHERE JobType = 'Queueable' AND ApexClass.Name = 'ProviderVerificationQueueable'
        ];
        System.assert(jobs.size() >= 1, 'Should enqueue at least one Queueable job');
    }

    // ========================
    // HTTP INTEGRATION TEST
    // ========================

    @IsTest
    static void testHttpIntegration_LowRiskResponse() {
        Test.setMock(HttpCalloutMock.class, new CredentialingAPIHttpMock(CredentialingAPIHttpMock.MockMode.SUCCESS_LOW));
        CredentialingAPIImpl api = new CredentialingAPIImpl();
        ProviderVerificationRequest req = new ProviderVerificationRequest();
        req.npiNumber = '1234567890';
        req.providerApplicationId = null;

        Test.startTest();
        List<ProviderVerificationResult> results = api.verifyProviders(new List<ProviderVerificationRequest>{req});
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].isSuccess);
        System.assertEquals('Low Risk', results[0].riskCategory);
    }

    // ========================
    // END-TO-END TRIGGER TEST
    // ========================

    @IsTest
    static void testEndToEnd_LowRiskViaTrigger_WithHttpMock() {
        Test.setMock(HttpCalloutMock.class, new CredentialingAPIHttpMock(CredentialingAPIHttpMock.MockMode.SUCCESS_LOW));

        Provider_Application__c app = createProvider('EndToEnd', 'Low', 'e2e@low.com', '7000000001');

        Test.startTest();
        insert app;
        Test.stopTest();

        Provider_Application__c updated = [
            SELECT Status__c, Risk_Tier__c FROM Provider_Application__c WHERE Id = :app.Id
        ];
        System.assertEquals('Verified', updated.Status__c);
        System.assertEquals('Low', updated.Risk_Tier__c);
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Name LIKE '%EndToEnd%']);
    }

    // ========================
    // HELPERS
    // ========================

    private static Provider_Application__c createProvider(String firstName, String lastName, String email, String npi) {
        return new Provider_Application__c(
            First_Name__c = firstName,
            Last_Name__c = lastName,
            Email__c = email,
            NPI_Number__c = npi,
            Status__c = 'New'
        );
    }
}