# Windows IPsec IKEv2 Site-to-Site VPN (RRAS)

A complete PowerShell toolkit for setting up, verifying, and troubleshooting IPsec IKEv2 site-to-site VPN tunnels on Windows Server using RRAS.

Built and tested during a real-world deployment connecting a Windows trading server to a remote financial gateway running Cisco ASA. Every script, every error, and every fix in this repo came from that live deployment.

---

## Why RRAS and Not Windows Native IPsec?

Windows native IPsec (`New-NetIPsecRule`) has a hard limitation in tunnel mode — it always uses its own built-in default Phase 1 crypto (DHGroup2, AES-128, SHA-1) regardless of any custom crypto sets you create. The `-MainModeCryptoSet` parameter does not exist on tunnel mode rules. This applies to both Windows Server 2019 and 2022.

You can confirm this yourself:

```powershell
netsh advfirewall consec show rule name="YOUR-TUNNEL" verbose
# MainModeSecMethods will always show: DHGroup2-AES128-SHA1
```

RRAS has its own IKEv2 stack with full crypto control through `-CustomPolicy`.

---

## Requirements

- Windows Server 2019 or 2022
- Administrator privileges
- Remote Access Windows feature
- PSK stored as environment variable — never hardcoded

---

## Quick Start

```
1. Edit config/tunnel-params.ps1 with your values
2. Set your PSK: $env:VPN_PSK = "your-psk-here"
3. Run scripts/01-setup-rras.ps1
4. Run scripts/02-create-tunnel.ps1
5. Run scripts/03-set-traffic-selectors.ps1
6. Run scripts/04-verify-tunnel.ps1
7. Run scripts/05-test-connection.ps1
```

---

## The Three Things That Will Break Your Tunnel

These are the three root causes discovered during real-world deployment. If your tunnel is not connecting, one of these is why.

**1. Windows native IPsec ignores your Phase 1 crypto**
Native IPsec tunnel mode always falls back to DHGroup2/AES128/SHA1. Switch to RRAS.

**2. Old native IPsec rules send IKEv1 alongside your IKEv2**
If you tried native IPsec first and then switched to RRAS, the old rules are still active and sending IKEv1 traffic. The remote gateway sees mixed traffic and logs errors. Remove all native rules.

```powershell
Get-NetIPsecRule | Remove-NetIPsecRule -ErrorAction SilentlyContinue
Get-NetIPsecMainModeRule | Remove-NetIPsecMainModeRule -ErrorAction SilentlyContinue
```

**3. RRAS sends wildcard traffic selectors 0.0.0.0/0 by default**
If the remote gateway has a crypto map configured for specific IP ranges (which Cisco ASA does), it will reject wildcard selectors with "Crypto Map Policy not found". Always set explicit traffic selectors using `New-VpnTrafficSelector`.

---

## Documentation

| Document | What it covers |
|---|---|
| [Troubleshooting](docs/troubleshooting.md) | All errors encountered and how each was fixed |
| [Windows IPsec Limitations](docs/windows-ipsec-limitations.md) | Why native IPsec fails and why RRAS is the solution |
| [Corporate Guide](docs/corporate-guide.md) | Security, architecture, firewall config, best practices |
| [Deployment Log](docs/deployment-log.md) | Chronological record of the real-world deployment |

---

## Supported Algorithms

### Phase 1
| Parameter | Supported Values |
|---|---|
| Encryption | AES128, AES192, AES256 |
| Integrity | SHA256, SHA384, SHA512 |
| DH Group | DH14, ECP256 (Group 19), ECP384 (Group 20), ECP521 (Group 21) |

### Phase 2
| Parameter | Supported Values |
|---|---|
| Protocol | ESP |
| Encryption | AES128, AES192, AES256 |
| Integrity | SHA256128 (=SHA256), SHA384, SHA512 |
| PFS Group | DH14, ECP256, ECP384 |

> **Note:** Windows RRAS displays SHA-256 as `SHA256128`. This is the standard HMAC-SHA-256 algorithm. Wireshark confirms it sends `AUTH_HMAC_SHA2_256_128` which is correct per RFC 4307.

---

## License

MIT
