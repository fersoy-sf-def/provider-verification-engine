public class ProviderVerificationRequest {
    public String npiNumber;
    public Id providerApplicationId;

    public ProviderVerificationRequest() {}

    public ProviderVerificationRequest(Id providerApplicationId, String npiNumber) {
        this.providerApplicationId = providerApplicationId;
        this.npiNumber = npiNumber;
    }
}