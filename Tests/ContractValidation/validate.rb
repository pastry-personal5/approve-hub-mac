# frozen_string_literal: true

require 'base64'
require 'digest'
require 'json'
require 'yaml'

spec = YAML.load_file(File.expand_path('../../Sources/openapi.yaml', __dir__))
components = spec.fetch('components')
paths = spec.fetch('paths')

def check(condition, message)
  raise "Contract check failed: #{message}" unless condition
end

def dereference(components, value)
  return value unless value.key?('$ref')

  segments = value.fetch('$ref').split('/').drop(2)
  segments.reduce(components) { |part, key| part.fetch(key) }
end

def response(components, operation, status)
  dereference(components, operation.fetch('responses').fetch(status.to_s))
end

check(spec.fetch('openapi') == '3.1.0', 'OpenAPI version')
check(spec.fetch('servers').first.fetch('url') == 'http://127.0.0.1:46931', 'fixed listener')

operations = {
  '/v1/identity/proofs' => ['post', nil],
  '/v1/requester/requests' => ['post', 'requesterBearer'],
  '/v1/requester/requests:submit-and-wait' => ['post', 'requesterBearer'],
  '/v1/requester/requests/{requestID}:wait' => ['post', 'requesterBearer'],
  '/v1/requester/requests/{requestID}' => ['delete', 'requesterBearer'],
  '/v1/decider/requests' => ['get', 'deciderBearer'],
  '/v1/decider/requests/{requestID}:decide' => ['post', 'deciderBearer'],
  '/v1/decider/events' => ['get', 'deciderBearer']
}
check(paths.keys.sort == operations.keys.sort, 'operation path set')
operations.each do |path, (method, role)|
  operation = paths.fetch(path).fetch(method)
  check(operation['security'] == (role ? [{ role => [] }] : nil), "role scope for #{path}")
  forbidden = response(components, operation, 403)
  expected_forbidden = role ? 'Forbidden' : 'OriginRejected'
  check(forbidden.equal?(components.fetch('responses').fetch(expected_forbidden)), "Origin rejection for #{path}")
end

proof = paths.fetch('/v1/identity/proofs').fetch('post')
proof_request = dereference(components, proof.fetch('requestBody').fetch('content').fetch('application/json').fetch('schema'))
check(proof_request.fetch('required') == ['challenge'], 'proof challenge required')
proof_payload = components.fetch('schemas').fetch('IdentityProofPayload')
check(proof_payload.fetch('required').sort == %w[protocol listener keyID challenge issuedAt expiresAt].sort,
      'exact signed proof fields')
check(proof_payload.fetch('properties').keys.sort == proof_payload.fetch('required').sort,
      'proof has no unsigned extra fields')
check(components.fetch('schemas').fetch('Base64URL32').fetch('pattern') == '^[A-Za-z0-9_-]{43}$',
      '32-byte challenge representation')

create_paths = ['/v1/requester/requests', '/v1/requester/requests:submit-and-wait']
create_paths.each do |path|
  operation = paths.fetch(path).fetch('post')
  key = dereference(components, operation.fetch('parameters').first)
  check(key.fetch('name') == 'Idempotency-Key' && key.fetch('required'), "retry key on #{path}")
  check(response(components, operation, 409).equal?(components.fetch('responses').fetch('IdempotencyConflict')),
        "key conflict on #{path}")
  check(response(components, operation, 422).equal?(components.fetch('responses').fetch('RejectedRequest')),
        "sensitive rejection on #{path}")
  limit = response(components, operation, 429)
  check(limit.fetch('headers').key?('Retry-After'), "pending limit retry on #{path}")
end

create_schema = components.fetch('schemas').fetch('CreateRequest')
check(create_schema.fetch('required').sort == %w[actionType text sensitive].sort, 'create required fields')
check(create_schema.fetch('properties').fetch('actionType').fetch('maxLength') == 128, 'action bound')
check(create_schema.fetch('properties').fetch('text').fetch('x-maxUtf8Bytes') == 16_384,
      'text byte bound')
check(components.fetch('schemas').fetch('RequestSnapshot').fetch('properties').fetch('text')
                .fetch('x-maxUtf8Bytes') == 16_384, 'snapshot text byte bound')
expiry = create_schema.fetch('properties').fetch('expirySeconds')
check(expiry.fetch('default') == 120 && expiry.fetch('minimum') == 1 && !expiry.key?('maximum'),
      'requested expiry remains distinct from its effective cap')
check(components.fetch('schemas').fetch('RequestSnapshot').fetch('properties').fetch('expiresAt')
                .fetch('description').include?('600 seconds'), 'effective expiry cap')
wait = components.fetch('schemas').fetch('WaitRequest').fetch('properties').fetch('waitSeconds')
check(wait.fetch('maximum') == 30 && wait.fetch('minimum') == 1, 'stepwise wait bounds')

create_examples = components.fetch('requestBodies').fetch('CreateRequest').fetch('content')
                            .fetch('application/json').fetch('examples')
ordinary = create_examples.fetch('ordinary').fetch('value')
sensitive = create_examples.fetch('rejectedSensitive').fetch('value')
check(ordinary.keys.sort == %w[actionType text sensitive].sort && ordinary.fetch('sensitive') == false,
      'ordinary create example')
check(sensitive.fetch('sensitive') == true, 'sensitive rejection input example')

