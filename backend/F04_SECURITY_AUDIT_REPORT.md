# F04 Security Audit Report

**Status:** PASS WITH FINDINGS
**Scope:** F04-A, F04-B1, F04-B2, F04-B3, F04-B4, sensitive logging, authentication rate limiter, JWT revocation persistence, and transaction rollback
**Repository:** `D:/sistem-penjualan-umkm`
**Source of truth:** `docs/SECURITY.md`, `docs/DEVELOPMENT_PLAN.md`, `docs/API_DOCUMENTATION.md`, `docs/AGENTS.md`
**Snapshot HEAD during pre-commit review:** `9781a74`

This report records verified F04 work only. It does not claim database-level immutability, production readiness, or that all security risks are closed. Claims below are backed by the referenced implementation and tests; production SQL bind logging remains unverified.

---

## 1. Summary

F04 hardening is implemented and the backend test suite passes on the reviewed snapshot. The report records audit-log model protection, account state consistency, registration/logout events, JWT and authorization security events, logger reliability, sensitive-data logging protections, the authentication rate limiter, database-backed JWT revocation, and four audit-log transaction rollback tests.

- Full backend suite (serial): **134 examples, 0 failures, 2 pending, exit code 0**.
- The 2 pending examples are environment-limited symlink tests, not failures.
- Open residual risk: **production SQL bind logging has not been verified through a production runtime**.

---

## 2. Requirement coverage

### 2.1 F04-A — AuditLog integrity

Implementation: `backend/app/models/audit_log.rb`.

- AuditLog permits creation of new records (`create` / `create!`), because a new record is not `persisted?`.
- A persisted record is treated as read-only: `readonly?` returns `persisted? || super`.
- Because the record is read-only once persisted, the following model methods are rejected with `ActiveRecord::ReadOnlyRecord`:
  - `update`
  - `update!`
  - `destroy`
  - `destroy!`
- `delete` is explicitly guarded and raises `ActiveRecord::ReadOnlyRecord` when `readonly?` is true.
- Tests: `backend/spec/models/audit_log_spec.rb` (6 examples) cover create, update, update!, destroy, destroy!, and delete, and assert the stored record is unchanged.

Limitations (explicitly not a database-level immutability guarantee):

- `delete_all`, `update_all`, `update_columns`, and raw SQL (`exec_query`, direct database access) can bypass Active Record model guards.
- Protection is enforced at the application model layer only; it is not a database constraint, trigger, or cryptographic immutability control.
- These bypass paths are recorded as known limitations and are not mitigated by this work.

### 2.2 F04-B1 — Account state consistency

Implementation: `backend/app/controllers/auth_controller.rb` (`login`).

- Login requires both valid credentials and `user.is_active?`.
- An inactive account cannot log in.
- The response for an inactive account is the same generic failure used for bad credentials: HTTP 401 with error code `INVALID_CREDENTIALS` and message "Email atau password tidak valid." Account status is not disclosed.
- No JWT is issued for an inactive account.
- No success event is emitted for an inactive account; the branch falls through to the failure path.
- Tests: `backend/spec/requests/auth_spec.rb` — "rejects inactive accounts at login with the same generic response and no token" asserts identical response bodies for inactive account and wrong password, no token, and absence of `ACCOUNT_INACTIVE` in the login response.

Note: a previously issued token for an account that later becomes inactive is rejected during authentication with `ACCOUNT_INACTIVE`, and that path emits `auth.jwt.account_inactive` (see F04-B3).

### 2.3 F04-B2 — Registration and logout events

Implementation: `backend/app/controllers/auth_controller.rb`.

Events emitted:

- `auth.register.success` — after a successful save, including `user_id`.
- `auth.logout.success` — after token revocation, including `user_id`.
- `auth.logout.failure` — with an implemented `reason`:
  - `token_missing` — no bearer token presented.
  - `authentication_failed` — token invalid or could not be authenticated.
  - `revocation_failed` — token revocation storage write failed.

Test coverage: `backend/spec/requests/auth_spec.rb` asserts these events, that no success event is emitted on failed registration/logout, and that the emitted JSON does not contain the token, Authorization header, user email, or JWT secret.

### 2.4 F04-B3 — JWT and authorization security events

Implementation: `backend/app/controllers/application_controller.rb`, `backend/app/services/jwt_service.rb`.

Verified events:

- `auth.jwt.invalid` — malformed, incorrectly signed, or missing-claim token.
- `auth.jwt.expired` — expired token (distinct status from invalid).
- `auth.jwt.revoked` — token found in the revocation store.
- `auth.jwt.revocation_unavailable` — revocation store could not be read; treated as unauthorized.
- `auth.jwt.user_missing` — token valid but referenced user no longer exists.
- `auth.jwt.account_inactive` — token valid and user exists but is inactive.
- `auth.authorization.denied` — authenticated user lacks the required role; includes `required_role` (`admin` or `customer`).

Validation ordering and data safety:

- `user_id` is recorded only after the JWT signature, algorithm, expiration, and required claims (`user_id`, `jti`, validated `exp`) have been verified.
- For invalid or expired tokens, the event records no `user_id` taken from unvalidated claims.
- `auth.jwt.user_missing` does not record the unvalidated claim `user_id`.

