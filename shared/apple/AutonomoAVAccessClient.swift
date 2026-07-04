import Foundation

enum AutonomoAVSharedConfig {
    static let appIdentifier = "autonomoav"
}

enum AutonomoAccessMode: String, CaseIterable, Codable, Identifiable {
    case guest
    case signedInFree
    case signedInPro

    var id: String { rawValue }
}

enum AutonomoPlanTier: String, Codable {
    case free
    case pro
}

struct AutonomoResolvedAccess: Equatable {
    let platformUserId: String?
    let planTier: AutonomoPlanTier
    let accessMode: AutonomoAccessMode
    let capabilities: AutonomoAccessCapabilities
    let limits: AutonomoAccessLimits

    static let guest = AutonomoResolvedAccess.localFallback(for: .guest)

    static func localFallback(for accessMode: AutonomoAccessMode) -> AutonomoResolvedAccess {
        AutonomoResolvedAccess(
            platformUserId: nil,
            planTier: accessMode == .signedInPro ? .pro : .free,
            accessMode: accessMode,
            capabilities: .forMode(accessMode),
            limits: .forMode(accessMode)
        )
    }
}

struct AutonomoAccessCapabilities: Codable, Equatable {
    let isSignedIn: Bool
    let canUseBackend: Bool
    let canUsePremiumFeatures: Bool
    let canUseCloudSync: Bool
    let canManagePlan: Bool

    var canUseIntake: Bool {
        canUsePremiumFeatures
    }

    static func forMode(_ accessMode: AutonomoAccessMode) -> AutonomoAccessCapabilities {
        switch accessMode {
        case .guest:
            AutonomoAccessCapabilities(
                isSignedIn: false,
                canUseBackend: false,
                canUsePremiumFeatures: false,
                canUseCloudSync: false,
                canManagePlan: false
            )
        case .signedInFree:
            AutonomoAccessCapabilities(
                isSignedIn: true,
                canUseBackend: true,
                canUsePremiumFeatures: false,
                canUseCloudSync: false,
                canManagePlan: true
            )
        case .signedInPro:
            AutonomoAccessCapabilities(
                isSignedIn: true,
                canUseBackend: true,
                canUsePremiumFeatures: true,
                canUseCloudSync: true,
                canManagePlan: true
            )
        }
    }

    init(
        isSignedIn: Bool,
        canUseBackend: Bool,
        canUsePremiumFeatures: Bool,
        canUseCloudSync: Bool,
        canManagePlan: Bool
    ) {
        self.isSignedIn = isSignedIn
        self.canUseBackend = canUseBackend
        self.canUsePremiumFeatures = canUsePremiumFeatures
        self.canUseCloudSync = canUseCloudSync
        self.canManagePlan = canManagePlan
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isSignedIn = try container.decodeIfPresent(Bool.self, forKey: .isSignedIn) ?? false
        canUseBackend = try container.decodeIfPresent(Bool.self, forKey: .canUseBackend) ?? false
        canUsePremiumFeatures = try container.decodeIfPresent(Bool.self, forKey: .canUsePremiumFeatures) ?? false
        canUseCloudSync = try container.decodeIfPresent(Bool.self, forKey: .canUseCloudSync) ?? false
        canManagePlan = try container.decodeIfPresent(Bool.self, forKey: .canManagePlan) ?? isSignedIn
    }
}

struct AutonomoAccessLimits: Codable, Equatable {
    static func forMode(_ accessMode: AutonomoAccessMode) -> AutonomoAccessLimits {
        _ = accessMode
        return AutonomoAccessLimits()
    }
}

struct AutonomoMeAccessResponse: Decodable, Equatable {
    let viewer: AutonomoMeAccessViewer?
    let apps: [AutonomoAppAccess]
}

struct AutonomoMeAccessViewer: Decodable, Equatable {
    let isAuthenticated: Bool
    let userId: String?
    let identityProvider: String?
}

struct AutonomoAppAccess: Decodable, Equatable {
    let appId: String
    let accessMode: AutonomoAccessMode
    let planTier: AutonomoPlanTier
    let capabilities: AutonomoAccessCapabilities
    let limits: AutonomoAccessLimits

    init(
        appId: String,
        accessMode: AutonomoAccessMode,
        planTier: AutonomoPlanTier,
        capabilities: AutonomoAccessCapabilities,
        limits: AutonomoAccessLimits
    ) {
        self.appId = appId
        self.accessMode = accessMode
        self.planTier = planTier
        self.capabilities = capabilities
        self.limits = limits
    }

