public class CredentialingAPIMockImpl implements ICredentialingAPI {
    public enum ResponseType { LOW_RISK, HIGH_RISK, API_ERROR, TIMEOUT, UNEXPECTED_EXCEPTION }
    private ResponseType defaultResponse;
    private Map<String, ResponseType> responseByNpi = new Map<String, ResponseType>();

    public CredentialingAPIMockImpl() { this(ResponseType.LOW_RISK); }
    public CredentialingAPIMockImpl(ResponseType defaultResponse) {
        this.defaultResponse = defaultResponse == null ? ResponseType.LOW_RISK : defaultResponse;
    }
    public void setResponseForNpi(String npi, ResponseType type) {
        if (!String.isBlank(npi) && type != null) {
            this.responseByNpi.put(npi, type);
        }
    }

    public List<ProviderVerificationResult> verifyProviders(
        List<ProviderVerificationRequest> requests
    ) {
        List<ProviderVerificationResult> results = new List<ProviderVerificationResult>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }
        for (ProviderVerificationRequest req : requests) {
            ProviderVerificationResult res = new ProviderVerificationResult();
            res.npiNumber = req == null ? null : req.npiNumber;
            res.providerApplicationId = req == null ? null : req.providerApplicationId;

            if (req == null || String.isBlank(req.npiNumber)) {
                res.isSuccess = false;
                res.errorMessage = 'INVALID_REQUEST: Missing NPI number';
                results.add(res);
                continue;
            }

            ResponseType type = responseByNpi.containsKey(req.npiNumber)
                ? responseByNpi.get(req.npiNumber) : defaultResponse;

            switch on type {
                when LOW_RISK {
                    res.isSuccess = true;
                    res.verificationId = 'V-' + req.npiNumber;
                    res.riskCategory = 'Low Risk';
                    res.licenseActive = true;
                }
                when HIGH_RISK {
                    res.isSuccess = true;
                    res.verificationId = 'V-' + req.npiNumber;
                    res.riskCategory = 'High Risk';
                    res.licenseActive = false;
                }
                when API_ERROR {
                    res.isSuccess = false;
                    res.errorMessage = 'HTTP_500: Simulated API error';
                }
                when TIMEOUT {
                    res.isSuccess = false;
                    res.errorMessage = 'CALLOUT_TIMEOUT: Simulated timeout';
                }
                when UNEXPECTED_EXCEPTION {
                    throw new MockCalloutException('Simulated unexpected API client exception');
                }
            }
            results.add(res);
        }
        return results;
    }

    public class MockCalloutException extends Exception {}
}