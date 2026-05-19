/**
 * Contract for provider credentialing verification clients.
 *
 * Implementations may call an external HTTP API, return mock responses for tests,
 * or later use a bulk vendor endpoint. The service layer depends on this
 * interface to avoid coupling business logic to HTTP mechanics.
 */
public interface ICredentialingAPI {

    /**
     * Verifies one or more provider applications.
     *
     * Implementations should return one ProviderVerificationResult per request.
     * Callout-based implementations must respect Salesforce callout limits.
     */
    List<ProviderVerificationResult> verifyProviders(
        List<ProviderVerificationRequest> requests
    );
}