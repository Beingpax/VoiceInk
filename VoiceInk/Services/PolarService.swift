import Foundation
import IOKit
import os

class PolarService {
    private let organizationId = "6f3d781d-a630-4435-9dba-058486f2d936"
    private let baseURL = "https://api.polar.sh"
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "PolarService")

    private func createRequest(endpoint: String, method: String = "POST") -> URLRequest {
        let url = URL(string: "\(baseURL)\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
        
    struct LicenseValidationResponse: Codable {
        let status: String
        let limit_activations: Int?
        let id: String?
        let activation: ActivationResponse?
    }
    
    struct ActivationResponse: Codable {
        let id: String
    }
    
    struct ActivationRequest: Codable {
        let key: String
        let organization_id: String
        let label: String
        let meta: [String: String]
    }
    
    struct ActivationResult: Codable {
        let id: String
        let license_key: LicenseKeyInfo
    }
    
    struct LicenseKeyInfo: Codable {
        let limit_activations: Int?
        let status: String
    }
    
    // Generate a unique device identifier using shared logic
    private func getDeviceIdentifier() -> String {
        return Obfuscator.getDeviceIdentifier()
    }
    
    // Check if a license key requires activation
    func checkLicenseRequiresActivation(_ key: String) async throws -> (isValid: Bool, requiresActivation: Bool, activationsLimit: Int?) {
        var request = createRequest(endpoint: "/v1/customer-portal/license-keys/validate")

        let body: [String: Any] = [
            "key": key,
            "organization_id": organizationId
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, httpResponse) = try await URLSession.shared.data(for: request)

        if let httpResponse = httpResponse as? HTTPURLResponse {
            if !(200...299).contains(httpResponse.statusCode) {
                let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                logger.error("🔑 License validation failed [HTTP \(httpResponse.statusCode)]: \(errorMsg, privacy: .public)")
                switch httpResponse.statusCode {
                case 404: throw LicenseError.keyNotFound
                default:  throw LicenseError.serverError(httpResponse.statusCode)
                }
            }
        }

        // Log successful response
        let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode response"
        let statusCode = (httpResponse as? HTTPURLResponse)?.statusCode ?? 0
        logger.notice("🔑 License validation success [HTTP \(statusCode)]: \(rawResponse, privacy: .public)")
        
        let validationResponse = try JSONDecoder().decode(LicenseValidationResponse.self, from: data)
        let isValid = validationResponse.status == "granted"
        
        // If limit_activations is nil or 0, the license doesn't require activation
        let requiresActivation = (validationResponse.limit_activations ?? 0) > 0
        
        return (isValid: isValid, requiresActivation: requiresActivation, activationsLimit: validationResponse.limit_activations)
    }
    
    // Activate a license key on this device
    func activateLicenseKey(_ key: String) async throws -> (activationId: String, activationsLimit: Int) {
        var request = createRequest(endpoint: "/v1/customer-portal/license-keys/activate")
        
        let deviceId = getDeviceIdentifier()
        let hostname = Host.current().localizedName ?? "Unknown Mac"
        
        let activationRequest = ActivationRequest(
            key: key,
            organization_id: organizationId,
            label: hostname,
            meta: ["device_id": deviceId]
        )
        
        request.httpBody = try JSONEncoder().encode(activationRequest)
        
        let (data, httpResponse) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = httpResponse as? HTTPURLResponse {
            if !(200...299).contains(httpResponse.statusCode) {
                let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                logger.error("🔑 License activation failed [HTTP \(httpResponse.statusCode)]: \(errorMsg, privacy: .public)")
                switch httpResponse.statusCode {
                case 404: throw LicenseError.keyNotFound
                case 403: throw LicenseError.activationLimitReached
                default:  throw LicenseError.serverError(httpResponse.statusCode)
                }
            }
        }
        
        // Log successful response
        let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode response"
        let statusCode = (httpResponse as? HTTPURLResponse)?.statusCode ?? 0
        logger.notice("🔑 License activation success [HTTP \(statusCode)]: \(rawResponse, privacy: .public)")
        
        let activationResult = try JSONDecoder().decode(ActivationResult.self, from: data)
        
        return (activationId: activationResult.id, activationsLimit: activationResult.license_key.limit_activations ?? 0)
    }
    
    // Validate a license key with an activation ID
    func validateLicenseKeyWithActivation(_ key: String, activationId: String) async throws -> Bool {
        var request = createRequest(endpoint: "/v1/customer-portal/license-keys/validate")
        
        let body: [String: Any] = [
            "key": key,
            "organization_id": organizationId,
            "activation_id": activationId
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, httpResponse) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = httpResponse as? HTTPURLResponse {
            if !(200...299).contains(httpResponse.statusCode) {
                let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                logger.error("🔑 License validation with activation failed [HTTP \(httpResponse.statusCode)]: \(errorMsg, privacy: .public)")
                switch httpResponse.statusCode {
                case 404: throw LicenseError.keyNotFound
                default:  throw LicenseError.serverError(httpResponse.statusCode)
                }
            }
        }

        // Log successful response
        let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode response"
        let statusCode = (httpResponse as? HTTPURLResponse)?.statusCode ?? 0
        logger.notice("🔑 License validation with activation success [HTTP \(statusCode)]: \(rawResponse, privacy: .public)")
        
        let validationResponse = try JSONDecoder().decode(LicenseValidationResponse.self, from: data)
        
        return validationResponse.status == "granted"
    }
}

enum LicenseError: Error {
    case keyNotFound             // 404 - key doesn't exist in this org
    case activationLimitReached  // 403 - device limit hit
    case serverError(Int)        // unexpected HTTP status
}
