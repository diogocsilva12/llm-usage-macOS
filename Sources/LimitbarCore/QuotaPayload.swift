import Foundation
import CoreFoundation

enum QuotaPayload {
    static func object(_ data: Data) throws -> [String: Any] {
        guard data.count <= 1_048_576 else { throw UsageError.outputTooLarge }
        guard let object = try? JSONSerialization.jsonObject(with: data), let dictionary = object as? [String: Any] else {
            throw UsageError.invalidResponse
        }
        return dictionary
    }

    static func number(_ value: Any?) throws -> Double? {
        guard let value, !(value is NSNull) else { return nil }
        let result: Double?
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { throw UsageError.invalidResponse }
            result = number.doubleValue
        } else if let string = value as? String { result = Double(string) }
        else { result = nil }
        guard let result, result.isFinite else { throw UsageError.invalidResponse }
        return result
    }

    static func firstNumber(_ object: [String: Any], keys: [String]) throws -> Double? {
        for key in keys { if let number = try number(object[key]) { return number } }
        return nil
    }

    static func date(_ value: Any?) -> Date? {
        if let string = value as? String, let date = UsageDate.parse(string) { return date }
        guard let numeric = try? number(value), numeric > 0 else { return nil }
        let seconds = numeric > 100_000_000_000 ? numeric / 1000 : numeric
        guard seconds <= 253_402_300_799 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
