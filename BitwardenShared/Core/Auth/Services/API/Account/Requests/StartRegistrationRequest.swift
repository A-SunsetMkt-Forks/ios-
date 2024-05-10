import Foundation
import Networking

// MARK: - StartRegistrationRequestError

/// Errors that can occur when sending a `StartRegistrationRequest`.
enum StartRegistrationRequestError: Error, Equatable {
    /// Captcha is required when creating an account.
    ///
    /// - Parameter hCaptchaSiteCode: The site code to use when authenticating with hCaptcha.
    case captchaRequired(hCaptchaSiteCode: String)
}

// MARK: - StartRegistrationRequest

/// The API request sent when starting the account creation.
///
struct StartRegistrationRequest: Request {
    typealias Response = StartRegistrationResponseModel
    typealias Body = StartRegistrationRequestModel

    /// The body of this request.
    var body: StartRegistrationRequestModel?

    /// The HTTP method for this request.
    let method: HTTPMethod = .post

    /// The URL path for this request.
    var path: String = "/accounts/send-verification-email"

    /// Creates a new `CreateAccountRequest` instance.
    ///
    /// - Parameter body: The body of the request.
    ///
    init(body: StartRegistrationRequestModel) {
        self.body = body
    }

    // MARK: Methods

    func validate(_ response: HTTPResponse) throws {
        switch response.statusCode {
        case 400 ..< 500:
            guard let errorResponse = try? ErrorResponseModel(response: response) else { return }

            if let siteCode = errorResponse.validationErrors?["HCaptcha_SiteKey"]?.first {
                throw StartRegistrationRequestError.captchaRequired(hCaptchaSiteCode: siteCode)
            }

            throw ServerError.error(errorResponse: errorResponse)
        default:
            return
        }
    }
}
