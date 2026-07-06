# Licensing & Free Trial - Deep Dive

## Purpose

The Licensing feature implements Polar-based license key validation, device activation, a 7-day free trial, and app gating for Yapper. It acts as a blocking gate at app startup - the application cannot proceed to normal operation without a valid license or active trial.

---

## User-Facing Behavior

| Action | Result |
|--------|--------|
| First launch (no license) | 7-day free trial starts automatically, toast confirms "Free trial started - 7 days" |
| During trial | Settings > Preferences shows orange trial badge with remaining days + "Buy a license" link |
| Mid-trial purchase | Trial badge disappears, transitions to fully licensed state |
| Trial expires | Modal: "Your Free Trial Has Ended" with "Buy Yapper" + "I Already Have a License" buttons |
| Enter valid license key | Device activated with Polar API, app proceeds |
| Enter invalid key | Error message displayed |
| Enter key at device limit | "Device Limit Reached" screen with portal link |
| License expires | Shows expired state, prompts renewal |
| License revoked | Shows revoked state, prompts support contact |
| Network error during validation | Shows error with retry option |
| Deactivate license (Settings) | Confirmation dialog, then app terminates |
| Click "Purchase License" / "Buy Yapper" | Opens `https://yapper.to/` in browser |
| Click "Manage Devices" | Opens Polar customer portal |
| Click "Quit Yapper" | App terminates immediately |

---

## Public Interface

### LicenseService (Singleton)

| Method/Property | Description |
|-----------------|-------------|
| `LicenseService.shared` | Singleton instance |
| `checkLicenseOnLaunch() async -> Bool` | Check cached license on startup |
| `activateLicense(key:) async throws` | Activate new license key |
| `validateLicense() async throws` | Revalidate existing license |
| `deactivateLicense() async throws` | Deactivate and clear local cache |
| `licenseState: LicenseState` | Current license state |
| `licenseInfo: LicenseInfo?` | Cached license details |

### LicenseState Enum

```swift
enum LicenseState: Equatable {
    case unknown              // Initial, not yet checked
    case unlicensed           // No license key stored
    case valid                // License is valid and active
    case expired              // License has expired
    case revoked              // License has been revoked
    case activationLimitReached  // Too many activations
    case validating           // Currently validating
    case networkError(String) // Network error
    case trialActive(daysRemaining: Int)  // Free trial active (v2.0)
    case trialExpired         // Free trial expired (v2.0)

    var isValid: Bool        // Only true for .valid
    var canUseApp: Bool      // True for .valid AND .trialActive
}
```

### LicenseInfo Struct

```swift
struct LicenseInfo: Codable {
    let licenseKey: String
    let activationId: String
    let expiresAt: Date?
    let status: String
    let validatedAt: Date
    let customerEmail: String?
    var isExpired: Bool      // Computed from expiresAt
}
```

### LicenseError Enum

```swift
enum LicenseError: LocalizedError {
    case invalidKey
    case keyExpired
    case keyRevoked
    case activationLimitReached
    case networkError(underlying: Error)
    case invalidResponse
    case noActivationId
}
```

### LicenseService (new methods)

| Method/Property | Description |
|-----------------|-------------|
| `setTrialState(_ state: LicenseState)` | MainActor-isolated: set trial state |

### TrialService (NEW - v2.0)

**Location**: `Yapper/Services/TrialService.swift` (175 lines)

| Method/Property | Description |
|-----------------|-------------|
| `TrialService.shared` | Singleton instance |
| `checkOrStartTrial() -> TrialResult` | Check existing trial or start new one |
| `touchLastSeen()` | Update lastSeenAt for clock rollback detection |

### Notifications

| Notification | Purpose |
|--------------|---------|
| `.licenseStateChanged` | Broadcast when license state changes |

---

## Implementation Notes

### Polar API Integration

Three endpoints:

1. **Activate** (`POST /v1/customer-portal/license-keys/activate`)
   - Request: `{ key, organization_id, label }`
   - Label: `"{hostname} - Yapper"`
   - Response includes activation ID

2. **Validate** (`POST /v1/customer-portal/license-keys/validate`)
   - Request: `{ key, organization_id, activation_id }`
   - Re-verifies expired cached licenses

3. **Deactivate** (`POST /v1/customer-portal/license-keys/deactivate`)
   - Request: `{ key, organization_id, activation_id }`
   - Clears local data regardless of server response

### Debug vs Release API Endpoints

```swift
#if DEBUG
    baseURL = "https://sandbox-api.polar.sh"
    organizationId = "bba446c3-e743-41a8-ac96-6491e122902d"
#else
    baseURL = "https://api.polar.sh"
    organizationId = "3344d11b-ac0a-4beb-8f65-0fd69f2fa7ae"
#endif
```

Environment overrides:
- `POLAR_USE_SANDBOX=1` - Force sandbox in Release
- `POLAR_USE_PRODUCTION=1` - Force production in Debug

### Offline License Caching

UserDefaults keys prefixed `com.yapper.license.`:
- `key` - License key string
- `activationId` - Device-specific activation ID
- `expiresAt` - Timestamp
- `status` - License status ("granted", "revoked")
- `validatedAt` - Last validation timestamp
- `customerEmail` - Customer's email

