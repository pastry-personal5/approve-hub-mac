import ApproveHubContract
import CryptoKit
import Foundation

struct ServiceProofSigner {
  let privateKey: Curve25519.Signing.PrivateKey
  let pin: ServicePin

  init(state: CredentialState) throws {
    guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: state.signingKey) else {
      throw CredentialError.corruptState
    }
    privateKey = key
    pin = try ServicePin(rawPublicKey: key.publicKey.rawRepresentation)
  }

  func sign(challenge: Data, now: Date = Date()) throws -> ServiceProof {
    guard challenge.count == 32 else { throw IdentityProofError.malformedEncoding }
    let issued = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 * 1_000) / 1_000)
    let payload = ServiceProofPayload(
      keyID: pin.keyID,
      challenge: Base64URL.encode(challenge),
      issuedAt: ProofTimestamp.render(issued),
      expiresAt: ProofTimestamp.render(issued.addingTimeInterval(60))
    )
    let raw = try privateKey.signature(for: payload.canonicalBytes())
    return ServiceProof(payload: payload, signature: Base64URL.encode(raw))
  }
}
