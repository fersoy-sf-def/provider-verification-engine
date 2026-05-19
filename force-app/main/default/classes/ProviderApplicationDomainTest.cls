@IsTest
private class ProviderApplicationDomainTest {

    @IsTest
    static void testValidNpi() {
        System.assertEquals(true, ProviderApplicationDomain.isValidNpi('1234567890'));
        System.assertEquals(true, ProviderApplicationDomain.isValidNpi(' 1234567890 '));
    }

    @IsTest
    static void testInvalidNpi() {
        System.assertEquals(false, ProviderApplicationDomain.isValidNpi(null));
        System.assertEquals(false, ProviderApplicationDomain.isValidNpi(''));
        System.assertEquals(false, ProviderApplicationDomain.isValidNpi('123'));
        System.assertEquals(false, ProviderApplicationDomain.isValidNpi('123456789A'));
    }

    @IsTest
    static void testRiskMapping() {
        System.assertEquals('Low', ProviderApplicationDomain.mapRiskTier('Low Risk'));
        System.assertEquals('High', ProviderApplicationDomain.mapRiskTier('High Risk'));
        System.assertEquals(null, ProviderApplicationDomain.mapRiskTier('Unknown'));
    }

    @IsTest
    static void testIsLowRiskAndIsHighRisk() {
        System.assertEquals(true, ProviderApplicationDomain.isLowRisk('Low Risk'));
        System.assertEquals(true, ProviderApplicationDomain.isLowRisk('low risk'));
        System.assertEquals(false, ProviderApplicationDomain.isLowRisk('High Risk'));
        System.assertEquals(true, ProviderApplicationDomain.isHighRisk('High Risk'));
        System.assertEquals(true, ProviderApplicationDomain.isHighRisk('high risk'));
        System.assertEquals(false, ProviderApplicationDomain.isHighRisk('Low Risk'));
    }

    @IsTest
    static void testFilterEligibleForVerification() {
        List<Provider_Application__c> apps = new List<Provider_Application__c>{
            new Provider_Application__c(Status__c = 'New', NPI_Number__c = '1234567890'),
            new Provider_Application__c(Status__c = 'Verified', NPI_Number__c = '1234567890'),
            new Provider_Application__c(Status__c = 'New', NPI_Number__c = 'ABC')
        };
        List<Id> eligibleIds = ProviderApplicationDomain.filterEligibleForVerification(apps);
        System.assertEquals(1, eligibleIds.size(), 'Only the first record is eligible');
    }

    @IsTest
    static void testFilterEligibleWithNullList() {
        List<Id> eligibleIds = ProviderApplicationDomain.filterEligibleForVerification(null);
        System.assertEquals(0, eligibleIds.size());
    }

    @IsTest
    static void testIsEligibleForVerification() {
        Provider_Application__c eligible = new Provider_Application__c(
            Status__c = 'New', NPI_Number__c = '1234567890'
        );
        System.assertEquals(true, ProviderApplicationDomain.isEligibleForVerification(eligible));

        Provider_Application__c notEligible = new Provider_Application__c(
            Status__c = 'Verified', NPI_Number__c = '1234567890'
        );
        System.assertEquals(false, ProviderApplicationDomain.isEligibleForVerification(notEligible));

        System.assertEquals(false, ProviderApplicationDomain.isEligibleForVerification(null));
    }
}