snapshot_schema = components.fetch('schemas').fetch('RequestSnapshot')
snapshot = snapshot_schema.fetch('examples').first
check((snapshot_schema.fetch('required') - snapshot.keys).empty?, 'snapshot example required fields')
check((snapshot.keys - snapshot_schema.fetch('properties').keys).empty?, 'snapshot example known fields')
check(snapshot.fetch('state') == 'pending' && snapshot.fetch('sensitive') == false,
      'ordinary pending snapshot')
digest_fields = %w[id requesterName actionType text sensitive sessionID createdAt expiresAt]
canonical_input = digest_fields.to_h { |key| [key, snapshot.fetch(key, nil)] }
# This fixture contains ASCII strings and integer-free values. Sorted JSON is
# exactly its RFC 8785 representation, making the expected digest independent
# of property order in the YAML example.
canonical_json = JSON.generate(canonical_input.sort.to_h)
expected_digest = 'sha256:' + Base64.urlsafe_encode64(Digest::SHA256.digest(canonical_json), padding: false)
check(snapshot.fetch('digest') == expected_digest, 'example digest calculation')
check(Regexp.new(components.fetch('schemas').fetch('DecisionDigest').fetch('pattern')).match?(expected_digest),
      'digest representation')
check(snapshot.fetch('requestedExpirySeconds') == 120, 'default expiry in snapshot')

current_ref = '#/components/schemas/RequestSnapshot'
{
  '/v1/requester/requests' => ['post', 201],
  '/v1/requester/requests:submit-and-wait' => ['post', 200],
  '/v1/requester/requests/{requestID}:wait' => ['post', 200],
  '/v1/requester/requests/{requestID}' => ['delete', 200],
  '/v1/decider/requests/{requestID}:decide' => ['post', 200]
}.each do |path, (method, status)|
  schema = response(components, paths.fetch(path).fetch(method), status)
             .fetch('content').fetch('application/json').fetch('schema')
  check(schema.fetch('$ref') == current_ref, "full snapshot from #{path}")
end

problem_schema = components.fetch('schemas').fetch('Problem')
check(problem_schema.fetch('required').sort == %w[type title status code].sort, 'Problem Details fields')
problem_codes = problem_schema.fetch('properties').fetch('code').fetch('enum')
seen_codes = []
problem_statuses = {
  'MalformedChallenge' => 400,
  'MalformedRequest' => 400,
  'Unauthenticated' => 401,
  'OriginRejected' => 403,
  'Forbidden' => 403,
  'RequestNotFound' => 404,
  'IdempotencyConflict' => 409,
  'DigestMismatch' => 409,
  'CursorUnavailable' => 409,
  'RejectedRequest' => 422,
  'PendingLimit' => 429
}
components.fetch('responses').each do |name, entry|
  content = entry.fetch('content', {})
  next unless content.key?('application/problem+json')

  body = content.fetch('application/problem+json')
  check(body.fetch('schema').fetch('$ref') == '#/components/schemas/Problem', "problem schema for #{name}")
  examples = body['examples']&.values&.map { |example| example.fetch('value') } || [body.fetch('example')]
  examples.each do |example|
    code = example.fetch('code')
    seen_codes << code
    check(problem_codes.include?(code), "registered code #{code}")
    check(example.fetch('type') == "urn:approvehub:problem:#{code}", "stable type #{code}")
    check(example.fetch('title').is_a?(String) && example.fetch('status').is_a?(Integer),
          "RFC 9457 shape #{code}")
    check(example.fetch('status') == problem_statuses.fetch(name), "status for #{code}")
  end
end
check(seen_codes.uniq.sort == problem_codes.sort, 'documented example for every stable problem code')
sensitive_problem = components.fetch('responses').fetch('RejectedRequest').fetch('content')
                              .fetch('application/problem+json').fetch('examples').fetch('sensitive').fetch('value')
check(sensitive_problem.fetch('status') == 422 &&
      sensitive_problem.fetch('code') == 'sensitive_request_not_supported', 'sensitive 422 example')

events = paths.fetch('/v1/decider/events').fetch('get')
check(events.fetch('parameters').first.fetch('name') == 'Last-Event-ID', 'SSE resume header')
frame = events.fetch('responses').fetch('200').fetch('content').fetch('text/event-stream').fetch('example')
check(frame.lines.any? { |line| line.start_with?('id: ') }, 'SSE opaque event ID')
check(frame.lines.any? { |line| line.strip == 'event: request.created' }, 'SSE created event')
event_data = JSON.parse(frame.lines.find { |line| line.start_with?('data: ') }.delete_prefix('data: '))
check(event_data == snapshot, 'SSE carries the full example snapshot')
cursor_loss = response(components, events, 409).fetch('content').fetch('application/problem+json').fetch('example')
check(cursor_loss.fetch('status') == 409 && cursor_loss.fetch('code') == 'event_cursor_unavailable',
      'SSE replay-loss response')
list_schema = paths.fetch('/v1/decider/requests').fetch('get').fetch('responses').fetch('200')
                   .fetch('content').fetch('application/json').fetch('schema')
check(list_schema.fetch('$ref') == '#/components/schemas/PendingRequestList', 'snapshot cursor response')
check(components.fetch('schemas').fetch('PendingRequestList').fetch('properties').fetch('requests')
                .fetch('maxItems') == 100, 'pending list capacity')

puts 'Contract validation passed'