Test coverage: `backend/spec/requests/auth_spec.rb` (invalid, expired, revoked, revocation storage failure, user missing, account inactive, authorization denied) and `backend/spec/services/jwt_service_spec.rb` (status classification, fail-closed behavior).

### 2.5 F04-B4 — Logger reliability

Implementation: `backend/app/controllers/application_controller.rb#log_security_event`; `backend/app/services/auth_rate_limiter.rb` (`log_event`, `log_failure`, `fallback_log`).

- Nested rescue: a logging failure is caught, then a minimal fallback is attempted, and any fallback failure is swallowed so it cannot recurse.
- Non-recursive `Kernel.warn` fallback: fallback writes do not call the application logger again.
- Fallback entries carry `degraded: true`, plus a safe `event`/`source` label only.
- Logger failure does not change authentication, authorization, or API response outcomes; responses are produced independently of logging success.
- Tests: `backend/spec/requests/logging_security_spec.rb` verifies authentication (200) and authorization (403) results are preserved when the structured logger raises, that fallback warnings contain `degraded` but not the token, email, or exception message, and that logger failure details are not exposed to clients.

### 2.6 Sensitive logging

Implementation: `backend/config/initializers/filter_parameter_logging.rb`; event payloads in `application_controller.rb` and `auth_rate_limiter.rb`.

- Parameter filtering is configured for at least: `passw`, `email`, `secret`, `token`, `_key`, `crypt`, `salt`, `certificate`, `otp`, `ssn`, `cvv`, `cvc`, `password`, `password_confirmation`, `access_token`.
- Security event payloads are structured and intentionally limited to non-secret fields: `event`, `ip`, `user_id`, `reason`, `required_role`, `degraded`, and operation/error-class labels.
- Password, JWT, Authorization header, JWT secret, raw email, and exception messages are not emitted by the reviewed logging paths.
- Tests: `backend/spec/requests/sensitive_logging_spec.rb` (6 examples) and the first example of `backend/spec/requests/logging_security_spec.rb`.

Limitation: `filter_parameters` filters request parameters in Rails request logs. It does **not** filter Active Record SQL bind values (see residual risks).

### 2.7 Authentication rate limiter

Implementation: `backend/app/services/auth_rate_limiter.rb`; request handling in `backend/app/controllers/auth_controller.rb`.

Actual configuration:

- Login IP: **30 requests per minute** (`LOGIN_IP_LIMIT` default 30, `LOGIN_IP_WINDOW` = 1 minute).
- Registration IP: **5 requests per 10 minutes** (`REGISTER_IP_LIMIT` default 5, `REGISTER_IP_WINDOW` = 10 minutes).
- Login failure window: **15 minutes** (`LOGIN_FAILURE_WINDOW`).
- Progressive delay: begins at **5 failures**, `0.25 * 2**(failures - 5)` seconds, capped at **2 seconds**.
- Email identifier: **HMAC-SHA256** digest; raw email is not used as a storage key.
- Client IP source: **`REMOTE_ADDR`** via Rack. `X-Forwarded-For` is not trusted until a trusted reverse-proxy boundary is defined and enforced in deployment.
- Rate-limited response: **HTTP 429** with a `Retry-After` header.
- Storage failure behavior: **fail-open** with a `degraded: true` marker; a counter-storage error does not block authentication attempts.
- Counter storage is atomic (`AuthRateLimitCounter` update with expiry-aware increment) and expired counters are cleaned in bounded batches.

Tests: `backend/spec/services/auth_rate_limiter_spec.rb` (25 examples) covers HMAC key derivation, atomic increment, window reset, degraded storage failure, cleanup and batch bounds, concurrency, and configuration validation. `backend/spec/requests/auth_spec.rb` covers IP rate limiting and window expiry behavior.

Note: the login/registration limits are only as strong as the `REMOTE_ADDR` trust model; behind an untrusted proxy boundary this must be revisited at deployment.

### 2.8 JWT revocation persistence

Implementation: `backend/app/services/jwt_service.rb`, `backend/app/models/jwt_revocation.rb`, migration `2026110600002_create_jwt_revocations.rb`.

- Revocation is persisted in the database (`jwt_revocations`) with a unique index on `jti` and an index on `expires_at`.
- Revocation is idempotent via `create_or_find_by!(jti: ...)`; repeated or concurrent logout attempts do not create duplicates.
- Already-expired tokens are not stored.
- Storage failure is **fail-closed**: if the revocation store cannot be read, `revocation_status` returns `:unavailable`, `revoked?` returns true, and authentication rejects the token. This prevents a storage outage from making a revoked token usable.
- Tests: `backend/spec/services/jwt_service_spec.rb` and `backend/spec/requests/auth_spec.rb` (revocation persistence across connection reinitialization, storage-read failure fail-closed, storage-write failure returning 503 without internal details).

### 2.9 Transaction rollback when AuditLog creation fails

Four service-level rollback tests exist and were executed. Each stubs `AuditLog.create!` to raise `ActiveRecord::StatementInvalid` inside the service transaction and asserts that all business changes and the audit record are rolled back.