    enum CodingKeys: String, CodingKey {
        case appId
        case accessMode
        case planTier
        case capabilities
        case limits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appId = try container.decode(String.self, forKey: .appId)
        accessMode = try container.decode(AutonomoAccessMode.self, forKey: .accessMode)
        planTier = try container.decode(AutonomoPlanTier.self, forKey: .planTier)
        capabilities = try container.decodeIfPresent(AutonomoAccessCapabilities.self, forKey: .capabilities)
            ?? .forMode(accessMode)
        limits = try container.decodeIfPresent(AutonomoAccessLimits.self, forKey: .limits)
            ?? .forMode(accessMode)
    }
}

@MainActor
protocol AutonomoPromotionCodeRedeeming {
    func redeemPromotionCode(_ code: String) async throws -> AutonomoPromotionCodeRedemptionResponse
}

@MainActor
struct AutonomoPromoCodeClient: AutonomoPromotionCodeRedeeming {
    var appId: String
    var baseURL: URL?
    var urlSession: URLSession
    var tokenProvider: () async throws -> String?
    var encoder: JSONEncoder
    var decoder: JSONDecoder

    init(
        appId: String = AutonomoAVSharedConfig.appIdentifier,
        baseURL: URL?,
        urlSession: URLSession = .shared,
        tokenProvider: @escaping () async throws -> String? = { nil },
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.appId = appId
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.tokenProvider = tokenProvider
        self.encoder = encoder
        self.decoder = decoder
    }

    func redeemPromotionCode(_ code: String) async throws -> AutonomoPromotionCodeRedemptionResponse {
        guard let baseURL else {
            throw AutonomoPromoCodeClientError.missingBaseURL
        }
        let normalizedAppId = appId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedAppId.isEmpty else {
            throw AutonomoPromoCodeClientError.missingAppID
        }
        guard let token = try await tokenProvider(), !token.isEmpty else {
            throw AutonomoPromoCodeClientError.missingToken
        }

        let encodedAppId = normalizedAppId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? normalizedAppId
        let path = "/v1/apps/\(encodedAppId)/promotions/redeem"
        let url = URL(string: path, relativeTo: baseURL)?.absoluteURL
            ?? baseURL.appending(path: "v1/apps/\(encodedAppId)/promotions/redeem")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(normalizedAppId, forHTTPHeaderField: "x-appsav-app-id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(AutonomoPromoCodeRedeemRequest(code: code))

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AutonomoPromoCodeClientError.requestFailed(statusCode: -1)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AutonomoPromoCodeClientError.decode(from: data, statusCode: httpResponse.statusCode)
        }

        return try decoder.decode(AutonomoPromotionCodeRedemptionResponse.self, from: data)
    }
}

enum AutonomoPromoCodeClientError: LocalizedError, Equatable {
    case missingAppID
    case missingBaseURL
    case missingToken
    case requestFailed(statusCode: Int)
    case server(code: String, message: String, statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .missingAppID, .missingBaseURL:
            L10n.string("promo.error.configuration")
        case .missingToken:
            L10n.string("upload.error.missingToken")
        case .requestFailed:
            L10n.string("promo.error.redeemFailed")
        case .server(_, let message, _):
            message
        }
    }

    static func decode(from data: Data, statusCode: Int) -> AutonomoPromoCodeClientError {
        if let decoded = try? JSONDecoder().decode(AutonomoPromoCodeErrorResponse.self, from: data) {
            return .server(
                code: decoded.error.code,
                message: decoded.error.message,
                statusCode: statusCode
            )
        }
        return .requestFailed(statusCode: statusCode)
    }
}

private struct AutonomoPromoCodeRedeemRequest: Encodable {
    let code: String
}

struct AutonomoPromotionCodeRedemptionResponse: Decodable, Equatable {
    let appId: String?
    let userId: String?
    let code: String?
    let campaignId: String?
    let redemptionId: String?
    let entitlement: AutonomoPromoCodeEntitlement?
}

struct AutonomoPromoCodeEntitlement: Decodable, Equatable {
    let appId: String?
    let userId: String?
    let planTier: String?
    let accessMode: String?
    let status: String?
    let source: String?
}

private struct AutonomoPromoCodeErrorResponse: Decodable {
    struct APIError: Decodable {
        let code: String
        let message: String
    }

    let error: APIError
}
