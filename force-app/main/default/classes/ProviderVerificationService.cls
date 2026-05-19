public class ProviderVerificationService {
    private final ICredentialingAPI apiClient;

    public ProviderVerificationService() {
        this(new CredentialingAPIImpl());
    }

    public ProviderVerificationService(ICredentialingAPI apiClient) {
        this.apiClient = apiClient;
    }

    public ProcessingContext processVerifications(List<Provider_Application__c> applications) {
        ProcessingContext ctx = new ProcessingContext();

        if (applications == null || applications.isEmpty()) {
            return ctx;
        }

        Map<Id, Provider_Application__c> appById =
            new Map<Id, Provider_Application__c>(applications);

        List<ProviderVerificationRequest> requests = new List<ProviderVerificationRequest>();
        for (Provider_Application__c app : applications) {
            if (ProviderApplicationDomain.isEligibleForVerification(app)) {
                requests.add(new ProviderVerificationRequest(app.Id, app.NPI_Number__c));
            }
        }

        if (requests.isEmpty()) {
            return ctx;
        }

        List<ProviderVerificationResult> results;
        try {
            results = apiClient.verifyProviders(requests);
        } catch (Exception ex) {
            for (Provider_Application__c app : applications) {
                markFailed(app, 'API service unavailable: ' + ex.getMessage());
                ctx.applicationsToUpdate.add(app);
            }
            ErrorLogger.log('ProviderVerificationService', 'processVerifications', null, 'API_TOTAL_FAILURE', ex);
            return ctx;
        }

        if (results == null || results.isEmpty()) {
            for (Provider_Application__c app : applications) {
                markFailed(app, 'Credentialing API returned no results.');
                ctx.applicationsToUpdate.add(app);
            }
            ErrorLogger.log('ProviderVerificationService', 'processVerifications', null, 'API_EMPTY_RESPONSE', 'Credentialing API returned no results.');
            return ctx;
        }

        for (ProviderVerificationResult result : results) {
            Provider_Application__c app = appById.get(result.providerApplicationId);
            if (app == null) {
                ErrorLogger.log('ProviderVerificationService', 'processVerifications', null, 'UNMATCHED_API_RESULT', 'No Provider Application found for API result. NPI=' + result.npiNumber);
                continue;
            }

            if (result.isSuccess != true) {
                markFailed(app, result.errorMessage);
                ctx.applicationsToUpdate.add(app);
                ErrorLogger.log('ProviderVerificationService', 'processVerifications', app.Id, 'API_FAILURE', result.errorMessage);
                continue;
            }

            String riskTier = ProviderApplicationDomain.mapRiskTier(result.riskCategory);
            if (String.isBlank(riskTier)) {
                markFailed(app, 'Unknown risk category returned by API: ' + result.riskCategory);
                ctx.applicationsToUpdate.add(app);
                ErrorLogger.log('ProviderVerificationService', 'processVerifications', app.Id, 'INVALID_RISK_CATEGORY', 'Unknown risk category: ' + result.riskCategory);
                continue;
            }

            applySuccessfulVerification(app, result, riskTier);

            if (ProviderApplicationDomain.RISK_LOW.equals(riskTier)) {
                Account acc = buildAccount(app);
                Contact con = buildContact(app);
                ctx.accountsToInsert.add(acc);
                ctx.contactsToInsert.add(con);
                ctx.applicationToAccountMap.put(app.Id, acc);
                ctx.applicationToContactMap.put(app.Id, con);
            } else if (ProviderApplicationDomain.RISK_HIGH.equals(riskTier)) {
                ctx.eventsToPublish.add(buildVerificationEvent(app, result));
            }

            ctx.applicationsToUpdate.add(app);
        }

        return ctx;
    }

    private static void applySuccessfulVerification(
        Provider_Application__c app,
        ProviderVerificationResult result,
        String riskTier
    ) {
        app.Status__c = ProviderApplicationDomain.STATUS_VERIFIED;
        app.Risk_Tier__c = riskTier;
        app.Verification_ID__c = result.verificationId;
        app.API_Response_JSON__c = JSON.serialize(result);
        app.Processed_Timestamp__c = System.now();
        app.Error_Details__c = null;
    }

    private static void markFailed(Provider_Application__c app, String errorMessage) {
        app.Status__c = ProviderApplicationDomain.STATUS_FAILED;
        app.Risk_Tier__c = null;
        app.Error_Details__c = String.isBlank(errorMessage)
            ? 'Unknown verification failure.'
            : errorMessage;
        app.Processed_Timestamp__c = System.now();
        app.Retry_Count__c = app.Retry_Count__c == null
            ? 1
            : app.Retry_Count__c + 1;
    }

    private static Account buildAccount(Provider_Application__c app) {
        return new Account(Name = buildAccountName(app));
    }

    private static Contact buildContact(Provider_Application__c app) {
        return new Contact(
            FirstName = app.First_Name__c,
            LastName = String.isBlank(app.Last_Name__c)
                ? 'Unknown Provider'
                : app.Last_Name__c,
            Email = app.Email__c
        );
    }

    private static Verification_Event__e buildVerificationEvent(
        Provider_Application__c app,
        ProviderVerificationResult result
    ) {
        return new Verification_Event__e(
            Provider_Application_ID__c = app.Id,
            NPI_Number__c = app.NPI_Number__c,
            Risk_Category__c = result.riskCategory,
            Verification_ID__c = result.verificationId
        );
    }

    private static String buildAccountName(Provider_Application__c app) {
        List<String> nameParts = new List<String>();
        if (!String.isBlank(app.Last_Name__c)) {
            nameParts.add(app.Last_Name__c);
        }
        if (!String.isBlank(app.First_Name__c)) {
            nameParts.add(app.First_Name__c);
        }
        String providerName = nameParts.isEmpty()
            ? 'Unknown Provider'
            : String.join(nameParts, ', ');
        return providerName + ' (' + app.NPI_Number__c + ')';
    }

    public class ProcessingContext {
        public List<Provider_Application__c> applicationsToUpdate = new List<Provider_Application__c>();
        public List<Account> accountsToInsert = new List<Account>();
        public List<Contact> contactsToInsert = new List<Contact>();
        public List<Verification_Event__e> eventsToPublish = new List<Verification_Event__e>();
        public Map<Id, Account> applicationToAccountMap = new Map<Id, Account>();
        public Map<Id, Contact> applicationToContactMap = new Map<Id, Contact>();
    }
}