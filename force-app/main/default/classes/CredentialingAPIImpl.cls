public class CredentialingAPIImpl implements ICredentialingAPI {
    private static final String DEFAULT_ENDPOINT = 'https://api.credentialing.example.com/v1/verify';
    private static final Integer DEFAULT_TIMEOUT = 120000;
    private static final Integer MAX_CALLOUTS_PER_TRANSACTION = 100;
    private static final Integer MAX_ERROR_BODY_LENGTH = 500;

    public class CredentialingAPIException extends Exception {}

    public List<ProviderVerificationResult> verifyProviders(
        List<ProviderVerificationRequest> requests
    ) {
        List<ProviderVerificationResult> results = new List<ProviderVerificationResult>();

        if (requests == null || requests.isEmpty()) {
            return results;
        }

        if (requests.size() > MAX_CALLOUTS_PER_TRANSACTION) {
            throw new CredentialingAPIException(
                'CredentialingAPIImpl cannot process more than ' +
                MAX_CALLOUTS_PER_TRANSACTION +
                ' records in one transaction because each record requires one callout.'
            );
        }

        API_Configuration__mdt config = getActiveConfiguration();
        Http http = new Http();

        for (ProviderVerificationRequest req : requests) {
            ProviderVerificationResult result = new ProviderVerificationResult();
            result.npiNumber = req.npiNumber;
            result.providerApplicationId = req.providerApplicationId;

            try {
                HttpRequest httpReq = buildRequest(req.npiNumber, config);
                HttpResponse httpRes = http.send(httpReq);
                parseResponse(result, httpRes);
            } catch (System.CalloutException ex) {
                result.isSuccess = false;
                result.errorMessage = 'CALLOUT_EXCEPTION: ' + ex.getMessage();
            } catch (Exception ex) {
                result.isSuccess = false;
                result.errorMessage = ex.getTypeName() + ': ' + ex.getMessage();
            }

            results.add(result);
        }

        return results;
    }

    private HttpRequest buildRequest(String npi, API_Configuration__mdt config) {
        HttpRequest req = new HttpRequest();

        String endpoint = String.isBlank(config.Endpoint_URL__c)
            ? DEFAULT_ENDPOINT
            : config.Endpoint_URL__c;

        Integer timeoutMs = config.Timeout_Milliseconds__c == null
            ? DEFAULT_TIMEOUT
            : Integer.valueOf(config.Timeout_Milliseconds__c);

        req.setEndpoint(endpoint + '?npi=' + EncodingUtil.urlEncode(npi, 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(timeoutMs);

        return req;
    }

    private void parseResponse(ProviderVerificationResult result, HttpResponse res) {
        if (res == null) {
            result.isSuccess = false;
            result.errorMessage = 'NULL_HTTP_RESPONSE';
            return;
        }

        String responseBody = res.getBody();

        if (res.getStatusCode() != 200) {
            result.isSuccess = false;
            result.errorMessage =
                'HTTP_' +
                res.getStatusCode() +
                ': ' +
                abbreviate(responseBody, MAX_ERROR_BODY_LENGTH);
            return;
        }

        try {
            Map<String, Object> body =
                (Map<String, Object>) JSON.deserializeUntyped(responseBody);

            result.verificationId = (String) body.get('verification_id');
            result.riskCategory = (String) body.get('risk_category');
            result.licenseActive = (Boolean) body.get('license_active');

            if (String.isBlank(result.verificationId) ||
                String.isBlank(result.riskCategory) ||
                result.licenseActive == null) {
                result.isSuccess = false;
                result.errorMessage = 'INVALID_API_RESPONSE: Missing required fields.';
                return;
            }

            result.isSuccess = true;
        } catch (Exception ex) {
            result.isSuccess = false;
            result.errorMessage =
                'INVALID_JSON_RESPONSE: ' +
                abbreviate(responseBody, MAX_ERROR_BODY_LENGTH);
        }
    }

    private API_Configuration__mdt getActiveConfiguration() {
        List<API_Configuration__mdt> configs = [
            SELECT Endpoint_URL__c, Timeout_Milliseconds__c
            FROM API_Configuration__mdt
            WHERE Active__c = TRUE
            LIMIT 1
        ];

        if (configs.isEmpty()) {
            API_Configuration__mdt fallback = new API_Configuration__mdt();
            fallback.Endpoint_URL__c = DEFAULT_ENDPOINT;
            fallback.Timeout_Milliseconds__c = DEFAULT_TIMEOUT;
            return fallback;
        }

        return configs[0];
    }

    private static String abbreviate(String value, Integer maxLength) {
        if (String.isBlank(value)) {
            return '';
        }
        return value.length() <= maxLength
            ? value
            : value.substring(0, maxLength);
    }
}