### TrialService Implementation (v2.0)

**Storage**: macOS Keychain with opaque identifiers:
- Service: `"app.persistence.layer"`
- Account: `"session.token.v1"` (payload), `"install.marker.v1"` (tombstone)
- Accessibility: `kSecAttrAccessibleAfterFirstUnlock`

**Payload**: JSON-encoded `TrialPayload` struct: `startedAt`, `lastSeenAt`, `signature`

**Security**:
- HMAC-SHA256 signing over `"yapper.trial.v1:{startedAt}:{bundleId}"` with 32-byte embedded key
- Tamper detection: invalid HMAC immediately expires trial
- Tombstone pattern: empty Keychain item survives payload deletion, preventing fresh-start bypasses
- Clock rollback detection: if `now < lastSeenAt`, trial expires

**Decision table (`checkOrStartTrial()`)**:
| Condition | Result |
|-----------|--------|
| No payload + no tombstone | First launch → `.active(7)` |
| No payload + tombstone | Deletion attack → `.expired` |
| Bad HMAC | Tampered → `.expired` |
| Clock rollback (`now < lastSeenAt`) | `.expired` |
| Elapsed >= 7 days | `.expired` |
| Elapsed < 7 days | `.active(remaining)` |
| Keychain unavailable on first launch | Grant trial, retry on next launch |

### Startup License Check Flow (v2.0)

```
App Launch
    │
    ▼
checkLicenseOnLaunch() (Polar)
    │
    ├─ Valid Polar license?
    │       └─► Return true (valid)
    │
    ├─ No cached license / check fails?
    │       └─► TrialService.shared.checkOrStartTrial()
    │               │
    │               ├─ .active(daysRemaining) → Set trial state, touchLastSeen(), proceed
    │               │   └─ First trial? Show welcome toast (keyed by com.yapper.trial.welcomed)
    │               │
    │               └─ .expired → Set state, show license activation modal
    │
    ├─ Cached license expired?
    │       └─► Validate with server
    │               ├─ Success: Update cache, return true
    │               └─ Failure: Fall through to trial check
    │
    └─ Cached license not expired?
            └─► Return true (valid)
```

---

## State & Data

### State Management

- `LicenseService` maintains `licenseState` and `licenseInfo` as `@MainActor` properties
- `AppState` mirrors with `isLicenseValid`, `licenseExpiresAt`, `licenseCustomerEmail`
- `AppState` trial state: `isInTrial: Bool`, `trialDaysRemaining: Int?`
- `AppState` methods: `updateTrialState(daysRemaining:)`, `markTrialExpired()`
- `updateLicenseState(isValid:...)` clears trial state when a real license is activated
- Synchronization via `Notification.Name.licenseStateChanged`

### New UserDefaults Key

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `com.yapper.trial.welcomed` | Bool | false | Whether trial welcome toast was shown |

### Data Flow

```
LicenseService                AppState                    UI
     │                           │                         │
     │──licenseStateChanged───►│                          │
     │                         │──updateLicenseState()─►│
     │                         │                         │
     │◄──────────────────────────────activateLicense()───│
     │                                                    │
     │──post(.licenseStateChanged)───────────────────────►│
```

---

## Edge Cases & Gotchas

1. **Network Error with Valid Cache**: Shows error state rather than allowing continued use

2. **Deactivation Always Succeeds Locally**: Clears local data even if server request fails

3. **No Offline Grace Period**: No grace period for offline use

4. **Modal Window Cannot Be Dismissed**: Uses `.modalPanel` level

5. **Activation ID Dependency**: Required for validation/deactivation; if lost, user must contact support

6. **ISO8601 Date Parsing Fragility**: Two parsing attempts for date formats

7. **Organization ID Hardcoded**: Requires code changes if organization changes

8. **Duplicate URL Configuration**: Environment logic duplicated between service and view

9. **Termination on Deactivation**: App terminates rather than returning to activation modal

10. **Purchase URL**: Now points to `https://yapper.to/` (previously Polar storefront with conditional sandbox/production branching)

---

## Technical Debt

1. **Sendable Conformance**: Uses `@unchecked Sendable` instead of proper actor isolation

2. **Code Duplication**: Environment detection duplicated between files

3. **No License Key Format Validation**: Any string accepted as license key

4. **Hardcoded Organization IDs**: Should move to Info.plist

5. **No Keychain Usage**: License keys in UserDefaults instead of Keychain

6. **Missing Revalidation Schedule**: No periodic background revalidation

7. **Error Messages Exposure**: Technical URLSession errors shown to users

8. **No Unit Tests**: Critical infrastructure without visible tests

---

## Files

| File | Lines | Purpose |
|------|-------|---------|
| `Yapper/Services/LicenseService.swift` | 728 | Polar API integration + trial state cases |
| `Yapper/Services/TrialService.swift` | 175 | 7-day trial (Keychain, HMAC-SHA256, tombstone) |
| `Yapper/Views/LicenseActivationView.swift` | ~450 | Activation UI + trial expired modal |
| `Yapper/Views/LicenseWindowController.swift` | 103 | Modal window management |
