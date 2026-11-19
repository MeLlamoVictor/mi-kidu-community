import Foundation

/// Vinculación de perfil sin credenciales de una sesión entre aplicaciones.
public enum KiduFamilyPairing {
    public struct Configuration: Sendable {
        public let clientID: String
        public let callbackScheme: String
        public let callbackPath: String
        public let redirectURI: String
        public let authorization: URL
        public let exchange: URL
        let exchangeFields: [String]
        let profileFields: [String]

        public init(clientID: String, redirectURI: String, authorization: URL, exchange: URL,
                    exchangeFields: [String], profileFields: [String]) throws {
            try self.init(clientID: clientID, redirectURI: redirectURI, authorization: authorization, exchange: exchange,
                          exchangeFields: exchangeFields, profileFields: profileFields,
                          trustedOrigin: KiduAccountAccess.website)
        }

        init(clientID: String, redirectURI: String, authorization: URL, exchange: URL,
             exchangeFields: [String], profileFields: [String], trustedOrigin: URL) throws {
            guard !clientID.isEmpty, clientID.utf8.count <= 128,
                  Self.trusts(authorization, from: trustedOrigin), Self.trusts(exchange, from: trustedOrigin),
                  authorization != exchange,
                  let callback = URLComponents(string: redirectURI), let scheme = callback.scheme,
                  scheme.contains("."), scheme == scheme.lowercased(),
                  scheme != "http", scheme != "https", callback.host == nil, callback.port == nil,
                  callback.user == nil, callback.password == nil, callback.query == nil, callback.fragment == nil,
                  Self.isSafePath(callback),
                  Self.validFields(exchangeFields, count: 4), Self.validFields(profileFields, count: 2) else {
                throw Failure.unavailable
            }
            self.clientID = clientID
            callbackScheme = scheme
            callbackPath = callback.percentEncodedPath
            self.redirectURI = redirectURI
            self.authorization = authorization
            self.exchange = exchange
            self.exchangeFields = exchangeFields
            self.profileFields = profileFields
        }

        private static func trusts(_ url: URL, from origin: URL) -> Bool {
            guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  parts.scheme == "https", parts.host?.lowercased() == origin.host?.lowercased(),
                  parts.host != nil, parts.port == nil, parts.user == nil, parts.password == nil,
                  parts.query == nil, parts.fragment == nil else { return false }
            return isSafePath(parts)
        }

        private static func isSafePath(_ parts: URLComponents) -> Bool {
            let path = parts.percentEncodedPath
            return path.count > 1 && path.hasPrefix("/") && !path.contains("//") && !path.contains("%")
                && !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
        }

        private static func validFields(_ fields: [String], count: Int) -> Bool {
            fields.count == count && Set(fields).count == count
                && fields.allSatisfy { $0.range(of: #"\A[A-Za-z][A-Za-z0-9_]{0,39}\z"#, options: .regularExpression) != nil }
        }
    }

    public static func authorizationURL(for config: Configuration, state: String, challenge: String) throws -> URL {
        guard isSecret(state), isSecret(challenge) else { throw Failure.invalidResponse }
        var values = URLComponents()
        values.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: state)
        ]
        guard var url = URLComponents(url: config.authorization, resolvingAgainstBaseURL: false) else {
            throw Failure.invalidResponse
        }
        url.percentEncodedFragment = values.percentEncodedQuery
        guard let result = url.url else { throw Failure.invalidResponse }
        return result
    }

    public static func returnedCode(from callback: URL, for config: Configuration, state: String) throws -> String {
        guard isSecret(state), let url = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              url.scheme == config.callbackScheme, url.percentEncodedPath == config.callbackPath,
              url.host == nil, url.port == nil, url.user == nil, url.password == nil, url.fragment == nil,
              let items = url.queryItems, items.count == 2,
              items.filter({ $0.name == "state" }).map(\.value) == [state] else {
            throw Failure.invalidResponse
        }
        if items.contains(URLQueryItem(name: "error", value: "access_denied")) { throw Failure.denied }
        guard let code = items.first(where: { $0.name == "code" })?.value, isSecret(code) else {
            throw Failure.invalidResponse
        }
        return code
    }

    public static func exchangeBody(for config: Configuration, code: String, verifier: String) throws -> Data {
        guard isSecret(code), isSecret(verifier) else { throw Failure.invalidResponse }
        let values = [config.clientID, config.redirectURI, code, verifier]
        return try JSONEncoder().encode(Dictionary(uniqueKeysWithValues: zip(config.exchangeFields, values)))
    }

    public static func profileDocument(from data: Data, for config: Configuration) throws -> KiduDocument {
        guard data.count <= 4_096,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              Set(object.keys) == Set(config.profileFields),
              let value = object[config.profileFields[0]], let subject = UUID(uuidString: value),
              let seed = object[config.profileFields[1]], isSeed(seed) else { throw Failure.invalidResponse }

        let profile = KiduProfile(personKey: subject, seedInput: seed, displayName: "Kidu", kind: .adult,
                                  familySubject: subject)
        struct InitialWorld: Encodable { let version = 1; let cuenta: UUID }
        return try KiduDocument(profile: profile, originalWorld: JSONEncoder().encode(InitialWorld(cuenta: subject)))
    }

    static func isSeed(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private static func isSecret(_ value: String) -> Bool {
        value.utf8.count == 43 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }

    public enum Failure: Error, Equatable, LocalizedError, Sendable {
        case invalidResponse, denied, unavailable, expired, rateLimited, browser

        public var errorDescription: String? {
            switch self {
            case .invalidResponse: "No se pudo verificar el retorno de Kidual."
            case .denied: "Has cancelado el vínculo con Kidual."
            case .unavailable: "El perfil Familia no está disponible para Mi Kidu."
            case .expired: "El código ya no se puede usar. Vuelve a empezar."
            case .rateLimited: "Hay demasiados intentos. Espera antes de volver a probar."
            case .browser: "No se pudo abrir la autorización de Kidual."
            }
        }
    }
}
