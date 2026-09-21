# Deployment Log

This is a chronological record of the real-world deployment. It documents every approach tried, every error hit, and every fix applied. It is kept here so anyone troubleshooting a similar setup does not have to start from zero.

---

## Phase 1 — Windows Native IPsec (Did Not Work)

**Approach:** Used PowerShell cmdlets to create IPsec tunnel rules with custom Phase 1 and Phase 2 crypto sets.

**What was configured:**
```powershell
New-NetIPsecMainModeCryptoSet -DisplayName "MM-Crypto" -Proposal (New-NetIPsecMainModeCryptoProposal -Encryption AES256 -Hash SHA384 -KeyExchange DH19) -MaxMinutes 1440
New-NetIPsecQuickModeCryptoSet -DisplayName "QM-Crypto" -Proposal (New-NetIPsecQuickModeCryptoProposal -Encryption AES256 -ESPHash SHA256 -Encapsulation ESP) -PfsGroup DH19
New-NetIPsecPhase1AuthSet -DisplayName "PSK-Auth" -Proposal (New-NetIPsecAuthProposal -Machine -PreSharedKey $env:VPN_PSK)
New-NetIPsecRule -DisplayName "Primary-Tunnel" -Mode Tunnel -LocalAddress "LOCAL_IP" -RemoteAddress "REMOTE_SUBNET" -LocalTunnelEndpoint "LOCAL_IP" -RemoteTunnelEndpoint "REMOTE_GATEWAY" -Phase1AuthSet $auth -QuickModeCryptoSet $qm
```

**What happened:** Everything was created without errors. But checking the actual negotiation:
```powershell
netsh advfirewall consec show rule name="Primary-Tunnel" verbose
# MainModeSecMethods: DHGroup2-AES128-SHA1  ← always this, regardless of config
```

**Root cause:** Windows tunnel mode rules always use the built-in default MainMode crypto set `{E5A5D32A-4BCE-4e4d-B07F-4AB1BA7E5FE1}`. The `-MainModeCryptoSet` parameter does not exist. Custom sets are created but never linked to tunnel rules.

**Attempts that also failed:**
- `Set-NetIPsecRule -MainModeCryptoSet` — parameter does not exist
- `Set-NetIPsecRule -KeyModule IKEv2` — HRESULT 0x80070057 Invalid Argument
- `netsh advfirewall consec add rule ... mmsecmethods=dhgroup19-aes256-sha384` — parameter not valid
- CIM/WMI direct injection of MainModeCryptoSet — silently ignored
- Registry modifications to IKEEXT service — no effect on tunnel mode
- Group Policy IP Security Policies — only offers MD5, SHA1, DES, 3DES — no AES or SHA256+
- Upgrading from Windows Server 2019 to 2022 — same limitation exists on 2022

**Resolution:** Abandoned native IPsec entirely. Switched to RRAS.

---

## Phase 2 — RRAS Setup

**Approach:** Installed RRAS and used `Add-VpnS2SInterface` with `-CustomPolicy`.

**Installation:**
```powershell
Install-WindowsFeature RemoteAccess, Routing, RSAT-RemoteAccess -IncludeManagementTools
```
Then configured as LAN router through rrasmgmt.msc.

**Tunnel creation:**
```powershell
Add-VpnS2SInterface -Name "VPN-Primary" -Destination "REMOTE_GATEWAY" -Protocol Ikev2 `
    -AuthenticationMethod PSKOnly -SharedSecret $env:VPN_PSK `
    -EncryptionType MaximumEncryption -IPv4Subnet "REMOTE_SUBNET:10" `
    -SALifeTime 28800 -MMSALifeTime 86400 -SourceIpAddress "LOCAL_IP" `
    -ResponderAuthenticationMethod PSKOnly

Set-VpnS2SInterface -Name "VPN-Primary" -CustomPolicy `
    -EncryptionMethod AES256 -IntegrityCheckMethod SHA384 -DHGroup ECP256 `
    -CipherTransformConstants AES256 -AuthenticationTransformConstants SHA256128 `
    -PfsGroup ECP256
