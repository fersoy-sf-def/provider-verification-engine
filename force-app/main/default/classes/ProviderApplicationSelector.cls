public with sharing class ProviderApplicationSelector {

    public static List<Provider_Application__c> selectById(Set<Id> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) {
            return new List<Provider_Application__c>();
        }

        return [
            SELECT Id,
                   First_Name__c,
                   Last_Name__c,
                   Email__c,
                   NPI_Number__c,
                   Status__c,
                   Risk_Tier__c,
                   Verification_ID__c,
                   API_Response_JSON__c,
                   Error_Details__c,
                   Processed_Timestamp__c,
                   Retry_Count__c
            FROM Provider_Application__c
            WHERE Id IN :recordIds
        ];
    }
}