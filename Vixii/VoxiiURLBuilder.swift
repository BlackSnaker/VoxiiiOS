import Foundation

enum VoxiiURLBuilder {
    static func normalizeBaseURL(_ rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let valueWithScheme: String
        if hasSupportedScheme(trimmed) {
            valueWithScheme = trimmed
        } else if trimmed.lowercased().hasPrefix("ws://") {
            valueWithScheme = "http://" + trimmed.dropFirst(5)
        } else if trimmed.lowercased().hasPrefix("wss://") {
            valueWithScheme = "https://" + trimmed.dropFirst(6)
        } else {
            valueWithScheme = "\(defaultScheme(for: trimmed))://\(trimmed)"
        }

        guard var components = URLComponents(string: valueWithScheme),
              components.host?.isEmpty == false else {
            return nil
        }

        guard let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        components.query = nil
        components.fragment = nil
        let normalizedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if shouldStripPathForAPIBase(normalizedPath) {
            components.path = ""
        }

        return components.url
    }

    static func endpoint(baseURL: String, path: String) -> URL? {
        guard let normalizedBase = normalizeBaseURL(baseURL),
              var components = URLComponents(url: normalizedBase, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let pathParts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let rawPath = String(pathParts.first ?? "")
        let rawQuery = pathParts.count > 1 ? String(pathParts[1]) : nil

        let cleanedPath = rawPath.hasPrefix("/") ? String(rawPath.dropFirst()) : rawPath
        let normalizedPath = cleanedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if basePath.isEmpty {
            components.path = normalizedPath.isEmpty ? "" : "/\(normalizedPath)"
        } else if normalizedPath.isEmpty {
            components.path = "/\(basePath)"
        } else if normalizedPath == basePath || normalizedPath.hasPrefix("\(basePath)/") {
            components.path = "/\(normalizedPath)"
        } else {
            components.path = "/\(basePath)/\(normalizedPath)"
        }
        components.percentEncodedQuery = rawQuery
        return components.url
    }

    static func candidateBaseURLs(_ rawValue: String) -> [URL] {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        if hasSupportedScheme(trimmed) || hasWebSocketScheme(trimmed) {
            guard let normalized = normalizeBaseURL(trimmed) else {
                return []
            }
            return [normalized]
        }

        let preferredScheme = defaultScheme(for: trimmed)
        let fallbackScheme = preferredScheme == "https" ? "http" : "https"
        let variants = [preferredScheme, fallbackScheme]

        var result: [URL] = []
        for scheme in variants {
            guard let url = normalizeBaseURL("\(scheme)://\(trimmed)") else {
                continue
            }
            if result.contains(where: { $0.absoluteString == url.absoluteString }) {
                continue
            }
            result.append(url)
        }
        return result
    }

    private static func hasSupportedScheme(_ value: String) -> Bool {
        let lowered = value.lowercased()
        return lowered.hasPrefix("http://") || lowered.hasPrefix("https://")
    }

    private static func hasWebSocketScheme(_ value: String) -> Bool {
        let lowered = value.lowercased()
        return lowered.hasPrefix("ws://") || lowered.hasPrefix("wss://")
    }

    private static func defaultScheme(for rawValue: String) -> String {
        guard let host = hostCandidate(from: rawValue) else {
            return "https"
        }
        return isLocalHost(host) ? "http" : "https"
    }

    private static func shouldStripPathForAPIBase(_ path: String) -> Bool {
        guard !path.isEmpty else {
            return true
        }

        let lowered = path.lowercased()
        if lowered == "api" || lowered == "login" || lowered == "index" {
            return true
        }

        if lowered.hasSuffix(".html") || lowered.hasSuffix(".htm") {
            return true
        }

        return false
    }

    private static func hostCandidate(from rawValue: String) -> String? {
        let noPath = rawValue.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? rawValue
        guard !noPath.isEmpty else {
            return nil
        }

        if noPath.hasPrefix("["),
           let closingBracket = noPath.firstIndex(of: "]"),
           noPath.index(after: noPath.startIndex) < closingBracket {
            let hostStart = noPath.index(after: noPath.startIndex)
            return String(noPath[hostStart..<closingBracket]).lowercased()
        }

        let host = noPath.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? noPath
        return host.lowercased()
    }

    private static func isLocalHost(_ host: String) -> Bool {
        if host == "localhost" || host == "127.0.0.1" || host == "0.0.0.0" || host == "::1" || host.hasSuffix(".local") {
            return true
        }
        return isPrivateIPv4(host)
    }

    private static func isPrivateIPv4(_ host: String) -> Bool {
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4,
              let first = Int(octets[0]),
              let second = Int(octets[1]),
              (0...255).contains(first),
              (0...255).contains(second) else {
            return false
        }

        if first == 10 || first == 127 || first == 192 && second == 168 {
            return true
        }
        if first == 172 && (16...31).contains(second) {
            return true
        }
        if first == 169 && second == 254 {
            return true
        }
        return false
    }

}
