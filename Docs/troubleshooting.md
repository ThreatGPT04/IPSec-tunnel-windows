# Troubleshooting Guide

All errors encountered during real-world deployment and how each was resolved.

---

## Error 13816 — IKE Authentication Failed

`LastError: 13816` means `ERROR_IPSEC_IKE_AUTH_FAIL`.

This error appears after Phase 1 SA Init completes successfully. The crypto negotiation worked but authentication failed.

**Common causes:**

**1. Traffic selector mismatch (most common in production)**

Check what your traffic selectors actually are:
```powershell
$t = Get-VpnS2SInterface -Name "YOUR-TUNNEL"
$t.LocalVpnTrafficSelector  | ForEach-Object { Write-Host "Local: " $_.IPAddressRange }
$t.RemoteVpnTrafficSelector | ForEach-Object { Write-Host "Remote:" $_.IPAddressRange }
```

If you see `0.0.0.0 255.255.255.255` — wildcard selectors. Run script 03 to fix.

The Cisco ASA error for this is:
```
IKEv2 Tunnel rejected: Crypto Map Policy not found
for remote traffic selector 0.0.0.0/255.255.255.255/0/65535/0
```

**2. PSK mismatch**

Verify PSK character by character:
```powershell
$psk = $env:VPN_PSK
Write-Host "Length: $($psk.Length)"
for ($i = 0; $i -lt $psk.Length; $i++) {
    Write-Host "[$i] '$($psk[$i])' = ASCII $([int][char]$psk[$i])"
}
```
Pay attention to special characters — `@`, `!`, `#` can be encoded differently in some contexts. Always use single quotes when assigning PSK in PowerShell.

---

## Error 633 — Port Already in Use

RRAS is not configured as a LAN router. Open `rrasmgmt.msc`, right click the server name, select Configure and Enable Routing and Remote Access, choose Custom Configuration, check LAN Routing, click Finish, then Start Service.

---

## Remote Side Shows IKE MM Errors (Cisco)

`IKE MM` in Cisco logs means IKE Main Mode which is IKEv1. If your RRAS is configured for IKEv2 but the remote side sees IKEv1, you have leftover native Windows IPsec rules still sending IKEv1 traffic.

Remove them:
```powershell
Get-NetIPsecRule          | Remove-NetIPsecRule          -ErrorAction SilentlyContinue
Get-NetIPsecMainModeCryptoSet  | Remove-NetIPsecMainModeCryptoSet  -ErrorAction SilentlyContinue
Get-NetIPsecQuickModeCryptoSet | Remove-NetIPsecQuickModeCryptoSet -ErrorAction SilentlyContinue
Get-NetIPsecPhase1AuthSet | Remove-NetIPsecPhase1AuthSet -ErrorAction SilentlyContinue
Get-NetIPsecMainModeRule  | Remove-NetIPsecMainModeRule  -ErrorAction SilentlyContinue
```

Then restart RRAS and reconnect.

---

## No Proposal Chosen

Phase 1 SA Init failed — the crypto proposals did not match.

Use Wireshark to see exactly what you are proposing:
1. Install Wireshark on the server
2. Start capture with filter: `udp.port == 500 or udp.port == 4500`
3. Trigger: `Connect-VpnS2SInterface -Name "YOUR-TUNNEL"`
4. Expand the IKE_SA_INIT packet → Security Association → Proposal 1
5. Compare the Transform IDs against what the remote side requires

Common mismatch: ECP256 (DH Group 19) vs DH14 (Group 14). Check the DH group carefully.

---

## Phase 1 Succeeds But No Traffic Flows

Check your perimeter firewall. IP Protocol 50 (ESP) carries the actual encrypted data and many firewalls block it by default because it is not TCP or UDP.

You need to allow:
- UDP 500 both directions between the two gateway IPs
- UDP 4500 both directions between the two gateway IPs
- IP Protocol 50 both directions between the two gateway IPs

---

## IKE Logs

```powershell
# Enable debug logging
wevtutil sl "Microsoft-Windows-IKEDBG/Debug" /e:true

# View operational log
Get-WinEvent -LogName "Microsoft-Windows-IKE/Operational" -MaxEvents 10 |
    ForEach-Object {
        Write-Host "Time: $($_.TimeCreated)  ID: $($_.Id)  Error: $($_.Properties[4].Value)  SA: $($_.Properties[5].Value)"
    }

# View debug log (shows actual packet exchange)
Get-WinEvent -LogName "Microsoft-Windows-IKEDBG/Debug" -MaxEvents 50 -Oldest |
    Where-Object {$_.Id -in (1024,1025,1026)} |
    ForEach-Object {
        Write-Host "ID:$($_.Id)  $($_.Properties[2].Value)  $($_.Properties[3].Value)bytes"
    }
```

**Event IDs:**
- 1013 = Main Mode SA Terminated
- 1024 = IKE packet sent
- 1025 = IKE packet received
- 1026 = WFP error

**Decode event 1026 error values:**
- 13816 = AUTH_FAILED
- 13868 = PEER_AUTH_FAILED
- 1168  = Optional construct (minor, not a real error)

---

## Quick Status Check

```powershell
Get-VpnS2SInterface | Select-Object Name, ConnectionState, LastError | Format-Table -AutoSize
```
