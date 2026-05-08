import Foundation

enum UpdateFeedURLBuilder {
    static func build(baseURLString: String, key: String?) -> String? {
        guard let key,
              !key.isEmpty,
              var components = URLComponents(string: baseURLString),
              components.scheme != nil,
              components.host != nil else {
            return nil
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "key" }
        queryItems.append(URLQueryItem(name: "key", value: key))
        components.queryItems = queryItems
        return components.string
    }
}
