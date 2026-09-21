# IPsec IKEv2 Site-to-Site VPN — Corporate Guide

## Table of Contents

1. [What Is IPsec and Why It Exists](#1-what-is-ipsec-and-why-it-exists)
2. [How the Tunnel Works](#2-how-the-tunnel-works)
3. [What Information Travels Inside the Tunnel](#3-what-information-travels-inside-the-tunnel)
4. [One Endpoint to One Endpoint](#4-one-endpoint-to-one-endpoint)
5. [One Endpoint to Multiple Endpoints](#5-one-endpoint-to-multiple-endpoints)
6. [How the Tunnel Protects Against Cyber Threats](#6-how-the-tunnel-protects-against-cyber-threats)
7. [Business Benefits and Risks](#7-business-benefits-and-risks)
8. [Firewall Configuration](#8-firewall-configuration)
9. [How Traffic Is Received on the Client Side](#9-how-traffic-is-received-on-the-client-side)
10. [Security Best Practices](#10-security-best-practices)

---

## 1. What Is IPsec and Why It Exists

IPsec stands for Internet Protocol Security. It is a framework of protocols that encrypts and authenticates network traffic between two endpoints over any network — including the public internet.

Without IPsec, data sent between two servers over the internet travels through dozens of intermediate networks in clear text. Anyone on any of those networks can read, copy or modify it. IPsec wraps each packet in an encrypted, authenticated envelope so that only the two legitimate endpoints can read the contents.

Companies use IPsec to:
- Connect offices across the internet as if they were on the same internal network
- Connect trading servers to financial exchange gateways securely
- Connect data centres to cloud environments without exposing services publicly
- Fulfil regulatory requirements that mandate encryption of data in transit

---

## 2. How the Tunnel Works

An IPsec tunnel is built in two phases.

### Phase 1 — IKE Negotiation

Phase 1 is where the two endpoints meet, agree on how they will communicate, and verify each other's identity. The IKE protocol (Internet Key Exchange) manages this handshake.

What happens in Phase 1:
1. The initiator sends a list of proposed crypto algorithms to the responder
2. The responder picks one it supports and sends it back
3. Both sides perform a Diffie-Hellman key exchange to generate a shared secret — the key material never travels over the network
4. Both sides authenticate using a pre-shared key or certificate
5. The Phase 1 SA (Security Association) is established — a secure channel for all further negotiation

Parameters that must match on both sides:
- IKE version (IKEv1 or IKEv2 — always use IKEv2)
- Encryption algorithm (AES-256 recommended)
- Integrity/hash algorithm (SHA-384 recommended)
- DH group (Group 19 / ECP256 recommended)
- Authentication method (PSK or certificate)
- SA lifetime in seconds

### Phase 2 — Data Encryption

Phase 2 happens inside the secure channel from Phase 1. This is where the encryption for the actual data traffic is negotiated.

Phase 2 uses ESP (Encapsulating Security Payload) which wraps each data packet in an encrypted envelope. The original packet headers and payload are hidden inside ESP. A new outer IP header is added with the tunnel endpoint addresses so the packet can route across the internet.

Parameters that must match on both sides:
- Protocol (ESP)
- Encryption algorithm
- Integrity algorithm
- Perfect Forward Secrecy group
- Traffic selectors (which source and destination IPs go through this tunnel)
- SA lifetime in seconds

---

## 3. What Information Travels Inside the Tunnel

### Hidden inside encryption — invisible to observers

- Original source IP of the application traffic
- Original destination IP of the application traffic
- TCP or UDP port numbers
- All application data — API calls, database queries, file transfers, trading messages, anything

### Visible to network observers

- The two tunnel endpoint IP addresses
- That IPsec/ESP traffic is flowing between those IPs
- Packet sizes and rough traffic volumes (not content)
- UDP port 500 or 4500 during the initial IKE handshake

### What observers cannot determine

- The actual application communicating
- The content of any message
- How many individual connections are inside the tunnel
- What ports the applications are using

---

## 4. One Endpoint to One Endpoint

The simplest configuration. One server talks to one remote server through an encrypted tunnel.

```
Server A ──────── IPsec Tunnel ──────── Server B
10.0.1.100                              10.0.2.100
```

Traffic selectors for point to point:
```
Local:  10.0.1.100 to 10.0.1.100
Remote: 10.0.2.100 to 10.0.2.100
```

Only traffic between those two specific IPs is tunnelled. Everything else goes normally.

---

## 5. One Endpoint to Multiple Endpoints

One central server (hub) maintains separate tunnels to multiple remote servers (spokes). This is called hub and spoke topology.

```
                    ── Tunnel 1 ──→ Remote A
Hub (10.0.0.1) ────── Tunnel 2 ──→ Remote B
                    ── Tunnel 3 ──→ Remote C
```

Each tunnel is a separate RRAS VPN S2S interface with its own traffic selectors, PSK, and crypto parameters. Different remotes can use different crypto settings if needed.

```powershell
Add-VpnS2SInterface -Name "VPN-RemoteA" -Destination "GATEWAY_A" -Protocol Ikev2 ...
Add-VpnS2SInterface -Name "VPN-RemoteB" -Destination "GATEWAY_B" -Protocol Ikev2 ...
Add-VpnS2SInterface -Name "VPN-RemoteC" -Destination "GATEWAY_C" -Protocol Ikev2 ...
```

Add a static route per tunnel so the OS knows which interface to use:
```powershell
route add 10.0.1.0 mask 255.255.255.0 0.0.0.0 if <InterfaceIndex>
```

**Limitation:** Traffic between two spokes must pass through the hub. Spoke-to-spoke direct communication requires additional tunnels.

---

## 6. How the Tunnel Protects Against Cyber Threats

| Threat | How IPsec Prevents It |
|---|---|
| Man in the Middle | Traffic is encrypted with keys only the two endpoints hold. Intercepted packets are unreadable. |
| Packet Sniffing | ESP encrypts the payload. Wireshark shows only encrypted bytes. |
| Replay Attack | Every packet has a unique sequence number. Previously seen packets are dropped. |
| IP Spoofing | Authentication verifies the identity of both peers. A spoofed IP cannot complete the IKE handshake. |
| Session Hijacking | Every packet is encrypted and integrity-checked. Injecting or modifying packets mid-session is not possible. |
| Data Tampering | Integrity checking detects any modification. Tampered packets are silently dropped. |

---

## 7. Business Benefits and Risks

### Benefits

- Secure connectivity over public internet — no need for expensive dedicated lines
- Meets PCI DSS, HIPAA, SOC 2 and other regulatory encryption requirements
- Always-on tunnels with no user intervention required
- Application traffic is completely transparent — no changes needed to the application itself
- Multiple tunnels support redundancy — if the primary fails, the backup takes over

### Risks of Not Having a Tunnel

- All traffic between sites travels unencrypted and readable by any ISP or attacker on the path
- Regulatory penalties for transmitting sensitive data without encryption
- Trading algorithms and order flow visible to anyone monitoring the network path
- No way to verify the remote server's identity — connections can be intercepted and redirected

### Risks of a Misconfigured Tunnel

- Weak crypto (DES, 3DES, SHA-1, DH Group 2) provides little real protection — use AES-256, SHA-384, Group 19
- Short SA lifetimes cause frequent renegotiation and potential connectivity gaps
- Wildcard traffic selectors (0.0.0.0/0) may be rejected by some gateways or may route more traffic than intended
- PSK stored in scripts or config files is a security risk — use environment variables or a secrets manager

---

## 8. Firewall Configuration

### Required Ports

| Port / Protocol | Direction | Purpose |
|---|---|---|
| UDP 500 | Inbound + Outbound | IKE negotiation |
| UDP 4500 | Inbound + Outbound | IKE NAT traversal (required even without NAT) |
| IP Protocol 50 | Inbound + Outbound | ESP — the encrypted data packets |

> **Important:** IP Protocol 50 is not TCP or UDP. Many corporate firewalls block it by default. This causes tunnels that establish Phase 1 successfully but never pass data. Explicitly allow Protocol 50 between the two gateway IPs on your perimeter firewall.

### Windows Host Firewall Rules

```powershell
New-NetFirewallRule -DisplayName "IKEv2-In"  -Direction Inbound  -Protocol UDP -LocalPort 500,4500  -RemoteAddress "REMOTE_GATEWAY_IP" -Action Allow
New-NetFirewallRule -DisplayName "IKEv2-Out" -Direction Outbound -Protocol UDP -RemotePort 500,4500 -RemoteAddress "REMOTE_GATEWAY_IP" -Action Allow
```

### Application Port Rules

Application traffic flows inside the encrypted tunnel but you still need host firewall rules for the application ports:

```powershell
New-NetFirewallRule -DisplayName "App-Out" -Direction Outbound -Protocol TCP -RemotePort YOUR_PORT -Action Allow
New-NetFirewallRule -DisplayName "App-In"  -Direction Inbound  -Protocol TCP -LocalPort  YOUR_PORT -Action Allow
```

---

## 9. How Traffic Is Received on the Client Side

When a remote server sends data through the tunnel to your Windows server:

1. Remote server encrypts the packet using the agreed ESP parameters
2. Sends it to your server IP on UDP 4500 (NAT-T is active by default in modern IKEv2)
3. Your perimeter firewall allows it (UDP 4500 rule)
4. Your Windows host firewall allows it (inbound UDP 4500 rule)
5. RRAS receives the packet and looks up the SA using the SPI value in the ESP header
6. Decrypts the packet using the session keys negotiated in Phase 2
7. Strips the outer ESP header and delivers the original application packet to the local network stack
8. The application receives the packet as if it came directly from the remote host

The IPsec layer is completely transparent to the application. No changes are needed on the application side.

---

## 10. Security Best Practices

**Algorithm selection**
- Always use IKEv2 — IKEv1 has known vulnerabilities and is being deprecated
- AES-256 for encryption — AES-128 is acceptable, never use DES or 3DES
- SHA-384 or SHA-512 for integrity — SHA-1 is deprecated, SHA-256 is the minimum
- DH Group 19 (ECP256) or higher for key exchange — Groups 1, 2, and 5 are weak

**PSK management**
- Never hardcode PSK values in scripts or config files
- Use environment variables: `$env:VPN_PSK = "your-psk"`
- For production use a secrets manager — HashiCorp Vault, Azure Key Vault, AWS Secrets Manager
- Minimum PSK complexity: 20+ characters, mixed case, numbers, special characters
- Rotate PSKs on a schedule — coordinate with the remote side

**Perfect Forward Secrecy**
- Always enable PFS on Phase 2
- PFS ensures that even if the Phase 1 long-term key is compromised, past Phase 2 sessions cannot be decrypted

**Firewall hardening**
- Restrict UDP 500 and 4500 rules to specific remote gateway IPs only
- Do not allow IKE from any source

**Monitoring**
- Monitor IKE operational logs for unexpected SA termination events
- Alert on repeated 13816 AUTH_FAILED events — could indicate probe attempts
- Monitor tunnel state and alert if either tunnel drops

```powershell
# Check tunnel status
Get-VpnS2SInterface | Select-Object Name, ConnectionState, LastError | Format-Table -AutoSize

# Check IKE events
Get-WinEvent -LogName "Microsoft-Windows-IKE/Operational" -MaxEvents 20 |
    Where-Object { $_.Properties[4].Value -ne 0 } |
    ForEach-Object { Write-Host "Time: $($_.TimeCreated)  Error: $($_.Properties[4].Value)" }
```
