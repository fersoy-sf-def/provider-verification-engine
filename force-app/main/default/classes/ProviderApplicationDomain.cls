public class ProviderApplicationDomain {
    public static final String STATUS_NEW = 'New';
    public static final String STATUS_VERIFIED = 'Verified';
    public static final String STATUS_FAILED = 'Failed';
    public static final String RISK_LOW = 'Low';
    public static final String RISK_HIGH = 'High';
    public static final String API_RISK_LOW = 'Low Risk';
    public static final String API_RISK_HIGH = 'High Risk';

    public static List<Id> filterEligibleForVerification(List<Provider_Application__c> records) {
        List<Id> eligibleIds = new List<Id>();
        if (records == null || records.isEmpty()) {
            return eligibleIds;
        }
        for (Provider_Application__c app : records) {
            if (isEligibleForVerification(app)) {
                eligibleIds.add(app.Id);
            }
        }
        return eligibleIds;
    }

    public static Boolean isEligibleForVerification(Provider_Application__c app) {
        return app != null &&
            STATUS_NEW.equals(app.Status__c) &&
            isValidNpi(app.NPI_Number__c);
    }

    public static Boolean isValidNpi(String npi) {
        if (String.isBlank(npi)) {
            return false;
        }
        String normalizedNpi = npi.trim();
        return normalizedNpi.length() == 10 && normalizedNpi.isNumeric();
    }

    public static Boolean isLowRisk(String apiRiskCategory) {
        return API_RISK_LOW.equalsIgnoreCase(apiRiskCategory);
    }

    public static Boolean isHighRisk(String apiRiskCategory) {
        return API_RISK_HIGH.equalsIgnoreCase(apiRiskCategory);
    }

    public static String mapRiskTier(String apiRiskCategory) {
        if (isLowRisk(apiRiskCategory)) {
            return RISK_LOW;
        }
        if (isHighRisk(apiRiskCategory)) {
            return RISK_HIGH;
        }
        return null;
    }
}