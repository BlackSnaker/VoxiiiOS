//
//  VixiiTests.swift
//  VixiiTests
//
//  Created by Oleg on 04.03.2026.
//

import Testing
import Foundation
@testable import Vixii

struct VixiiTests {
    @Test
    func normalizesServerURLWithoutScheme() {
        let value = VoxiiURLBuilder.normalizeBaseURL("127.0.0.1:3000")
        #expect(value?.absoluteString == "http://127.0.0.1:3000")
    }

    @Test
    func normalizesWebSocketSchemeToHTTP() {
        let value = VoxiiURLBuilder.normalizeBaseURL("ws://127.0.0.1:3000")
        #expect(value?.absoluteString == "http://127.0.0.1:3000")
    }

    @Test
    func preservesHttpsInEndpointBuilder() {
        let value = VoxiiURLBuilder.endpoint(baseURL: "https://voxii.example.com", path: "/api/login")
        #expect(value?.absoluteString == "https://voxii.example.com/api/login")
    }

    @Test
    func stripsApiSuffixFromBaseURL() {
        let value = VoxiiURLBuilder.normalizeBaseURL("https://voxii.example.com/api")
        #expect(value?.absoluteString == "https://voxii.example.com")
    }

    @Test
    func avoidsDuplicatedApiPrefixInEndpointBuilder() {
        let value = VoxiiURLBuilder.endpoint(baseURL: "https://voxii.example.com/api", path: "/api/login")
        #expect(value?.absoluteString == "https://voxii.example.com/api/login")
    }

    @Test
    func buildsSchemeCandidatesForPublicHosts() {
        let values = VoxiiURLBuilder
            .candidateBaseURLs("api.voxii.example.com")
            .map(\.absoluteString)
        #expect(values.first == "https://api.voxii.example.com")
        #expect(values.contains("http://api.voxii.example.com"))
    }

    @Test
    func stripsLoginHTMLSuffixFromBaseURL() {
        let value = VoxiiURLBuilder.normalizeBaseURL("https://voxii.lenuma.ru/login.html")
        #expect(value?.absoluteString == "https://voxii.lenuma.ru")
    }

    @Test
    func invalidServerURLReturnsNil() {
        let value = VoxiiURLBuilder.endpoint(baseURL: "   ", path: "/api/login")
        #expect(value == nil)
    }
}
