# ApproveHub

A Mac app for approving what your AI agents ask to do. AI asks. You decide. Your agent continues.

The owner CLI manages local service identity and requester credentials. The loopback HTTP service serves the canonical `/v1` API in [Sources/openapi.yaml](Sources/openapi.yaml). The Mac approval window is still under development. SwiftPM generates the shared types and client/server bindings at build time. See [product behavior](docs/product-behavior.md) and [architecture](docs/architecture.md).

## Local credential setup

Build both executables, then run the owner CLI while logged in to the Mac account that will use ApproveHub:

```sh
swift build
.build/debug/approve-hub setup
.build/debug/approve-hub requester add "Build Agent"
.build/debug/approve-hub requester list
.build/debug/approve-hub pin export
.build/debug/approve-hub requester revoke REQUESTER_ID
```

`setup` creates a persistent service signing key and a separate GUI decider credential. It prints the public service pin and fingerprint; it creates no requester. `requester add` prints one new token once. Transfer that token and the matching pin to the requesting app through an owner-controlled route. Save the token at issuance: the CLI cannot print it again. The service stores only its salted password-quality verifier. Active requester names must be unique. To replace a lost token, revoke its requester ID and add a new requester; pending requests under the old ID are cancelled.

An explicit repeat of `setup` restores a missing GUI pin from the local service key without changing credentials. `approve-hub decider reset` replaces the GUI credential in Keychain. To rotate the service key, stop ApproveHub Service, run `approve-hub identity rotate`, then distribute the newly printed pin. Existing clients fail closed until their pins are updated. Credential files live in the account's `Library/Application Support/ApproveHub` directory and the GUI secrets live in Keychain.

## Run the service

After `setup`, start the foreground service with `swift run approve-hub-service` or `.build/debug/approve-hub-service`. It listens only on `127.0.0.1:46931`; a port collision or missing/corrupt setup stops startup. Stop it with Control-C. The `approve-hub service` owner command and automatic GUI launch are part of the later bundle milestone.

Requires macOS 26 or later. Licensed under [Apache-2.0](LICENSE).

For setup and contributions, see the [contribution guide](docs/contribution-guide.md). Coding agents start with [AGENTS.md](AGENTS.md).
