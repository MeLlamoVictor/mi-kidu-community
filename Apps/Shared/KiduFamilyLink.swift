#if os(macOS) || os(iOS)
import AuthenticationServices
import CryptoKit
import Foundation
import Security
import MiKiduCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum KiduFamilyLinkRelease {
    static var configuration: KiduFamilyPairing.Configuration? {
        let bundle = Bundle.main
        func setting(_ key: String) -> String {
            bundle.object(forInfoDictionaryKey: key) as? String ?? ""
        }
        guard setting("KiduFamilyLinkEnabled") == "YES",
              let authorization = URL(string: setting("KiduFamilyAuthorization")),
              let exchange = URL(string: setting("KiduFamilyExchange")),
              let config = try? KiduFamilyPairing.Configuration(
                clientID: setting("KiduFamilyClientID"),
                redirectURI: setting("KiduFamilyRedirect"),
                authorization: authorization,
                exchange: exchange,
                exchangeFields: setting("KiduFamilyExchangeFields").components(separatedBy: ","),
                profileFields: setting("KiduFamilyProfileFields").components(separatedBy: ",")
              ),
              let registrations = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]],
              registrations.contains(where: { ($0["CFBundleURLSchemes"] as? [String])?.contains(config.callbackScheme) == true })
        else { return nil }
        return config
    }

    static var isEnabled: Bool { configuration != nil }
}

@MainActor
final class KiduFamilyLink: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: ASPresentationAnchor
    private var authentication: ASWebAuthenticationSession?
    private var pending: CheckedContinuation<URL, any Error>?

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
        super.init()
    }

    static func inCurrentWindow() throws -> KiduFamilyLink {
        #if os(macOS)
        guard let anchor = NSApp.keyWindow else { throw KiduFamilyPairing.Failure.browser }
        #else
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let anchor = scenes.filter({ $0.activationState == .foregroundActive })
            .flatMap(\.windows).first(where: \.isKeyWindow) else { throw KiduFamilyPairing.Failure.browser }
        #endif
        return KiduFamilyLink(anchor: anchor)
    }

    func authorize() async throws -> KiduDocument {
        guard let config = KiduFamilyLinkRelease.configuration else { throw KiduFamilyPairing.Failure.unavailable }
        let state = try Self.makeSecret()
        let verifier = try Self.makeSecret()
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let url = try KiduFamilyPairing.authorizationURL(for: config, state: state, challenge: challenge)
        let callback = try await readCallback(from: url, scheme: config.callbackScheme)
        let code = try KiduFamilyPairing.returnedCode(from: callback, for: config, state: state)
        return try await exchange(for: config, code: code, verifier: verifier)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor }

    private func readCallback(from url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(scheme)) {
                [weak self] callback, error in
                let result: Result<URL, KiduFamilyPairing.Failure>
                if let callback, error == nil {
                    result = .success(callback)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    result = .failure(.denied)
                } else {
                    result = .failure(.browser)
                }
                Task { @MainActor [weak self] in self?.finish(result) }
            }
            authentication = session
            session.presentationContextProvider = self
            if !session.start() {
                finish(.failure(.browser))
            }
        }
    }

    private func finish(_ result: Result<URL, KiduFamilyPairing.Failure>) {
        guard let pending else { return }
        self.pending = nil
        authentication = nil
        switch result {
        case .success(let callback): pending.resume(returning: callback)
        case .failure(let failure): pending.resume(throwing: failure)
        }
    }

    private func exchange(for pairing: KiduFamilyPairing.Configuration, code: String, verifier: String) async throws -> KiduDocument {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        let session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: pairing.exchange)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try KiduFamilyPairing.exchangeBody(for: pairing, code: code, verifier: verifier)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.url == pairing.exchange else {
            throw KiduFamilyPairing.Failure.invalidResponse
        }
        switch http.statusCode {
        case 200: break
        case 400: throw KiduFamilyPairing.Failure.expired
        case 429: throw KiduFamilyPairing.Failure.rateLimited
        default: throw KiduFamilyPairing.Failure.unavailable
        }
        guard http.mimeType == "application/json" else { throw KiduFamilyPairing.Failure.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 4_096 else { throw KiduFamilyPairing.Failure.invalidResponse }
            data.append(byte)
        }
        return try KiduFamilyPairing.profileDocument(from: data, for: pairing)
    }

    private static func makeSecret() throws -> String {
        var bytes = Data(count: 32)
        let result = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard result == errSecSuccess else { throw KiduFamilyPairing.Failure.browser }
        return base64URL(bytes)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
#endif
