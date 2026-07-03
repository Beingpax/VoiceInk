// Diagnostic reproducer for cloud-transcription timeouts behind VPNs that
// blackhole bulk HTTP/3 (QUIC) traffic — e.g. Palo Alto GlobalProtect.
//
// Symptom in VoiceInk: the first transcription of a longer dictation hangs and
// fails after ~60s with "The request timed out" (NSURLError -1001), while an
// immediate retry succeeds in 1-2s.
//
// Mechanism: a persistent URLSessionConfiguration caches the server's
// `Alt-Svc: h3` advertisement (in ~/Library/HTTPStorages/<bundle-id>/), so new
// connections upgrade to HTTP/3 over UDP 443. Some VPN tunnels pass small QUIC
// packets (handshake, small requests) but silently drop full-size datagrams,
// so multi-megabyte audio uploads stall until the request timeout. After the
// failure URLSession falls back to TCP, which is why the retry is instant.
//
// Build:  swiftc -parse-as-library -O quic-vpn-repro.swift -o quic-vpn-repro
// Usage:  quic-vpn-repro <idleSeconds> <shared|fresh> [bulkBytes]
//   shared = one default-config session, mirrors URLSession.shared behavior
//   fresh  = new ephemeral session per request (the fix: no cached Alt-Svc,
//            connections stay on TCP)
//
// On an affected network, after the host has been visited once with a
// persistent config (so Alt-Svc h3 is cached for the process):
//   quic-vpn-repro 1 shared 1500000   -> h3, times out (-1001) on the upload
//   quic-vpn-repro 1 shared 10000     -> h3, succeeds (small payload passes)
//   quic-vpn-repro 1 fresh  1500000   -> h2, succeeds
// The per-transaction metrics line prints the negotiated protocol and whether
// the connection was reused, which is the evidence that matters.

import Foundation

let idle = UInt32(CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? 1 : 1)
let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "shared"
let bulk = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3]) ?? 1_500_000 : 1_500_000
let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

final class MetricsDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        for t in metrics.transactionMetrics {
            let proto = t.networkProtocolName ?? "?"
            print("    metrics: proto=\(proto) reused=\(t.isReusedConnection) " +
                  "fetchStart->responseEnd=\(fmt(t.fetchStartDate, t.responseEndDate))")
        }
    }
    private func fmt(_ a: Date?, _ b: Date?) -> String {
        guard let a, let b else { return "n/a" }
        return String(format: "%.2fs", b.timeIntervalSince(a))
    }
}

let delegate = MetricsDelegate()
let sharedSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

func session() -> URLSession {
    if mode == "fresh" {
        return URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    }
    return sharedSession
}

func doUpload(_ label: String) async {
    let boundary = "Boundary-\(UUID().uuidString)"
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    // Invalid key on purpose: the server drains the multipart body and answers
    // 401, which exercises the full upload path without transcribing anything.
    request.setValue("Bearer sk-invalid-probe", forHTTPHeaderField: "Authorization")

    var body = Data()
    body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"probe.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
    body.append(Data(count: bulk))
    body.append("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\ngpt-4o-transcribe\r\n--\(boundary)--\r\n".data(using: .utf8)!)

    let s = session()
    let t0 = Date()
    do {
        let (data, response) = try await s.upload(for: request, from: body)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        print("  \(label): HTTP \(code) in \(String(format: "%.2f", Date().timeIntervalSince(t0)))s bodyBytes=\(data.count)")
    } catch {
        let ns = error as NSError
        print("  \(label): ERROR domain=\(ns.domain) code=\(ns.code) \(ns.localizedDescription) after \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")
    }
    if mode == "fresh" { s.finishTasksAndInvalidate() }
}

@main
struct Repro {
    static func main() async {
        print("[repro mode=\(mode) idle=\(idle)s bulk=\(bulk)]")
        await doUpload("req1")
        print("  idling \(idle)s...")
        sleep(idle)
        await doUpload("req2")
    }
}
