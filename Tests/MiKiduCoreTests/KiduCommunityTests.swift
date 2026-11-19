import Foundation
import Testing
@testable import MiKiduCore

struct KiduCommunityTests {
    @Test func sameNormalizedNameKeepsAvatarAndSeparateOwners() throws {
        let first = try KiduLocalProfile.create(named: "  Lúa   Lunar ")
        let next = try KiduLocalProfile.create(named: "LU\u{301}A LUNAR")
        let other = try KiduLocalProfile.create(named: "Nube de Tiza")

        #expect(first.profile.displayName == "Lúa Lunar")
        #expect(first.profile.seedInput == next.profile.seedInput)
        #expect(first.profile.seedInput != other.profile.seedInput)
        #expect(first.profile.personKey != next.profile.personKey)
        #expect(first.profile.familySubject == nil)
        #expect(!first.profile.seedInput.contains("Lúa"))
        try first.validate()
    }

    @Test func rejectsEmptyOversizedAndControlNames() {
        for invalid in ["  \n", String(repeating: "x", count: 41), "Ficción\u{0000}"] {
            #expect(throws: KiduLocalProfile.NameError.invalid) {
                try KiduLocalProfile.create(named: invalid)
            }
        }
    }

    @Test func localProfileSurvivesReopenAndIsNeverReplacedOnInitialize() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("kidu.sqlite")
        let store = KiduStore(url: database)
        let device = UUID()
        let profile = try KiduLocalProfile.create(named: "Nube de Tiza")
        try await store.initialize(profile, deviceID: device)

        let reopened = KiduStore(url: database)
        #expect(try await reopened.snapshot() == profile)
        let other = try KiduLocalProfile.create(named: "Cometa de Papel")
        await #expect(throws: KiduError.alreadyInitialized) {
            try await reopened.initialize(other, deviceID: device)
        }
        #expect(try await reopened.snapshot() == profile)
    }

    @Test func agentBriefUsesOnlyExplicitInputsAndOmitsEmptySections() throws {
        var brief = KiduAgentBrief()
        #expect(throws: KiduAgentBrief.PreparationError.missingGoal) { try brief.prepare() }
        brief.goal = "  Revisar un ejemplo ficticio  "
        brief.context = "Archivo de muestra sin dependencias"
        brief.deliverable = "Tres observaciones comprobables"
        #expect(try brief.prepare() == """
        Objetivo
        Revisar un ejemplo ficticio

        Contexto
        Archivo de muestra sin dependencias

        Resultado esperado
        Tres observaciones comprobables
        """)
        brief.limits = String(repeating: "a", count: 4_001)
        #expect(throws: KiduAgentBrief.PreparationError.tooLong) { try brief.prepare() }
    }

    @Test func accountAccessAndProviderLinksUseOnlyFixedOfficialSites() {
        #expect(KiduAccountAccess.website.absoluteString == "https://www.kidual.com/")
        #expect(KiduAccountAccess.availabilityMessage.contains("no está disponible"))
        #expect(KiduAgentProvider.allCases.compactMap { $0.officialURL?.host } == ["docs.openclaw.ai", "chatgpt.com", "claude.ai"])
        #expect(KiduAgentProvider.allCases.allSatisfy { $0.officialURL?.query == nil && $0.officialURL?.fragment == nil })
    }
}

struct KiduFamilyPairingTests {
    let state = String(repeating: "s", count: 43)
    let code = String(repeating: "c", count: 43)
    let challenge = String(repeating: "p", count: 43)
    let redirectURI = "org.example.community:/sample/return"

    private func config() throws -> KiduFamilyPairing.Configuration {
        try KiduFamilyPairing.Configuration(
            clientID: "storybook-demo", redirectURI: redirectURI,
            authorization: URL(string: "https://identity.example/demo/consent")!,
            exchange: URL(string: "https://identity.example/demo/redeem")!,
            exchangeFields: ["client_field", "return_field", "one_time_code", "verifier_field"],
            profileFields: ["sample_id", "sample_shape"],
            trustedOrigin: URL(string: "https://identity.example/")!
        )
    }

    @Test func browserRequestUsesOnlyTheContractFragment() throws {
        let config = try config()
        let url = try KiduFamilyPairing.authorizationURL(for: config, state: state, challenge: challenge)
        #expect(url.scheme == "https")
        #expect(url.host == "identity.example")
        #expect(url.path == "/demo/consent")
        #expect(url.query == nil)
        let fragment = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedFragment)
        let items = try #require(URLComponents(string: "?" + fragment)?.queryItems)
        #expect(items.count == 5)
        let parameters = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value) })
        #expect(parameters["client_id"] == "storybook-demo")
        #expect(parameters["redirect_uri"] == redirectURI)
        #expect(parameters["code_challenge_method"] == "S256")
        #expect(parameters["code_challenge"] == challenge)
        #expect(parameters["state"] == state)
    }

    @Test func productionConfigDoesNotAcceptThirdPartyHosts() throws {
        #expect(throws: KiduFamilyPairing.Failure.unavailable) {
            try KiduFamilyPairing.Configuration(
                clientID: "storybook-demo", redirectURI: redirectURI,
                authorization: URL(string: "https://identity.example/demo/consent")!,
                exchange: URL(string: "https://identity.example/demo/redeem")!,
                exchangeFields: ["client_field", "return_field", "one_time_code", "verifier_field"],
                profileFields: ["sample_id", "sample_shape"]
            )
        }
        for badOrigin in [
            "http://identity.example/demo/redeem", "https://identity.example:443/demo/redeem",
            "https://identity.example./demo/redeem", "https://other.example/demo/redeem",
            "https://identity.example/demo/redeem?other=1", "https://identity.example/demo/%2Fredeem"
        ] {
            let valid = try config()
            #expect(throws: KiduFamilyPairing.Failure.unavailable) {
                try KiduFamilyPairing.Configuration(
                    clientID: valid.clientID, redirectURI: valid.redirectURI,
                    authorization: valid.authorization, exchange: URL(string: badOrigin)!,
                    exchangeFields: valid.exchangeFields, profileFields: valid.profileFields,
                    trustedOrigin: URL(string: "https://identity.example/")!
                )
            }
        }
    }

    @Test func callbackRejectsDifferentOriginsRoutesDuplicatedStateAndExtraFields() throws {
        let config = try config()
        let base = redirectURI
        func callback(_ value: String) throws -> URL { try #require(URL(string: value)) }
        let valid = try callback(base + "?code=\(code)&state=\(state)")
        #expect(try KiduFamilyPairing.returnedCode(from: valid, for: config, state: state) == code)
        for invalid in [
            "org.example.other:/sample/return?code=\(code)&state=\(state)",
            "org.example.community://other/sample/return?code=\(code)&state=\(state)",
            "org.example.community:/wrong?code=\(code)&state=\(state)",
            base + "?code=\(code)&state=another",
            base + "?code=\(code)&state=\(state)&state=\(state)",
            base + "?code=\(code)&state=\(state)&scope=profile",
            base + "?code=\(code)&state=\(state)#another",
            base + "?code=short&state=\(state)"
        ] {
            let url = try callback(invalid)
            #expect(throws: KiduFamilyPairing.Failure.invalidResponse) {
                try KiduFamilyPairing.returnedCode(from: url, for: config, state: state)
            }
        }
        let denied = try callback(base + "?error=access_denied&state=\(state)")
        #expect(throws: KiduFamilyPairing.Failure.denied) {
            try KiduFamilyPairing.returnedCode(from: denied, for: config, state: state)
        }
    }

    @Test func exchangeIsMinimalAndProfilePersistsWithoutCredentials() async throws {
        let config = try config()
        let payload = try KiduFamilyPairing.exchangeBody(for: config, code: code, verifier: challenge)
        let request = try #require(JSONSerialization.jsonObject(with: payload) as? [String: String])
        #expect(Set(request.keys) == ["client_field", "return_field", "one_time_code", "verifier_field"])
        #expect(request["verifier_field"] == challenge)
        let subject = UUID()
        let seed = String(repeating: "a", count: 64)
        let response = ["sample_id": subject.uuidString, "sample_shape": seed]
        let document = try KiduFamilyPairing.profileDocument(from: JSONSerialization.data(withJSONObject: response), for: config)
        #expect(document.profile.familySubject == subject)
        #expect(document.profile.personKey == subject)
        #expect(document.profile.seedInput == seed)
        #expect(document.profile.displayName == "Kidu")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = KiduStore(url: directory.appendingPathComponent("kidu.sqlite"))
        try await store.initialize(document, deviceID: UUID())
        #expect(try await store.snapshot() == document)

        for invalid in [
            response.merging(["session": "fixture"], uniquingKeysWith: { old, _ in old }),
            ["sample_id": "not-a-uuid", "sample_shape": seed],
            ["sample_id": subject.uuidString, "sample_shape": "invalid"]
        ] {
            let bytes = try JSONSerialization.data(withJSONObject: invalid)
            #expect(throws: KiduFamilyPairing.Failure.invalidResponse) {
                try KiduFamilyPairing.profileDocument(from: bytes, for: config)
            }
        }
    }
}
