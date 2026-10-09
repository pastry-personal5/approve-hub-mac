import CryptoKit
import Foundation
import Testing

@Test func ed25519InteroperatesWithRFC8032RawRepresentations() throws {
  func hex(_ text: String) throws -> Data {
    let bytes = Array(text.utf8)
    try #require(bytes.count.isMultiple(of: 2))
    var result = Data()
    for index in stride(from: 0, to: bytes.count, by: 2) {
      let pair = try #require(String(bytes: bytes[index..<(index + 2)], encoding: .utf8))
      result.append(try #require(UInt8(pair, radix: 16)))
    }
    return result
  }

  let seed = try hex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
  let expectedPublic = try hex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
  let expectedSignature = try hex(
    "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155"
      + "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b")
  let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
  #expect(privateKey.publicKey.rawRepresentation == expectedPublic)
  let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: expectedPublic)
  #expect(publicKey.isValidSignature(expectedSignature, for: Data()))
  #expect(publicKey.isValidSignature(try privateKey.signature(for: Data()), for: Data()))
}
