@IsTest
public class CredentialingAPIHttpMock implements HttpCalloutMock {

    public class MockCalloutException extends Exception {}

    public enum MockMode { SUCCESS_LOW, SUCCESS_HIGH, ERROR_500, TIMEOUT }

    private MockMode mode;

    public CredentialingAPIHttpMock(MockMode mode) {
        if (mode == null) {
            throw new MockCalloutException('Mock mode is required.');
        }
        this.mode = mode;
    }

    public HttpResponse respond(HttpRequest req) {
        if (mode == MockMode.TIMEOUT) {
            throw new MockCalloutException('Read timed out');
        }

        HttpResponse res = new HttpResponse();

        if (mode == MockMode.ERROR_500) {
            res.setStatusCode(500);
            res.setStatus('Internal Server Error');
            res.setBody('{"error": "Internal Server Error"}');
            return res;
        }

        res.setStatusCode(200);
        res.setStatus('OK');

        if (mode == MockMode.SUCCESS_LOW) {
            res.setBody('{"verification_id": "V-100", "risk_category": "Low Risk", "license_active": true}');
        } else if (mode == MockMode.SUCCESS_HIGH) {
            res.setBody('{"verification_id": "V-200", "risk_category": "High Risk", "license_active": false}');
        }

        return res;
    }
}