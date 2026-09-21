# Windows Native IPsec Limitations in Tunnel Mode

## The Problem

Windows native IPsec through PowerShell has a hard limitation in tunnel mode. You cannot control Phase 1 crypto. Windows always uses its own built-in default MainMode crypto set regardless of what you configure.

The built-in set contains:
- DHGroup2 with AES-128 and SHA-1
- DHGroup2 with 3DES and SHA-1

If your remote gateway requires AES-256, SHA-384, or DH Group 19 — native IPsec will never connect.

**Confirmed on:** Windows Server 2019 (Build 17763) and Windows Server 2022

---

## Everything That Was Tried

| Method | Result |
|---|---|
| `New-NetIPsecRule -MainModeCryptoSet` | Parameter does not exist |
| `Set-NetIPsecRule -MainModeCryptoSet` | Parameter does not exist |
| `New-NetIPsecRule -KeyModule IKEv2` | HRESULT 0x80070057 — Invalid Argument for tunnel mode |
| `netsh advfirewall consec add rule ... mmsecmethods=dhgroup19` | Parameter not valid |
| `netsh advfirewall set global mainmode mmsecmethods ecdhp256:aes256-sha384` | Accepted but ignored for tunnel mode rules |
| CIM/WMI `Set-CimInstance ... MainModeCryptoSet` | Accepted without error but silently ignored |
| Registry `HKLM\Services\IKEEXT\Parameters` | No effect on tunnel mode crypto |
| Group Policy IP Security Policies | Only offers MD5, SHA1, DES, 3DES — no AES, no SHA256+ |
| Upgrading to Windows Server 2022 | Same limitation — no change |

---

## Why It Happens

Windows assigns the built-in GUID `{E5A5D32A-4BCE-4e4d-B07F-4AB1BA7E5FE1}` to all tunnel mode rules. This GUID is embedded in the IPsec driver, not accessible through any PowerShell cmdlet, and cannot be overridden by any external configuration.

You can see it yourself:
```powershell
Get-NetIPsecRule -DisplayName "YOUR-TUNNEL" | Select-Object MainModeCryptoSet
# MainModeCryptoSet: {E5A5D32A-4BCE-4e4d-B07F-4AB1BA7E5FE1}  ← always this
```

And it cannot be queried:
```powershell
Get-NetIPsecMainModeCryptoSet -Name "{E5A5D32A-4BCE-4e4d-B07F-4AB1BA7E5FE1}"
# Error: No MSFT_NetIKEMMCryptoSet objects found
```

---

## The Solution — RRAS

RRAS (Routing and Remote Access Service) has its own separate IKEv2 stack that bypasses all of these limitations entirely. Use `Set-VpnS2SInterface -CustomPolicy` to specify exact crypto.

```powershell
Set-VpnS2SInterface -Name "VPN-Primary" -CustomPolicy `
    -EncryptionMethod AES256 `
    -IntegrityCheckMethod SHA384 `
    -DHGroup ECP256 `
    -CipherTransformConstants AES256 `
    -AuthenticationTransformConstants SHA256128 `
    -PfsGroup ECP256
```

---

## Algorithm Name Mapping

| Standard Name | RRAS Parameter Value | Notes |
|---|---|---|
| AES-128 | AES128 | |
| AES-192 | AES192 | |
| AES-256 | AES256 | |
| SHA-256 | SHA256128 | Windows internal name — correct algorithm |
| SHA-384 | SHA384 | |
| SHA-512 | SHA512 | |
| DH Group 14 | DH14 | 2048-bit MODP |
| DH Group 19 | ECP256 | 256-bit Elliptic Curve — most commonly required |
| DH Group 20 | ECP384 | 384-bit Elliptic Curve |
| DH Group 21 | ECP521 | 521-bit Elliptic Curve |

**On SHA256128:** Windows RRAS displays SHA-256 as `SHA256128`. This is the standard HMAC-SHA-256 algorithm — the 128 refers to the output truncation length per RFC 4307. Wireshark shows it as `AUTH_HMAC_SHA2_256_128`. Cisco, Palo Alto and other vendor gateways accept it as SHA-256.
