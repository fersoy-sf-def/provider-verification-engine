public class ProviderVerificationResult {
    public String npiNumber;
    public Id providerApplicationId;
    public String verificationId;
    public String riskCategory;
    public Boolean licenseActive;
    public Boolean isSuccess = false;
    public String errorMessage;

    public ProviderVerificationResult() {}

    public ProviderVerificationResult(String npiNumber, Id providerApplicationId) {
        this.npiNumber = npiNumber;
        this.providerApplicationId = providerApplicationId;
    }
}