```

**Result:** RRAS created correctly. IKEv2 SA Init started but still failing.

---

## Problem 1 — IKEv1 Traffic Interfering

**Symptom:** Remote Cisco gateway logs showed `IKE MM` errors (Main Mode = IKEv1 term).

**Diagnosis:** Old native Windows IPsec tunnel rules from Phase 1 were still active and sending IKEv1 traffic to the remote gateway at the same time as RRAS was sending IKEv2. The remote Cisco saw mixed traffic.

**Fix:**
```powershell
Get-NetIPsecRule          | Remove-NetIPsecRule          -ErrorAction SilentlyContinue
Get-NetIPsecMainModeCryptoSet  | Remove-NetIPsecMainModeCryptoSet  -ErrorAction SilentlyContinue
Get-NetIPsecQuickModeCryptoSet | Remove-NetIPsecQuickModeCryptoSet -ErrorAction SilentlyContinue
Get-NetIPsecPhase1AuthSet | Remove-NetIPsecPhase1AuthSet -ErrorAction SilentlyContinue
Get-NetIPsecMainModeRule  | Remove-NetIPsecMainModeRule  -ErrorAction SilentlyContinue
```

**Result:** IKEv1 traffic stopped. RRAS now the only sender. IKEv2 SA Init confirmed working via Wireshark.

---

## Problem 2 — Error 13816 AUTH_FAILED

**Symptom:** `Get-VpnS2SInterface` showed `LastError: 13816` on every connection attempt.

**Wireshark analysis:**
- IKEv2 SA Init — **PASSED** — both sides agreed on AES256/SHA384/DH Group 19
- IKEv2 Auth — **FAILED** — remote gateway returned AUTH_FAILED notification
- Confirmed remote gateway is Cisco ASA via Vendor ID payloads in packets

**Initial assumption:** PSK mismatch. PSK verified character by character:
```powershell
$psk = $env:VPN_PSK
for ($i = 0; $i -lt $psk.Length; $i++) {
    Write-Host "[$i] '$($psk[$i])' = ASCII $([int][char]$psk[$i])"
}
```
PSK confirmed correct on our side. Remote side also confirmed correct.

**Discovery:** During a live call with the remote network team they shared Cisco console output:
```
IKEv2 Tunnel rejected: Crypto Map Policy not found
for remote traffic selector 0.0.0.0/255.255.255.255/0/65535/0
local traffic selector  0.0.0.0/255.255.255.255/0/65535/0
```

**Root cause:** RRAS sends wildcard traffic selectors `0.0.0.0/0` by default. The Cisco ASA had a crypto map configured for specific IP ranges. Wildcard selectors did not match the crypto map so the tunnel was rejected.

**Error 13816 in this context:** The AUTH_FAILED was a secondary error caused by the traffic selector rejection — not a PSK problem.

---

## Problem 3 — New-VpnTrafficSelector Syntax

**Finding the correct syntax:**

```powershell
# Wrong — parameter does not exist
New-VpnTrafficSelector -StartAddress "10.0.0.1" ...
# Error: Parameter 'StartAddress' not found

# Wrong — string format rejected
New-VpnTrafficSelector -IPAddressRange "10.0.0.1-10.0.0.1" -PortRange "0-65535" ...
# Error: Cannot convert "0-65535" to UInt32[]

# Wrong — array format rejected
New-VpnTrafficSelector -IPAddressRange "10.0.0.1","10.0.0.1" -PortRange @(0,65535) ...
# Error: Invalid IPAddressRange value

# CORRECT
$ts = New-VpnTrafficSelector -TSPayloadId 0 -Type IPv4 `
    -IPAddressRange "10.0.0.1","10.0.0.1" `
    -PortRange 0,65535 `
    -ProtocolId 0
```

Key: `IPAddressRange` takes two separate string values (start, end) as positional array. `PortRange` takes two separate integers (not a string, not an array object).

---

## Resolution — Traffic Selectors Fixed

```powershell
$ts_local  = New-VpnTrafficSelector -TSPayloadId 0 -Type IPv4 -IPAddressRange "LOCAL_IP","LOCAL_IP" -PortRange 0,65535 -ProtocolId 0
$ts_remote = New-VpnTrafficSelector -TSPayloadId 0 -Type IPv4 -IPAddressRange "REMOTE_START","REMOTE_END" -PortRange 0,65535 -ProtocolId 0
Set-VpnS2SInterface -Name "VPN-Primary" -LocalVpnTrafficSelector $ts_local -RemoteVpnTrafficSelector $ts_remote

Restart-Service RemoteAccess -Force
Start-Sleep -Seconds 10
Connect-VpnS2SInterface -Name "VPN-Primary"
```

**Result:** Both tunnels connected immediately. `ConnectionState: Connected`, `LastError: 0`. Application ports verified working end to end.

---

## Summary of Root Causes

| # | Problem | Root Cause | Fix |
|---|---|---|---|
| 1 | Phase 1 crypto wrong | Windows native IPsec ignores custom Phase 1 crypto in tunnel mode | Use RRAS instead |
| 2 | IKEv1 traffic on wire | Old native IPsec rules still active after switching to RRAS | Remove all native IPsec rules |
| 3 | Tunnel rejected by Cisco | RRAS wildcard traffic selectors 0.0.0.0/0 did not match Cisco crypto map | Set explicit traffic selectors using New-VpnTrafficSelector |