- PaymentApprovalService — `backend/spec/requests/payments_spec.rb` (`rolls back payment approval when the audit log cannot be created`): payment remains `waiting_verification`, order remains `awaiting_payment`, product stock/reserved unchanged, proof remains `submitted`, no `PaymentVerificationEvent`, no audit record.
- CancellationService — `backend/spec/requests/order_shipping_spec.rb` (`rolls back cancellation approval when the audit log cannot be created`): order remains `awaiting_payment`, cancellation remains `pending`, payment remains `pending`, reserved stock unchanged, reservation remains `reserved`, no audit record.
- ShipmentService — `backend/spec/requests/order_shipping_spec.rb` (`rolls back shipment creation when the audit log cannot be created`): order remains `processing`, no shipment, no audit record.
- OrderCompletionService — `backend/spec/requests/order_shipping_spec.rb` (`rolls back automatic order completion when the audit log cannot be created`): order remains `shipped`, `completed_at` nil, no audit record.

The corresponding services call `AuditLog.create!` inside `ActiveRecord::Base.transaction`, so the exception propagates and rolls back the enclosing transaction.

---

## 3. Test results

Command (serial, PowerShell on Windows):

```
cd backend
$env:RAILS_MAX_THREADS=1
bundle exec rspec --format progress
```

Actual result:

```
134 examples, 0 failures, 2 pending
Finished in 3.72 seconds
EXIT_CODE=0
```

Pending examples (expected; not failures):

1. `spec/services/verified_storage_file_spec.rb:45` — "rejects a symlink to a file outside the root".
2. `spec/services/verified_storage_file_spec.rb:54` — "rejects a symlink to a file inside the root".

Both are pending because symlink creation is unavailable on this Windows filesystem. They are environment limitations, not test failures.

Environment-only warnings observed (not failures): VIPS optional module load warnings and a Rack `:unprocessable_entity` deprecation notice. No SQLite locking occurred in the serial run.

The full-suite figure above is the authoritative result for this report. Older, narrower counts (for example, auth-only counts) are not used as the full backend suite result.

---

## 4. Residual risks and limitations

1. **Production SQL bind logging is not verified.** It has not been observed through a production runtime in this audit.
2. **Debug log level can expose SQL bind values.** The production default is `log_level = "info"`, which suppresses Active Record SQL debug output, but `RAILS_LOG_LEVEL=debug` would cause SQL statements and bind values to be logged.
3. **`filter_parameters` does not protect SQL bind values.** Parameter filtering applies to request parameters, not to Active Record SQL bind payloads.
4. **AuditLog model protection is bypassable.** Bulk operations (`delete_all`, `update_all`, `update_columns`) and raw SQL can bypass model-level guards. This is not database-level immutability.
5. **IP addresses are recorded in security events.** A retention policy for IP/user-agent data remains to be defined per `docs/SECURITY.md` privacy/retention requirements.
6. **Two symlink tests are pending** on the Windows filesystem and are not executed there.
7. **Rate limiting trusts `REMOTE_ADDR`.** Correct client-IP attribution depends on a deployment-defined trusted proxy boundary; `X-Forwarded-For` is intentionally not trusted yet.

These items are open. They do not indicate that all security risks are resolved.

---

## 5. Git snapshot and scope of change

Snapshot recorded during the pre-commit review:

- Branch: **main** (`main...origin/main`).
- HEAD: **`9781a74`**.
- Modified tracked files: **9**.
- Untracked files: **4**.
- Staged files: **0**.

The 9 modified tracked files:

1. `backend/app/controllers/application_controller.rb`
2. `backend/app/controllers/auth_controller.rb`
3. `backend/app/models/audit_log.rb`
4. `backend/app/services/auth_rate_limiter.rb`
5. `backend/app/services/jwt_service.rb`
6. `backend/spec/requests/auth_spec.rb`
7. `backend/spec/requests/order_shipping_spec.rb`
8. `backend/spec/requests/payments_spec.rb`
9. `backend/spec/services/jwt_service_spec.rb`

The 4 untracked files:

1. `backend/F04_SECURITY_AUDIT_REPORT.md` (this report)
2. `backend/spec/models/audit_log_spec.rb`
3. `backend/spec/requests/logging_security_spec.rb`
4. `backend/spec/requests/sensitive_logging_spec.rb`

The working tree was **not clean** at review time. These counts are a snapshot from that pre-commit review and are not a guarantee of Git state after that point.

---

## 6. Conclusion

**PASS WITH FINDINGS.**

The F04 implementation and its tests pass based on the available evidence: 134 examples, 0 failures, 2 environment-limited pending tests, exit code 0. Audit-log model protection, account state consistency, registration/logout events, JWT/authorization events, logger reliability, sensitive-data logging protections, the authentication rate limiter, database-backed fail-closed JWT revocation, and four audit-log transaction rollback tests are implemented and covered by tests.

Production SQL bind logging remains an unverified residual risk, and the limitations in Section 4 remain open. This report does not assert that the system is production-ready or that all security risks have been closed.
