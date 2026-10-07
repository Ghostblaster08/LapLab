# 🧠 Homelab Networking & Systems Theory — Complete Deep Dive

> *Written specifically for your Omarchy Linux (Arch) setup running on an Intel Core i5-1035G1, 16 GB RAM, with Docker Compose services on 192.168.1.96. Every concept here is grounded in your actual stack.*

---

## Table of Contents

1. [The OSI Model & TCP/IP Stack](#section-1)
2. [Local Network Architecture](#section-2)
3. [DNS — From Stub Resolver to Root Server](#section-3)
4. [HTTP, HTTPS, Reverse Proxies & TLS](#section-4)
5. [Docker Networking Deep Dive](#section-5)
6. [VPNs & Zero-Trust Networking](#section-6)
7. [Video Streaming & Low-Latency Protocols](#section-7)
8. [Linux Kernel Internals Relevant to Homelab](#section-8)
9. [Security Model & Attack Surface](#section-9)
10. [Brief Primer on Distributed Computing](#section-10)

---

<a name="section-1"></a>
# Section 1: The OSI Model & TCP/IP Stack

## Why the OSI Model Exists

The OSI (Open Systems Interconnection) model is a conceptual framework created by ISO in 1984 to describe how computers communicate. It doesn't correspond exactly to how real protocols are implemented—the Internet runs on TCP/IP, which collapses some layers—but OSI gives you a *vocabulary* for reasoning about where problems occur and how to isolate them. When your Jellyfin client fails to connect, you need to know whether the problem is at Layer 2 (ARP failure, wrong switch port), Layer 3 (routing issue, wrong subnet), Layer 4 (firewall blocking TCP port 8096), or Layer 7 (the application rejecting the HTTP request). The OSI model lets you diagnose in a structured way.

## The 7 Layers — With Real Homelab Examples

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Layer 7 — Application      │ HTTP, DNS, SSH, WebSocket                     │
│  Layer 6 — Presentation     │ TLS/SSL encryption, data serialization        │
│  Layer 5 — Session          │ TLS session management, TCP connection state  │
│  Layer 4 — Transport        │ TCP (reliable), UDP (fast/unreliable)         │
│  Layer 3 — Network          │ IP (addressing + routing)                     │
│  Layer 2 — Data Link        │ Ethernet frames, MAC addresses, ARP           │
│  Layer 1 — Physical         │ Wi-Fi radio signals, Ethernet cable signals   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Layer 1 — Physical

This is the literal signal: photons in fiber, electrons in copper, radio waves in Wi-Fi. Your laptop uses `wlp3s0` (the wireless interface, MAC `1c:bf:c0:bc:70:81`) and connects over Wi-Fi 802.11 (likely 802.11ac/Wi-Fi 5 or 802.11ax/Wi-Fi 6). The physical layer deals with signal encoding, frequency, amplitude, and timing. It knows nothing about who is talking or what is being said—it just moves bits.

Your `enp2s0` (Ethernet port, `c0:3e:ba:1e:15:c4`) is currently `DOWN`—no carrier—meaning no physical cable is attached.

### Layer 2 — Data Link

Layer 2 adds structure to the raw bits by grouping them into **frames**. On Ethernet/Wi-Fi, the frame structure is:

```
┌────────────┬────────────┬──────┬──────────────────────┬─────────────┐
│ Dest MAC   │ Src MAC    │ EType│ Payload (IP packet)  │ FCS/CRC     │
│ 6 bytes    │ 6 bytes    │ 2 B  │ up to 1500 bytes     │ 4 bytes     │
└────────────┬────────────┴──────┴──────────────────────┴─────────────┘
              e.g.: ff:ff:ff:ff:ff:ff (broadcast)
              or:   1c:bf:c0:bc:70:81 (your laptop's Wi-Fi MAC)
```

- **MAC addresses** are Layer 2 identifiers. They're 48-bit hardware addresses burned into the NIC (though they can be spoofed). The first 24 bits (OUI) identify the manufacturer; Intel's OUI for your Wi-Fi card starts with `1c:bf:c0`.
- **EtherType** tells the receiver what Layer 3 protocol is inside: `0x0800` = IPv4, `0x0806` = ARP, `0x86DD` = IPv6.
- **FCS** (Frame Check Sequence) is a CRC-32 checksum. If the frame is corrupted in transit, the receiver discards it silently. This is why UDP applications build their own reliability (or don't care about occasional loss).
- The **802.11 Wi-Fi frame** adds more fields (frame control, duration, BSSID, sequence number) but conceptually is still a Layer 2 frame.

**In your homelab:** ARP uses Layer 2 directly. When your phone tries to reach Jellyfin at `192.168.1.96`, it first needs to find the MAC address of that IP. It broadcasts an ARP request on Layer 2 (destination `ff:ff:ff:ff:ff:ff`), and your laptop responds with its MAC `1c:bf:c0:bc:70:81`.

### Layer 3 — Network

Layer 3 is about **addressing across networks**. IP (Internet Protocol) assigns logical addresses (`192.168.1.96`, `8.8.8.8`) that are independent of hardware. Routers operate at Layer 3—they look at the destination IP, consult their routing table, and forward the packet toward the destination.

**IPv4 Packet Header (simplified):**
```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
├─────────────────────────────────────────────────────────────────┤
│ Version │ IHL  │  DSCP/ECN   │            Total Length         │
├─────────────────────────────────────────────────────────────────┤
│         Identification        │ Flags │    Fragment Offset      │
├─────────────────────────────────────────────────────────────────┤
│    TTL   │    Protocol  │         Header Checksum               │
├─────────────────────────────────────────────────────────────────┤
│                       Source IP Address                         │
├─────────────────────────────────────────────────────────────────┤
│                    Destination IP Address                       │
└─────────────────────────────────────────────────────────────────┘
```

Key fields:
- **TTL (Time To Live)**: Decremented by 1 at each router hop. When it hits 0, the packet is dropped and an ICMP "Time Exceeded" is sent back. This prevents routing loops from living forever. `traceroute` exploits this by intentionally sending packets with TTL=1, 2, 3... to map the path.
- **Protocol**: `6` = TCP, `17` = UDP, `1` = ICMP, `41` = IPv6-in-IPv4 (used by some tunnels).
- **Flags + Fragment Offset**: Used for IP fragmentation (see MTU section below).

**In your homelab:** Your laptop's IP `192.168.1.96/24` and gateway `192.168.1.1`. The kernel's routing table:
```
default via 192.168.1.1 dev wlp3s0   ← All non-local traffic → router
172.17.0.0/16 dev docker0            ← Docker default bridge subnet
192.168.1.0/24 dev wlp3s0            ← Local LAN, direct delivery
```

### Layer 4 — Transport

Layer 4 adds **port numbers** (identifying which application gets the packet) and either **reliability** (TCP) or just raw **speed** (UDP).

**TCP (Transmission Control Protocol)** provides:
- **Reliable delivery**: Lost packets are retransmitted.
- **Ordering**: Packets are reassembled in sequence order.
- **Flow control**: The receiver tells the sender how much buffer space it has (window size).
- **Congestion control**: TCP backs off when the network is congested.

**TCP Segment header:**
```
┌───────────────────┬───────────────────┐
│ Source Port       │ Destination Port  │  e.g., 54231 → 8096 (Jellyfin)
├───────────────────┴───────────────────┤
│         Sequence Number               │  Which byte in the stream this starts at
├───────────────────────────────────────┤
│       Acknowledgment Number           │  Next byte expected from peer
├───────┬───────────┬───────────────────┤
│ Offs. │  Flags    │   Window Size     │  SYN,ACK,FIN,RST,PSH,URG
├───────────────────┬───────────────────┤
│    Checksum       │  Urgent Pointer   │
└───────────────────┴───────────────────┘
```

**The TCP 3-Way Handshake** (this happens every time your browser opens Jellyfin):
```
Client (Phone)           Server (Laptop :8096)
    │                           │
    │─────── SYN ──────────────►│   "I want to connect, my seq=1000"
    │                           │
    │◄────── SYN+ACK ───────────│   "OK, my seq=5000, I got your 1000, next send 1001"
    │                           │
    │─────── ACK ──────────────►│   "Got it, I'll start sending from 1001"
    │                           │
    │◄══════ DATA ══════════════│   HTTP response flows
```

**UDP (User Datagram Protocol)** is just an IP packet with two extra fields (source/destination ports and a checksum). That's it. No handshake, no retransmit, no ordering. Why use it?

**Why UDP is used for DNS, streaming, and VPNs:**

1. **DNS**: A DNS query is tiny (usually < 512 bytes, fits in one UDP datagram). The overhead of a TCP handshake for a round-trip query/response would be wasteful. If the UDP packet is lost, the DNS resolver just retries after a timeout. DNS *can* use TCP (for responses > 512 bytes, zone transfers), but the default is UDP/53.

2. **Streaming (Jellyfin, Sunshine/Moonlight)**: Video streaming sends a *torrent* of data. TCP's retransmit mechanism causes problems: if a packet is lost, TCP blocks the entire stream waiting for the retransmit, causing a stuttering freeze (head-of-line blocking). Video codecs are designed to handle occasional lost frames gracefully—a slightly corrupted frame is far better than a frozen stream. UDP lets the application implement its own loss handling (like Forward Error Correction in Moonlight).

3. **VPNs (WireGuard/Tailscale)**: WireGuard uses UDP for its tunnel. Because WireGuard often encapsulates TCP connections (your Jellyfin TCP stream is wrapped inside WireGuard UDP packets), running WireGuard over TCP would cause "TCP-over-TCP" problems where both inner and outer TCP stacks compete for congestion control, causing catastrophic performance degradation.

### Layers 5, 6, 7 — Session, Presentation, Application

In practice, the TCP/IP stack collapses these into the "Application Layer." But the concepts remain useful:

- **Session (L5)**: TLS manages sessions (session IDs, session tickets for resumption). HTTP/2 multiplexes multiple streams over a single TCP connection (session management).
- **Presentation (L6)**: TLS *encryption/decryption* technically lives here—converting application plaintext into ciphertext before it goes to TCP. JSON, XML, gzip compression also live here conceptually.
- **Application (L7)**: The actual protocol—HTTP requests, DNS queries, SSH commands. Your Nginx Proxy Manager, AdGuard Home, and all services live here.

**In your homelab:** Nginx Proxy Manager operates as a **Layer 7 reverse proxy**. It terminates TLS (decrypts), reads the HTTP Host header, and decides where to route the request. A simple Layer 4 load balancer, by contrast, just looks at IP/port and forwards TCP streams without reading the content.

---

## Tracing a DNS Query Through All Layers: Phone → `jellyfin.home.lab`

Let's trace every hop as your phone asks "what's the IP of jellyfin.home.lab?" and gets back the Jellyfin stream.

```
Phone
  [L7] Application: DNS query for jellyfin.home.lab, type A
  [L6] Presentation: (no encryption for plain DNS)
  [L5] Session: none (UDP)
  [L4] Transport: UDP, Src Port=54321, Dst Port=53
  [L3] Network: IP, Src=192.168.1.55, Dst=192.168.1.96 (AdGuard Home)
  [L2] Data Link: Ethernet frame, Src MAC=phone_mac, Dst MAC=??
                  → ARP: "Who has 192.168.1.1?" (gateway) if needed
                    OR direct to laptop MAC if same subnet
  [L1] Physical: Wi-Fi radio transmission to access point

  ──── Through Wi-Fi AP (Layer 1/2 only, AP doesn't inspect IP) ────

Laptop (192.168.1.96)
  [L1] Physical: Wi-Fi NIC receives frame
  [L2] Data Link: wlp3s0 confirms destination MAC is ours, strips Ethernet header
  [L3] Network: IP stack receives packet, destination 192.168.1.96 = us ✓
  [L4] Transport: UDP port 53, delivered to AdGuard Home process
  [L7] Application: AdGuard checks blocklist → "jellyfin.home.lab" is not an ad domain
                    → Check custom DNS rewrite: jellyfin.home.lab → 192.168.1.96
                    → Return A record: 192.168.1.96
  [L4 down to L1]: Response UDP packet flows back to phone

Phone receives response: jellyfin.home.lab = 192.168.1.96
  → Phone now opens TCP connection to 192.168.1.96:8096
  → 3-way handshake
  → HTTP request: GET / HTTP/1.1 Host: jellyfin.home.lab
  → Jellyfin responds with its web UI
```

---

## MTU, Fragmentation, and Jumbo Frames

**MTU (Maximum Transmission Unit)** is the largest payload a Layer 2 frame can carry. For standard Ethernet, the MTU is **1500 bytes**. This means the maximum IP packet size is 1500 bytes—if you have more data, it must be split into multiple packets.

```
Ethernet frame (max 1518 bytes):
├── Ethernet header: 14 bytes (dest MAC + src MAC + EtherType)
├── IP packet: up to 1500 bytes ← This is the MTU
│   ├── IP header: 20 bytes
│   └── TCP/UDP payload: up to 1480 bytes
└── FCS: 4 bytes
```

**IP Fragmentation**: If a router receives a packet larger than the next link's MTU, it fragments the packet. Each fragment gets the original packet's ID and a Fragment Offset field. The *destination* host reassembles them. Fragmentation is bad for performance because:
- Dropping any single fragment requires retransmitting the entire original packet (TCP) or dropping the entire application message (UDP).
- It adds processing overhead.

**Path MTU Discovery (PMTUD)**: The modern solution. Hosts send packets with the **Don't Fragment (DF)** bit set. If a router can't forward the packet without fragmenting, it drops it and sends back an ICMP "Fragmentation Needed" message. The source lowers its MTU. TCP handles this automatically; UDP applications need to be aware.

**VPN Overhead**: WireGuard wraps your packets in UDP datagrams with extra headers (~60 bytes overhead). If your LAN MTU is 1500 bytes and WireGuard adds 60 bytes, the *inner* packet must be at most 1440 bytes. WireGuard sets the MTU of its `tailscale0` interface to 1280 bytes (a conservative value that works over IPv6 and most paths) to avoid fragmentation.

**Jumbo Frames**: Some datacenter Ethernet supports MTU up to 9000 bytes ("jumbo frames"). This reduces per-packet header overhead for large transfers, improving throughput for storage traffic. Irrelevant on Wi-Fi (which caps around 2304 bytes per MPDU) but worth knowing for when you build a wired homelab.

---

<a name="section-2"></a>
# Section 2: Local Network Architecture

## Your Home Router: A Multi-Function Swiss Army Knife

Your home router at `192.168.1.1` is doing *at least* five jobs simultaneously:

1. **Layer 3 Router**: Forwarding packets between your ISP's WAN interface and your LAN.
2. **NAT Gateway**: Translating private RFC-1918 addresses to your public IP.
3. **DHCP Server**: Assigning IP addresses to devices on your LAN.
4. **DNS Forwarder**: Forwarding DNS queries (usually to ISP or 8.8.8.8)—*unless* you've configured your devices to use AdGuard Home instead.
5. **Firewall**: Blocking unsolicited inbound connections from the internet.

---

## NAT & PAT: The Great IP-Address Workaround

The internet was designed for every device to have a globally unique IP. IPv4 only has ~4.3 billion addresses—not enough for 8 billion people with multiple devices each. NAT (Network Address Translation) was the hack that let us get away with this for 30 years.

**How NAT works:**

Your ISP gives your router a single public IP (let's say `203.0.113.45`). Your home has dozens of devices with private addresses (`192.168.1.x`). When your laptop (`192.168.1.96`) makes a request to `8.8.8.8`:

```
BEFORE (on your LAN):
  IP Src: 192.168.1.96  Port Src: 49152
  IP Dst: 8.8.8.8       Port Dst: 443

Router modifies:
  IP Src: 203.0.113.45  Port Src: 61024  ← Public IP + NEW unique port
  IP Dst: 8.8.8.8       Port Dst: 443

NAT Translation Table entry:
  203.0.113.45:61024 → 192.168.1.96:49152

RESPONSE comes back:
  IP Src: 8.8.8.8       Port Src: 443
  IP Dst: 203.0.113.45  Port Dst: 61024

Router looks up 61024 in NAT table → 192.168.1.96:49152
Modifies and forwards to your laptop.
```

This is technically **PAT (Port Address Translation)**—one public IP, many private IPs, distinguished by port number. The port is the "session identifier." The router maintains this state table in RAM. This is why:

- **Inbound connections can't reach your home services by default**: Nothing can initiate a connection to `192.168.1.96:8096` from the internet, because the NAT table has no entry for unsolicited inbound traffic. That's actually a security feature.
- **Port forwarding** adds a static NAT rule: "inbound traffic on port 8096 → always forward to 192.168.1.96:8096." This is how traditional VPNs and remote services work—and why Tailscale's approach (no port forwarding needed) is such an improvement.
- **Tailscale can punch through NAT**: More on this in Section 6.

---

## DHCP: How Your Devices Get Their IP Addresses

When your phone connects to Wi-Fi, it doesn't know its IP address yet. DHCP (Dynamic Host Configuration Protocol) is how it finds out.

**The DORA Process:**

```
Device                    DHCP Server (Router at 192.168.1.1)
  │                                 │
  │──── DISCOVER (broadcast) ──────►│  "I need an IP! (from 0.0.0.0 → 255.255.255.255)"
  │                                 │
  │◄─── OFFER ──────────────────────│  "How about 192.168.1.55? Here are the terms:"
  │                                 │     - Subnet mask: 255.255.255.0
  │                                 │     - Gateway: 192.168.1.1
  │                                 │     - DNS: 192.168.1.96 (if you configure AdGuard)
  │                                 │     - Lease time: 24 hours
  │                                 │
  │──── REQUEST (broadcast) ────────►│  "I'll take 192.168.1.55!"
  │                                 │
  │◄─── ACK ────────────────────────│  "Confirmed! It's yours for 24 hours."
```

**DHCP Leases**: The IP is "leased" for a fixed time. Before the lease expires, the device sends a RENEW request (unicast this time, since it knows its IP). If the lease expires without renewal (device powered off), the IP goes back into the pool.

**DHCP Reservations**: You can tell your router "whenever you see MAC address `1c:bf:c0:bc:70:81`, always give it `192.168.1.96`." This makes your laptop's IP *effectively static* without actually configuring a static IP on the laptop. This is **critical** for your homelab—services like AdGuard Home need to be reachable at a predictable address. Ditto for your TV at presumably `192.168.1.50` (as hardcoded in `tv-tools.sh`).

**DHCP options you can push to clients:**
- `option 6` (Domain Name Server): Tell all clients to use `192.168.1.96:53` (AdGuard Home). This is how you make AdGuard apply to every device on your network without configuring each individually.
- `option 3` (Gateway): `192.168.1.1`
- `option 15` (Domain name): `home.lab` — so you can refer to devices by short hostname

---

## ARP: Connecting IP Addresses to MAC Addresses

IP addresses are Layer 3 (logical). To actually send a packet on Ethernet/Wi-Fi, you need the destination's **Layer 2 MAC address**. ARP (Address Resolution Protocol) bridges this gap.

**ARP Request/Reply:**

```
Your Phone (192.168.1.55) wants to send a packet to 192.168.1.96 (your laptop).

ARP Request (Ethernet broadcast to ff:ff:ff:ff:ff:ff):
  "Who has 192.168.1.96? Tell 192.168.1.55"

ARP Reply (unicast to phone's MAC):
  "192.168.1.96 is at 1c:bf:c0:bc:70:81"

Phone caches this in its ARP table:
  192.168.1.96 → 1c:bf:c0:bc:70:81  (expires in ~20 minutes)
```

**ARP only works on the same subnet.** If your phone (`192.168.1.55`) wants to reach `8.8.8.8`, it cannot ARP for `8.8.8.8` directly—different subnet. Instead, it ARPs for the **gateway's IP** (`192.168.1.1`), then sends the packet to the gateway's MAC. The gateway handles the rest.

**Gratuitous ARP**: A device can send an ARP reply nobody asked for, announcing its own IP-to-MAC mapping. This is used when an IP address changes (e.g., DHCP renewal with different IP) to update caches quickly.

**ARP Poisoning**: A security attack where a malicious device sends fake ARP replies, claiming "192.168.1.1 is at MY_MAC." This poisons other devices' ARP caches, redirecting traffic through the attacker (man-in-the-middle). VLANs and Dynamic ARP Inspection (DAI) on managed switches defend against this.

**Check the ARP table on your laptop:**
```bash
ip neigh show
# Output example:
# 192.168.1.1 dev wlp3s0 lladdr aa:bb:cc:dd:ee:ff REACHABLE
# 192.168.1.50 dev wlp3s0 lladdr 11:22:33:44:55:66 STALE
```

---

## Subnets & CIDR Notation: The Address Math

An IP address is 32 bits. The **subnet mask** tells you which bits identify the network and which identify the host within that network.

**CIDR notation** writes the subnet mask as `/N` where N is the number of network bits.

```
Your laptop's address: 192.168.1.96/24

Binary breakdown:
192     . 168     . 1       . 96
11000000.10101000.00000001.01100000
│─────────────────────────│────────│
      Network (24 bits)      Host (8 bits)

Network address:   192.168.1.0
Broadcast address: 192.168.1.255
Usable hosts:      192.168.1.1 through 192.168.1.254 (254 hosts)
```

**Common subnet sizes:**

| CIDR | Mask            | Hosts  | Use Case                              |
|------|-----------------|--------|---------------------------------------|
| /8   | 255.0.0.0       | 16.7M  | Large ISP blocks, 10.x.x.x private   |
| /16  | 255.255.0.0     | 65,534 | Medium orgs, Docker default bridge    |
| /24  | 255.255.255.0   | 254    | Home networks, typical LAN            |
| /25  | 255.255.255.128 | 126    | Splitting a /24 in two               |
| /30  | 255.255.255.252 | 2      | Point-to-point links                  |
| /32  | 255.255.255.255 | 1      | Single host route                     |

**Why `/16` for Docker networks?** Docker creates its default bridge at `172.17.0.0/16` (65,534 potential container IPs). When you create a custom network like `homelab-net`, Docker picks another `/16` or `/20` from the `172.16.0.0/12` or `192.168.0.0/16` range. You can see it in your routing table:
```
172.17.0.0/16 dev docker0 proto kernel scope link src 172.17.0.1
```
This means "packets destined for any 172.17.x.x go out docker0 (the Docker bridge), not to the internet."

**Checking if two IPs are on the same subnet** (the operation your kernel does for every packet):
```
My IP:        192.168.1.96   = 11000000.10101000.00000001.01100000
Dest IP:      192.168.1.50   = 11000000.10101000.00000001.00110010
Mask (/24):   255.255.255.0  = 11111111.11111111.11111111.00000000

My network:   192.168.1.96 AND mask = 192.168.1.0
Dest network: 192.168.1.50 AND mask = 192.168.1.0

Same network! → Direct delivery (ARP for dest MAC, send directly)
```

---

## VLANs: Network Segmentation Without New Hardware

A **VLAN (Virtual LAN)** uses IEEE 802.1Q tag in the Ethernet frame to logically separate traffic that shares the same physical cables and switch.

```
Ethernet frame WITH VLAN tag (802.1Q):
┌──────────┬──────────┬───────┬────────┬──────────────────────┬─────┐
│ Dest MAC │ Src MAC  │ 0x8100│VLAN ID │ Payload (IP packet)  │ FCS │
│ 6 bytes  │ 6 bytes  │ 2 B   │12-bit  │ up to 1496 bytes     │ 4B  │
└──────────┴──────────┴───────┴────────┴──────────────────────┴─────┘
                        ↑ marks "this frame has a VLAN tag"
                               ↑ 0-4094, identifies which VLAN
```

**Why you'd want VLANs in your homelab:**

Imagine you have smart home / IoT devices (smart bulbs, IP cameras). These often have weak security—known vulnerabilities, default passwords. You don't want a compromised smart bulb being able to ARP-scan and attack your Jellyfin server. VLANs solve this:

```
VLAN 10 (Trusted): 192.168.10.0/24  — laptop, phone, NAS
VLAN 20 (IoT):     192.168.20.0/24  — smart bulbs, cameras
VLAN 30 (Guest):   192.168.30.0/24  — guest Wi-Fi

Firewall rules:
  VLAN 20 → VLAN 10: BLOCK (IoT can't reach your services)
  VLAN 30 → VLAN 10: BLOCK (guests can't reach your services)
  VLAN 10 → VLAN 20: ALLOW (you can manage IoT devices)
  Any VLAN → Internet: ALLOW (everything gets internet access)
```

To use VLANs, you need a **managed switch** (like TP-Link TL-SG108E ~$30) and a router that supports VLAN tagging (most OpenWRT-capable routers do). Each VLAN gets its own DHCP pool, its own subnet, its own firewall rules.

---

## Why Docker Bridge Networks Exist Separately from Your LAN

Your LAN is `192.168.1.0/24`. Docker creates its own private network `172.17.0.0/16` (and `homelab-net` on another range). Why separate?

**1. Isolation by default**: Containers shouldn't be directly reachable from your LAN without explicit port publishing. The Docker bridge (`docker0`) is like a private mini-switch inside your laptop. Containers on this bridge can talk to each other, but LAN devices can't reach containers (except through published ports).

**2. Name collision avoidance**: If Docker used `192.168.1.0/24`, container IPs would collide with your LAN IPs, breaking routing.

**3. Namespace isolation**: Each Docker network is a separate **network namespace** at the kernel level. Containers in different Docker networks can't reach each other even if both are running on the same host—the Linux kernel enforces this at the network namespace boundary.

**The architecture looks like this:**

```
        Internet
            │
     [192.168.1.1] Router/Gateway
            │
    [Wi-Fi: wlp3s0]  192.168.1.96  ← Your Laptop
            │
     ┌──────┴──────────────────────────────────────────┐
     │                   Linux Kernel                   │
     │                                                  │
     │  ┌──────────────┐   ┌──────────────────────────┐│
     │  │  docker0     │   │   homelab-net bridge     ││
     │  │ 172.17.0.1   │   │   172.18.0.1 (example)  ││
     │  └──────┬───────┘   └───────┬──────────────────┘│
     │         │                   │                   │
     │   [default containers]  [adguardhome]           │
     │                         [npm]                   │
     │                         [jellyfin]              │
     │                         [immich_server]         │
     │                         [filebrowser]           │
     │                         [dockge]                │
     │                         [uptime-kuma]           │
     └─────────────────────────────────────────────────┘

Port publishing = hole in the firewall:
  192.168.1.96:8096 → DNAT → 172.18.x.y:8096 (jellyfin container)
  192.168.1.96:53   → DNAT → 172.18.x.z:53   (adguardhome container)
```

---

<a name="section-3"></a>
# Section 3: DNS — From Stub Resolver to Root Server

## What DNS Actually Is

The Domain Name System is a **globally distributed, hierarchical, delegated database** that maps human-readable names to IP addresses (and much more). It's the phone book of the internet—but a phone book that's replicated across millions of servers worldwide, updated in near-real-time, and handles 3 trillion queries per day.

The hierarchy looks like a tree:

```
                         . (root)
                         │
         ┌───────────────┼───────────────┐
        com             org             io         (TLDs)
         │               │
    ┌────┴────┐      ─────┴─────
  google    netflix    wikipedia
    │
  www  mail  drive                                 (subdomains)
```

---

## Recursive DNS Resolution: The Full Journey

Your laptop has `/etc/resolv.conf` pointing to `127.0.0.53` (systemd-resolved's stub resolver). When you request `jellyfin.home.lab`, here's the full journey for a *public* domain like `netflix.com`:

```
[1] Your app (browser, curl) calls getaddrinfo("netflix.com")
    → glibc makes a DNS query to 127.0.0.53 (systemd-resolved stub)

[2] systemd-resolved checks its cache: miss
    → Forwards to configured upstream resolver
    → You've configured AdGuard Home (192.168.1.96:53) as upstream
    → Or if not, would forward to ISP's resolver or 8.8.8.8

[3] AdGuard Home receives query for netflix.com
    → Checks blocklist: not an ad domain, pass through
    → Checks custom rewrites: not found
    → Forwards to its configured upstream (e.g., 8.8.8.8 or a DoH server)

[4] 8.8.8.8 (Google's recursive resolver) receives the query
    → Checks its cache: miss (or uses cached answer if TTL hasn't expired)
    → Starts RECURSIVE RESOLUTION:

    [4a] Query root nameservers (hardcoded, 13 root server clusters):
         "Who handles .com?"
         Root server responds: "Ask one of these .com TLD servers: 
           a.gtld-servers.net (192.5.6.30), b.gtld-servers.net, ..."

    [4b] Query a.gtld-servers.net:
         "Who handles netflix.com?"
         TLD server responds: "Ask Netflix's authoritative nameservers:
           ns1.p17.dynect.net, ns2.p17.dynect.net, ..."

    [4c] Query ns1.p17.dynect.net:
         "What's the A record for netflix.com?"
         Authoritative server responds: "netflix.com A 54.237.226.164" (TTL=60s)

    [4d] 8.8.8.8 caches this result for 60 seconds
         Returns the answer to AdGuard Home

[5] AdGuard Home caches the answer (respects TTL)
    Returns to systemd-resolved

[6] systemd-resolved caches the answer
    Returns to the application

Total time: ~50-200ms on first query, <1ms on cache hit
```

**Why 13 root servers?** The number 13 comes from the maximum size of a UDP DNS response (512 bytes). Thirteen server *clusters* (A through M root servers) fit within that limit. Each "root server" is actually a massive Anycast cluster—200+ physical servers worldwide. `a.root-servers.net` at `198.41.0.4` is simultaneously served from dozens of locations; your query goes to the nearest one.

---

## DNS Record Types

```bash
# Check these yourself:
dig A google.com          # IPv4 address
dig AAAA google.com       # IPv6 address
dig CNAME www.github.com  # Alias to another name
dig MX gmail.com          # Mail server records
dig TXT github.com        # Arbitrary text (SPF, DKIM, verification)
dig SRV _http._tcp.example.com  # Service location records
dig PTR 96.1.168.192.in-addr.arpa  # Reverse DNS (IP → hostname)
dig NS google.com         # Authoritative nameservers
dig SOA google.com        # Start of Authority (zone metadata)
```

**A (Address)**: `jellyfin.home.lab → 192.168.1.96`
The most common record. Maps a name to an IPv4 address.

**AAAA (Quad-A)**: Maps a name to an IPv6 address. Your laptop has a public IPv6 `2401:4900:8fea:47d7:e779:d8e3:6c17:b697/64`—if you set up an AAAA record pointing to this, devices with IPv6 could reach your services directly (without NAT!). 

**CNAME (Canonical Name)**: An alias. `www.example.com CNAME example.com` means "go look up example.com and use that IP." CNAMEs can chain, but each hop adds latency. You can't CNAME the root of a zone (the "apex"), which is why services use ALIAS/ANAME records or just A records for root domains.

**MX (Mail Exchange)**: `gmail.com MX 10 smtp.google.com` — the `10` is the priority (lower = preferred). Used by mail servers to find where to deliver email.

**TXT**: Arbitrary text records. Used for SPF (`v=spf1 include:_spf.google.com ~all` — tells mail servers which servers are authorized to send mail for this domain), DKIM keys, DMARC policies, and domain ownership verification (Google/Let's Encrypt ask you to add a TXT record to prove you own the domain).

**SRV**: Service discovery. `_minecraft._tcp.example.com SRV 0 5 25565 mc.example.com`. Used by protocols that need to discover service locations dynamically. Kubernetes uses SRV records internally.

**PTR**: Reverse DNS. The IP `192.168.1.96` in reverse is `96.1.168.192`, looked up under the `.in-addr.arpa` zone. Used for spam filtering (mail servers check that the sending IP has a PTR record matching its forward A record).

---

## DNS Caching and TTL

Every DNS record has a **TTL (Time To Live)** in seconds. This tells caches how long to remember the answer before asking again.

```
netflix.com A 54.237.226.164 TTL 60
               ↑ After 60 seconds, resolvers must re-query
```

**TTL tradeoffs:**
- **Low TTL (60s)**: Changes propagate quickly. Good for dynamic services (rolling deployments, failover). But increases DNS query volume and load on nameservers.
- **High TTL (86400s = 24h)**: Reduces DNS query volume, faster responses (cache hits). But if you change the IP, old clients keep using the old IP for up to 24 hours.

**For home.lab internal names**, TTL doesn't matter much since AdGuard Home is authoritative and the cache is local. But for Let's Encrypt TXT validation records, you want the TTL to be low (300s) so the challenge propagates quickly.

**How to check AdGuard Home's cache:**
```bash
# AdGuard Home exposes query logs in its web UI (192.168.1.96:8080)
# You can also force a cache flush via the API:
curl -X POST http://192.168.1.96:8080/control/cache_clear
```

---

## How AdGuard Home Works as a DNS Sinkhole

AdGuard Home is a **DNS sinkhole**—it intercepts DNS queries and lies to clients about ad/tracker domains.

**The flow for an ad domain:**
```
Phone visits website → page loads JS → JS tries to load ad from "ads.doubleclick.net"
  → DNS query: ads.doubleclick.net ?
  → AdGuard Home checks: "ads.doubleclick.net" matches blocklist ✓
  → Returns 0.0.0.0 (or 127.0.0.1)  ← The LIE (NXDOMAIN or null IP)
  → Browser tries to connect to 0.0.0.0 → connection refused immediately
  → Ad never loads. Page loads faster, less data used.
```

**Why this is powerful**: It blocks ads at the *network level*, not just in one browser. Every device on your LAN—phone, TV, smart home devices, gaming console—gets ad filtering. The blocklists (like Steven Black's Hosts or AdGuard's own filters) contain hundreds of thousands of known ad/tracker domains.

**What AdGuard Home doesn't block**: Ads served from the *same domain* as the content (YouTube's `youtube.com` serves both videos and ads), or HTTPS sites that serve ads from their own servers. DNS can only block by domain, not by URL path.

**Custom DNS rewrites in AdGuard Home**: This is how `jellyfin.home.lab → 192.168.1.96` works. You add a rewrite rule in the GUI: Domain=`*.home.lab`, Answer=`192.168.1.96`. AdGuard Home returns this A record authoritatively without forwarding to upstream.

---

## DNS-over-HTTPS, DNS-over-TLS, DNS-over-QUIC

Plain DNS (UDP/53) has two problems:
1. **No encryption**: Anyone between you and the resolver can see every domain you visit (your ISP, Wi-Fi network operators).
2. **No authentication**: Responses can be spoofed (DNS cache poisoning).

The solutions:

**DNS-over-TLS (DoT, port 853)**: Wraps the DNS query in a TLS connection. Simple—same DNS wire format, just encrypted. The port (853) reveals that you're doing DNS, even if the content is encrypted.

**DNS-over-HTTPS (DoH, port 443)**: Wraps DNS in an HTTPS connection. Looks identical to web traffic—impossible for ISPs to selectively block without blocking all HTTPS. Firefox enables DoH by default. AdGuard Home can both *receive* DoH queries (from apps) and *forward* as DoH to upstream resolvers like Cloudflare (`https://cloudflare-dns.com/dns-query`).

**DNS-over-QUIC (DoQ, port 853)**: Uses QUIC (UDP-based) instead of TCP+TLS. Faster connection establishment (0-RTT resumption), better multiplexing. Newest, least supported.

**In your AdGuard Home config**, you can enable DoT/DoH listening and configure upstream servers to be DoH providers. This means:
- Your devices → DoH → AdGuard Home (encrypted on LAN, though LAN is trusted)
- AdGuard Home → DoH → Cloudflare/NextDNS (encrypted to upstream)

---

## Split-Horizon DNS: LAN vs. WAN Resolution

**Split-horizon DNS** (also called split-brain DNS) means the same domain name resolves to *different IPs* depending on where you're asking from.

**Your homelab example:**
```
On your LAN (192.168.1.0/24):
  Query "jellyfin.home.lab" → AdGuard Home → 192.168.1.96
  Direct connection, no VPN overhead, full LAN speed

On mobile data (away from home):
  No access to 192.168.1.96 (private RFC-1918 address, unreachable over internet)
  Need Tailscale to reach home network
  
  With Tailscale subnet router advertising 192.168.1.0/24:
    "jellyfin.home.lab" → must configure Tailscale DNS or MagicDNS
    → resolves to 192.168.1.96
    → traffic routes through Tailscale tunnel to home network
    → arrives at 192.168.1.96 (your laptop)
```

**Implementing split-horizon in AdGuard Home**: The custom rewrites (e.g., `*.home.lab → 192.168.1.96`) only work for devices using AdGuard Home as their DNS server. When you're on Tailscale, you either:
1. Configure Tailscale to also use AdGuard Home as the DNS server (via Tailscale DNS settings in the admin panel).
2. Or use Tailscale's MagicDNS which auto-assigns `machinename.tailnet-name.ts.net` names.

---

## DNSSEC: Cryptographic Chain of Trust

DNSSEC (DNS Security Extensions) adds digital signatures to DNS records, preventing cache poisoning attacks.

**The problem DNSSEC solves:**
```
Attack: Kaminsky DNS Cache Poisoning (2008)
  Attacker sends thousands of forged DNS responses to a resolver
  trying to inject a fake record: "bank.com → 1.2.3.4 (attacker's server)"
  If the resolver accepts the forged response, ALL its clients get the wrong IP
  
  DNSSEC prevents this: the correct resolver can verify the signature
  and reject forged responses.
```

**DNSSEC mechanism:**
1. Each zone has a **Zone Signing Key (ZSK)** and **Key Signing Key (KSK)**.
2. Every DNS record is signed with the ZSK to produce an **RRSIG** record.
3. The KSK's fingerprint (DS record) is published in the parent zone.
4. The chain goes: root zone signs `.com` DS record → `.com` zone signs `netflix.com` DS record → `netflix.com` zone signs its own records.
5. The root zone's public key is hardcoded in resolver software (the "trust anchor").

**Validation:**
```
Resolver gets netflix.com A record + RRSIG
  → Fetches netflix.com DNSKEY records
  → Verifies RRSIG with public key
  → Fetches netflix.com DS record from .com zone
  → Verifies DS record matches DNSKEY
  → Fetches .com DS record from root zone
  → Chain of trust verified back to hardcoded root trust anchor ✓
```

**For home.lab**: DNSSEC is irrelevant for your internal `.home.lab` names since AdGuard Home is authoritative and you trust it. But when AdGuard Home forwards to upstream resolvers, those resolvers perform DNSSEC validation—you can enable "Enable DNSSEC" in AdGuard Home settings to request and validate signed responses.

---

<a name="section-4"></a>
# Section 4: HTTP, HTTPS, Reverse Proxies & TLS

## HTTP Evolution: 1.1 → 2 → 3

### HTTP/1.1 (1997, still widely used)

HTTP/1.1 is text-based. A request looks like:
```http
GET /web/index.html HTTP/1.1
Host: jellyfin.home.lab
Connection: keep-alive
Accept: text/html,application/xhtml+xml
Accept-Encoding: gzip, deflate
User-Agent: Mozilla/5.0 ...

```
(Blank line marks end of headers; request body follows for POST/PUT)

**Problems with HTTP/1.1:**
- **Head-of-line (HOL) blocking**: Requests on a single connection must be processed in order. If request 3 is slow, requests 4 and 5 wait.
- **Solution (workaround)**: Browsers open 6-8 parallel TCP connections per domain. Wasteful.
- **Header repetition**: Every request sends full headers (cookies, user-agent, etc.) even if they haven't changed.

### HTTP/2 (2015)

HTTP/2 is binary, not text. Key innovations:

**Multiplexing**: Multiple requests share a single TCP connection as independent *streams*. Each HTTP request/response is split into **frames** tagged with a Stream ID. The receiver reassembles frames by ID.

```
TCP connection
  ├─ Stream 1: GET /api/users → response 200 OK
  ├─ Stream 3: GET /style.css → response 200 OK  (parallel!)
  ├─ Stream 5: GET /logo.png → response 200 OK   (parallel!)
  └─ Stream 7: GET /data.json → response 200 OK  (parallel!)
```

**Header compression (HPACK)**: Headers are compressed using a static table (common headers like `:method: GET` are encoded as a single byte) and a dynamic table (headers seen before are referenced by index instead of repeated). Saves 50-90% of header bytes.

**Server Push**: Server can proactively send resources the client will need. (Largely abandoned in practice due to poor cache interaction.)

**Still has HOL blocking!** HTTP/2 multiplexes over a single TCP connection. If a TCP packet is lost, TCP's reliable delivery stops all streams until the packet is retransmitted—all streams are blocked. This is "TCP HOL blocking" (different from HTTP/1.1's "HTTP HOL blocking").

### HTTP/3 (2022)

HTTP/3 solves TCP HOL blocking by replacing TCP with **QUIC** (UDP-based).

- **QUIC** runs over UDP. Each stream is independent at the transport level. Losing a UDP packet for stream 3 doesn't affect stream 5.
- **0-RTT connection establishment**: QUIC can resume a connection in 0 RTT (compared to TCP+TLS which needs 3-RTT for new connections). Huge win for mobile networks that constantly switch between Wi-Fi and cellular.
- **Connection migration**: QUIC connections are identified by a Connection ID, not an IP:port tuple. If your phone switches from Wi-Fi to cellular (changing IP), the QUIC connection *continues* without interruption. A TCP connection would break.
- **Built-in encryption**: QUIC integrates TLS 1.3. There's no unencrypted QUIC.

**In your homelab**: Nginx Proxy Manager supports HTTP/2 out of the box. HTTP/3/QUIC requires specific configuration and UDP port 443. Most internal traffic will use HTTP/2; HTTP/3 is mainly valuable for public-facing high-traffic services.

---

## TLS Handshake: Securing the Connection

TLS (Transport Layer Security, successor to SSL) provides:
1. **Authentication**: Proves the server is who it claims to be (via certificates).
2. **Confidentiality**: Encrypts data so eavesdroppers can't read it.
3. **Integrity**: Detects tampering (message authentication codes).

**TLS 1.3 Handshake** (simplified):

```
Client (Browser)                    Server (Nginx Proxy Manager)
      │                                     │
      │──── ClientHello ───────────────────►│
      │  • TLS version: 1.3                 │
      │  • Cipher suites: TLS_AES_256_GCM   │
      │  • Key share: Curve25519 public key │  ← Client's ephemeral keypair
      │  • SNI: jellyfin.home.lab           │  ← Which domain!
      │                                     │
      │◄─── ServerHello ────────────────────│
      │  • Chosen cipher: TLS_AES_256_GCM   │
      │  • Key share: Server's Curve25519   │  ← Server generates its keypair
      │  • Certificate (jellyfin.home.lab)  │
      │  • CertificateVerify (signature)    │
      │  • Finished (MAC of handshake)      │
      │                                     │
      │  [Both sides compute shared secret using ECDH]
      │  Client public + Server private → shared secret
      │  Server public + Client private → same shared secret (magic of DH)
      │                                                        │
      │──── Finished (MAC of handshake) ──────────────────────►│
      │                                                        │
      │◄════════════ Encrypted Application Data ══════════════►│
      │         (AES-256-GCM or ChaCha20-Poly1305)            │
```

**Why Diffie-Hellman (DH) key exchange?**

The server's certificate contains its *public key* (used for authentication—to prove identity). But if you used that key to encrypt the session key, then if the server's private key was ever stolen, *all past sessions could be decrypted* (recorded traffic from years ago). This is the "no forward secrecy" problem.

**Elliptic Curve Diffie-Hellman Ephemeral (ECDHE)** solves this: both parties generate *temporary* (ephemeral) keypairs for each session. The session key is derived from these temporary keys. Even if the server's certificate private key is stolen later, past sessions are safe—the ephemeral keys were discarded after the handshake. This property is called **Perfect Forward Secrecy (PFS)**.

**Certificate chain of trust:**
```
Let's Encrypt Root CA  (trusted by browsers, built into OS)
  └─ Let's Encrypt R3 (intermediate CA)
       └─ jellyfin.home.lab (leaf certificate, signed by R3)
```

Your browser trusts Let's Encrypt's root CA. The root CA signed R3's certificate. R3 signed your server's certificate. Each signature can be cryptographically verified. This is the **chain of trust**.

---

## How Nginx Proxy Manager Works

When a request arrives at your laptop on port 443:

```
HTTPS request to jellyfin.home.lab:443

[1] Network stack receives TCP SYN on port 443
    → iptables DNAT (if running in Docker): 192.168.1.96:443 → container_ip:443

[2] Nginx Proxy Manager's SSL listener receives TLS ClientHello
    → Reads SNI extension: "jellyfin.home.lab"
    → Selects the right TLS certificate for that hostname
    → Completes TLS handshake with the correct cert

[3] NPM decrypts the HTTP request:
    GET /web/index.html HTTP/1.1
    Host: jellyfin.home.lab

[4] NPM looks up proxy rule: jellyfin.home.lab → http://jellyfin:8096
    (The name "jellyfin" resolves via Docker's internal DNS to the container IP)

[5] NPM creates a NEW HTTP connection to jellyfin:8096
    (This connection is internal, plain HTTP since it's local—Docker network)
    
[6] NPM forwards request, gets response, forwards response back to client
    (With proper X-Forwarded-For, X-Real-IP headers added)
```

**Why reverse proxy?** You only expose ports 80 and 443 to users (standard HTTP/HTTPS ports, no port numbers needed in URLs). NPM routes based on hostname. One IP, many services, clean URLs.

**Security benefit**: NPM applies TLS termination, so your backend services (Jellyfin, Immich, etc.) can run plain HTTP internally. The communication between NPM and backends is on the Docker `homelab-net` network—no need for TLS there.

---

## SNI: How One IP Serves Multiple HTTPS Domains

**The Problem**: Before SNI, a TLS server had to present its certificate *before* knowing which domain the client wanted (TLS handshake happened before the HTTP Host header was visible). So one IP could only have one TLS certificate.

**SNI (Server Name Indication)**: An extension to TLS where the client includes the target hostname in the *ClientHello* message (before encryption starts). The server reads this, selects the right certificate, and proceeds.

```
ClientHello includes:
  server_name extension: "jellyfin.home.lab"
  
Nginx sees: "jellyfin.home.lab" → use /etc/letsencrypt/live/jellyfin.home.lab/
```

Now `192.168.1.96:443` can serve `jellyfin.home.lab`, `immich.home.lab`, `filebrowser.home.lab`—each with its own certificate. NPM handles all of this automatically.

**Privacy caveat**: SNI is sent *unencrypted* in the ClientHello (before the TLS channel is established). Your ISP or local network can see *which domain* you're connecting to, even if they can't see the content. This is why **ESNI (Encrypted SNI)** / **ECH (Encrypted Client Hello)** is being standardized in TLS 1.3.

---

## Let's Encrypt & the ACME Protocol

**Let's Encrypt** is a free, automated Certificate Authority. Before it existed (2015), TLS certificates cost $50-$200/year and required manual processes. Now they're free and auto-renewed.

**How ACME (Automatic Certificate Management Environment) works:**

For `HTTP-01` challenge (for public domains):
```
1. Your server: "Please give me a cert for jellyfin.example.com"
2. Let's Encrypt: "Prove you control it. Place this token at:
                   http://jellyfin.example.com/.well-known/acme-challenge/TOKEN"
3. Your server puts the file there
4. Let's Encrypt fetches http://jellyfin.example.com/.well-known/acme-challenge/TOKEN
5. File found! Identity verified. Certificate issued.
```

**HTTP-01 won't work for home.lab** (not publicly reachable). Use **DNS-01 challenge** instead:

```
1. Your server: "Please give me a wildcard cert for *.home.lab"
2. Let's Encrypt: "Add this TXT record: _acme-challenge.home.lab = XYZABC123"
3. Your server uses DNS provider API to add the TXT record
4. Let's Encrypt queries DNS and finds the TXT record
5. Identity verified! Wildcard cert issued for *.home.lab
```

NPM supports DNS-01 challenges for many DNS providers (Cloudflare, Route53, etc.). The wildcard cert `*.home.lab` would cover `jellyfin.home.lab`, `immich.home.lab`, etc.

**Certificate lifetime**: Let's Encrypt certs expire in 90 days (intentionally short to encourage automation). NPM auto-renews them ~30 days before expiry.

---

## WebSockets and Server-Sent Events

**WebSockets**: HTTP connection upgraded to a full-duplex, persistent binary channel.

```
Client sends:
  GET /socket HTTP/1.1
  Upgrade: websocket
  Connection: Upgrade
  Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==

Server responds:
  HTTP/1.1 101 Switching Protocols
  Upgrade: websocket
  Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=

Now both sides can send messages at any time in either direction.
```

**Used in Dockge** for real-time log streaming. When you tail container logs in Dockge's UI, the browser has a WebSocket connection to the Dockge server. As new log lines arrive (Docker log streaming via `docker.sock`), they're pushed to the browser instantly.

**Used in Uptime Kuma** for live heartbeat updates. The dashboard shows monitors updating in real time—that's WebSocket pushing status changes from server to browser.

**NPM WebSocket config**: You must enable "WebSockets Support" in NPM's proxy host settings, or you'll get `502 Bad Gateway` on WebSocket upgrades. NPM adds the necessary `Upgrade` and `Connection` headers to forward the WebSocket correctly.

**Server-Sent Events (SSE)**: One-directional version—server pushes to client only. Uses regular HTTP with `Content-Type: text/event-stream`. Simpler than WebSocket (no upgrade needed), but only server→client. Used for notification feeds, progress bars.

---

<a name="section-5"></a>
# Section 5: Docker Networking Deep Dive

## The Linux Kernel Plumbing: veth, Bridge, iptables

Docker networking is built on Linux kernel primitives. No black magic—just pipes and filters.

**Virtual Ethernet Pairs (veth)**:
A `veth` is a pair of network interfaces connected like a virtual pipe: anything going into one end comes out the other. When Docker creates a container, it creates a veth pair:
- One end goes into the container's **network namespace** (seen as `eth0` inside the container)
- Other end stays in the **host's network namespace** (seen as `veth3f4a2b` or similar)

```bash
# On host, you can see container veths:
ip link show | grep veth
# veth3f4a2b@if5: ...  (the @if5 means paired with interface index 5 inside the container)

# Inside the container:
ip link show
# eth0@if8: ...  (paired with interface index 8 on the host)
```

**Linux Bridge (`docker0`, `br-homelab-net`)**:
A Linux bridge acts like a virtual Layer 2 switch. All veth host-ends are "plugged into" the bridge. Traffic between containers on the same network flows through the bridge at Layer 2 (no routing needed for same-subnet containers).

```
Host Network Namespace:
                    ┌──────────────────────────┐
  wlp3s0 ─────────►│    Linux Bridge           │
  (via iptables    │    br-homelab-net          │
   MASQUERADE)     │    172.18.0.1              │
                   │                            │
                   │  veth_adguard ─────────────┼──► adguardhome namespace (eth0: 172.18.0.2)
                   │  veth_npm     ─────────────┼──► npm namespace         (eth0: 172.18.0.3)
                   │  veth_jellyfin ────────────┼──► jellyfin namespace    (eth0: 172.18.0.4)
                   │  veth_immich  ─────────────┼──► immich namespace      (eth0: 172.18.0.5)
                   └──────────────────────────────┘
```

**iptables MASQUERADE**: For containers to reach the internet, their traffic (source IP `172.18.x.x`) must be NATted to the host's IP `192.168.1.96`. Docker adds an iptables rule:
```
# Docker adds automatically:
iptables -t nat -A POSTROUTING -s 172.18.0.0/16 ! -o br-homelab-net -j MASQUERADE
# Translation: "If a packet originated from 172.18.0.0/16 and is going out any interface
#               EXCEPT br-homelab-net (leaving the Docker network), replace the source IP
#               with the host's outgoing interface IP."
```

---

## Container DNS Resolution

How does the `immich_server` container resolve `immich-postgres` (the PostgreSQL container's name)?

Docker runs an **embedded DNS server** at `127.0.0.11` inside every container. The container's `/etc/resolv.conf` points to this:
```
# Inside immich_server container:
cat /etc/resolv.conf
nameserver 127.0.0.11
options ndots:0
```

When `immich_server` does a DNS lookup for `immich-postgres`:
1. The query goes to `127.0.0.11` (Docker's embedded resolver).
2. Docker looks up `immich-postgres` in its internal service registry.
3. Finds: container `immich_postgres`, IP `172.18.0.7` (on `homelab-net`).
4. Returns the IP.

This is why your `immich_server` compose file uses `DB_HOSTNAME=immich-postgres`—it's the Docker container name, resolved by Docker's embedded DNS. No configuration needed, as long as both containers are on the same Docker network (`homelab-net`).

**Important detail from your compose file**:
```yaml
# stacks/03-storage/docker-compose.yml
environment:
  - DB_HOSTNAME=immich-postgres   ← container name, not IP
  - REDIS_HOSTNAME=immich-redis   ← same
```
If you put Immich and its database on *different Docker networks*, this DNS resolution would fail. They must share a network.

---

## Port Publishing: What `-p 8096:8096` Actually Does

When you declare:
```yaml
ports:
  - "8096:8096"
```

Docker adds iptables rules that make port 8096 on the *host* forward to port 8096 in the *container*:

```bash
# Docker creates something like:
iptables -t nat -A PREROUTING -p tcp --dport 8096 -j DNAT --to-destination 172.18.0.4:8096
iptables -t filter -A DOCKER -d 172.18.0.4/32 ! -i br-homelab-net -p tcp --dport 8096 -j ACCEPT
```

**Anatomy of the rule:**
- `PREROUTING`: Applied to packets as they arrive, before routing decisions.
- `DNAT`: Destination NAT—change the destination address.
- `--to-destination 172.18.0.4:8096`: Rewrite the destination to the container IP.

So when your phone sends a TCP packet to `192.168.1.96:8096`:
1. Arrives at host's network stack.
2. `PREROUTING` chain: "Port 8096? DNAT to 172.18.0.4:8096."
3. Packet is routed to the Docker bridge and delivered to the Jellyfin container.
4. Jellyfin responds to the phone's IP (response path uses MASQUERADE to handle the return).

**Binding to specific host IPs:**
```yaml
ports:
  - "127.0.0.1:8096:8096"  # Only accessible locally, not from LAN
  - "192.168.1.96:8096:8096"  # Only on LAN interface
  - "8096:8096"  # All interfaces (0.0.0.0)
```

For services you only access through NPM (like Immich's web UI), you could bind to `127.0.0.1` only, reducing your LAN attack surface.

---

## Docker Network Isolation

Containers on the same Docker network (`homelab-net`) can communicate freely. Containers on *different* Docker networks cannot (by default).

```
homelab-net (172.18.0.0/16):
  adguardhome ─┐
  npm          ├── All can talk to each other
  jellyfin     │
  immich        ─┘

docker0 (172.17.0.0/16):
  some_other_container ─ CANNOT reach homelab-net containers
```

The isolation is enforced by iptables rules Docker manages in the `DOCKER-ISOLATION-STAGE-1` and `DOCKER-ISOLATION-STAGE-2` chains. Packets from `br-homelab-net` going to `docker0` are DROPped.

**Why all your services share one network (homelab-net)**: It's simpler and they all need to communicate. NPM needs to reach Jellyfin, Immich, etc. by container name. This requires a shared network.

**More secure approach**: Put frontend containers (NPM) in a "frontend" network, backend containers (Jellyfin, Immich) in a "backend" network, and connect NPM to both. Database containers connect only to the backend network. This way, a compromised NPM container can't directly hit the Postgres database.

---

## Bind Mounts vs Named Volumes

**Bind Mount**: Maps a specific host path into the container.
```yaml
volumes:
  - /home/ghostblaster/Projects/homeLabs/appdata/jellyfin/config:/config
  # Host path ─────────────────────────────────────────────────  Container path
```
You can see and edit the files directly on the host. Easy to backup (just `rsync` the directory).

**Named Volume**: Docker manages the storage location (`/var/lib/docker/volumes/`).
```yaml
volumes:
  - jellyfin-config:/config  # Docker manages where this lives
```
More portable (works the same on any Docker host), but harder to access/backup directly.

**Your setup uses bind mounts** for everything: `${APPDATA_PATH}/...` maps to your NVMe. This is the right choice for a homelab—you know exactly where your data is.

**Filesystem namespaces**: Containers use Linux mount namespaces. Inside the container, `/config` exists as a real directory. But in the container's namespace, it's mounted from the host's `/home/ghostblaster/.../jellyfin/config`. The container doesn't see the rest of your host filesystem (unless you mount it). `docker run -v /:/host` would give the container your entire filesystem—a security hole.

---

## The NTFS File Locking Problem (Critical for Your Setup!)

Your storage drive (`/dev/sda2`) is mounted as NTFS3 at `/mnt/storage`:
```
/dev/sda2 on /mnt/storage type ntfs3 (rw,relatime,uid=1000,...)
```

This matters a lot for databases. Here's why:

**POSIX file locking**: Linux applications use `fcntl()` or `flock()` system calls to lock files. This is how databases ensure only one writer at a time. PostgreSQL, SQLite, and Redis all rely on these locks.

**NTFS doesn't support POSIX semantics properly**: The Linux NTFS3 driver implements some locking, but subtle incompatibilities exist:

**SQLite WAL (Write-Ahead Log) mode**: SQLite uses memory-mapped I/O and a specific locking protocol (shared-memory WAL index). This requires precise POSIX semantics that NTFS doesn't provide. Running SQLite in WAL mode on NTFS can cause database corruption.

**PostgreSQL's `flock()`**: PostgreSQL uses advisory locks for its postmaster.pid and other control files. NTFS-mounted filesystems may not properly enforce these, risking process conflicts.

**Your actual risk:**
- **Jellyfin** (SQLite database) → config on `/home/ghostblaster/.../jellyfin/config` (NVMe, ext4 or Btrfs) ✓ Safe
- **Immich-postgres** → `${APPDATA_PATH}/immich/postgres` (NVMe) ✓ Safe  
- **Filebrowser** database → `${APPDATA_PATH}/filebrowser/filebrowser.db` (NVMe) ✓ Safe
- **Media files** (`${STORAGE_PATH}/media/`) on NTFS → Just file reads, no database → ✓ Fine
- **Immich photos** (`${STORAGE_PATH}/photos`) on NTFS → Image files only → ✓ Fine

Your setup is actually correct! Database/config files live on NVMe (reliable POSIX fs), and NTFS is used only for bulk media storage (movies, photos—plain file reads/writes, no POSIX locking needed). 

---

<a name="section-6"></a>
# Section 6: VPNs & Zero-Trust Networking

## Traditional VPN Architecture

A classical VPN (OpenVPN, IPSec) uses a **hub-and-spoke** topology:

```
     [Remote Laptop] ──────────────────►┐
     [Remote Phone]  ──────────────────►│  [VPN Concentrator Server]
     [Remote Office] ──────────────────►│  (public IP, port forwarded)
                                        │        │
                                        └────────┘
                                                 │
                                         [Home Network]
                                         192.168.1.0/24
```

All traffic goes through the central VPN server. Problems:
1. You need a server with a public IP and open ports (router port forwarding required).
2. All traffic is routed through one point—if it's slow, everything is slow.
3. Mobile devices behind CGNAT can't receive connections (see below).
4. Certificate management, key distribution, user management is complex.

---

## WireGuard: Modern Cryptographic VPN

WireGuard is a modern VPN protocol built into the Linux kernel (since 5.6). Tailscale uses it underneath.

**Cryptographic foundation:**

| Function | Algorithm | Why |
|---|---|---|
| Key exchange | Curve25519 ECDH | Fast, secure, constant-time |
| Authenticated encryption | ChaCha20-Poly1305 | Fast on CPUs without AES-NI, also secure |
| Hashing | BLAKE2s | Fast, secure |
| Key derivation | HKDF | Standard KDF |

**WireGuard packet flow:**

```
Sender's plaintext IP packet:
  Src: 192.168.1.96  Dst: 10.0.0.1  (inner packet, private network)
  
WireGuard wraps it:
  Outer UDP packet:
    Src: 203.0.113.45:41234  Dst: 198.51.100.2:51820  (public IPs, WG port)
    Payload: [WireGuard header][ChaCha20-Poly1305 encrypted inner packet]
                    ↑ counter (replay protection)
```

**The WireGuard Handshake** (Noise_IKpsk2 protocol):
1. Each peer has a static keypair (like SSH keys). Public keys are pre-shared.
2. Peers mutually authenticate using these static keys.
3. Two ephemeral keypairs are generated for forward secrecy.
4. A session key is derived. 
5. Subsequent packets are encrypted with this session key.
6. WireGuard re-initiates the handshake every 180 seconds and rotates keys.

**WireGuard's interface is dead simple:**
```bash
# /etc/wireguard/wg0.conf
[Interface]
PrivateKey = <your_private_key>
Address = 10.0.0.1/24
ListenPort = 51820

[Peer]
PublicKey = <peer_public_key>
AllowedIPs = 10.0.0.2/32  # Only route this peer's IP through tunnel
Endpoint = 1.2.3.4:51820  # Peer's public address
```

"AllowedIPs" is both a routing rule and an access control list. Packets from the peer must have a source IP in AllowedIPs, or they're dropped.

---

## Tailscale: WireGuard with a Control Plane

WireGuard is the cryptographic engine. Tailscale adds the **coordination layer** that makes it work without manual configuration.

**The three planes of Tailscale:**

```
┌─────────────────────────────────────────────────────────────────┐
│                    CONTROL PLANE                                 │
│            Tailscale Coordination Servers                        │
│        (login.tailscale.com, hosted by Tailscale Inc.)          │
│                                                                  │
│  - Manages public keys for all your devices                      │
│  - Distributes key updates when devices join/leave               │
│  - Issues short-lived node keys (24-hour validity)               │
│  - Provides access control policy (ACL rules)                    │
└──────────────────────────┬──────────────────────────────────────┘
                           │ HTTPS (for key exchange only)
                           │
┌─────────────────────────────────────────────────────────────────┐
│                     DATA PLANE                                   │
│           Direct WireGuard connections between nodes             │
│                                                                  │
│  Laptop (100.x.x.x) ←──WireGuard UDP──► Phone (100.y.y.y)      │
│                                                                  │
│  If direct path fails: DERP relay servers used                  │
└─────────────────────────────────────────────────────────────────┘
```

**NAT Traversal (How Tailscale connects peers behind NAT):**

The hard problem: both your laptop and your phone are behind NAT. Neither has a public IP for the other to connect to directly.

**STUN (Session Traversal Utilities for NAT)**: A lightweight protocol. Your device sends a UDP packet to a STUN server (public IP). The STUN server echoes back the *public* IP:port your NAT assigned for that UDP flow. Your device learns "my public address is `203.0.113.45:61024`." It shares this with the peer via the coordination server.

**Hole punching**: Both peers simultaneously send UDP packets to each other's NAT-mapped address. Each outgoing packet creates an inbound allow-rule in the respective NAT table. If both packets hit the right windows, the NAT tables on both sides open up, and subsequent packets flow directly.

```
Laptop (behind NAT, public: 203.0.113.45:61024)
Phone (behind CGNAT, public: 100.64.0.X:random)

1. Both learn each other's public NAT mapping (via Tailscale coordination)
2. Laptop sends UDP to 100.64.0.X:random simultaneously with
3. Phone sends UDP to 203.0.113.45:61024
4. NAT tables on both sides create inbound entries
5. ??? (magic) Direct WireGuard connection established!
```

**CGNAT Problem**: Mobile ISPs use "Carrier-Grade NAT" with IP range `100.64.0.0/10`. Your phone might be behind your home router NAT *and* the carrier's CGNAT—double NAT. Hole punching fails for some double-NAT scenarios.

**DERP (Designated Encrypted Relay for Packets)**: Tailscale's fallback relays. If direct connection fails, traffic flows through the nearest DERP server (Tailscale runs them in many regions). Traffic is end-to-end encrypted—the DERP server sees only encrypted WireGuard packets, not content.

Your Tailscale IP is in `100.64.0.0/10` — Tailscale deliberately chose the CGNAT range for its overlay network IPs, knowing this range is never used for anything else on the internet.

---

## Tailscale Subnet Router

When you run:
```bash
tailscale up --advertise-routes=192.168.1.0/24
```

Your laptop becomes a **subnet router** for your home network. This means remote Tailscale devices (your phone on cellular) can reach **all** devices on `192.168.1.0/24`, not just your laptop.

**How it works:**

```
Phone (on cellular, 100.y.y.y)
  "I want to reach 192.168.1.50 (your TV!)"
  
  Routing decision: 192.168.1.0/24 is advertised by laptop (100.x.x.x)
  → Send packet to laptop's Tailscale IP: 100.x.x.x
  
Laptop receives packet:
  WireGuard decapsulates → inner packet: Src=100.y.y.y Dst=192.168.1.50
  Kernel routes to wlp3s0 (192.168.1.0/24 is local)
  → Delivers to TV at 192.168.1.50
  
TV responds to 100.y.y.y (Tailscale IP):
  Laptop intercepts (it's the default gateway for the TV, via subnet router NAT)
  Re-encapsulates in WireGuard → sends to phone
```

Subnet routing uses **IP masquerading**: the laptop NATSs packets from the Tailscale network to the LAN. Devices on the LAN (TV, router) don't need Tailscale installed—they just see packets from `192.168.1.96`.

**Route propagation**: This is analogous to BGP route advertisement. The laptop tells the coordination server "I can reach `192.168.1.0/24`." The coordination server distributes this to all authorized Tailscale nodes on your tailnet. Those nodes add `192.168.1.0/24 via 100.x.x.x` to their routing tables.

---

<a name="section-7"></a>
# Section 7: Video Streaming & Low-Latency Protocols

## Jellyfin: Direct Play vs Transcode

When a client (browser, Jellyfin app) requests a video, Jellyfin does capability negotiation:

```
Client connects:
  "I support: H.264 (High Profile L5.1), H.265/HEVC, VP9, AV1"
  "I support: AAC, AC3, EAC3, FLAC"
  "Max bitrate: 80 Mbps"
  "Container: MKV, MP4, TS"

Server evaluates the source file:
  Video: H.264 High Profile → client supports ✓
  Audio: AAC 2-channel → client supports ✓
  Container: MKV → client supports ✓
  Bitrate: 15 Mbps → under client max ✓
  
Result: DIRECT PLAY → HTTP byte-range request, no processing
  "Serve the file as-is"
  client just plays raw bytes
```

**Direct Play** is the ideal path: zero CPU/GPU overhead on the server, perfect quality (no re-encoding degradation).

**Transcoding** happens when the client can't play the source format:
```
Source: H.265 (HEVC) 4K HDR MKV
Client (older TV): "I only support H.264"

Result: TRANSCODE
  Jellyfin must decode H.265 → raw YUV frames → encode as H.264 → stream
  Software: 4K H.265 decode = very CPU-heavy (i5-1035G1 would struggle)
  Hardware: Intel QuickSync offloads this to the GPU
```

---

## Intel Quick Sync Video: The Hardware Video Engine

Your i5-1035G1 is an Ice Lake processor with **Intel Iris Plus Graphics G1**. It includes dedicated fixed-function silicon for video encode/decode called **Quick Sync Video**.

**The software stack:**

```
Application (Jellyfin)
    │
    │  calls
    ▼
libva (VA-API interface library)
    │
    │  calls
    ▼
libva-intel-driver or intel-media-driver  (iHD driver for Gen 11+)
    │
    │  calls
    ▼
i915 kernel driver  (DRM/KMS driver for Intel GPU)
    │
    │  submits GPU commands
    ▼
Intel Iris Plus G1 GPU  (fixed-function video engine)
```

**VA-API (Video Acceleration API)**: The standard Linux API for hardware video encode/decode. Applications call `vaCreateContext()`, `vaBeginPicture()`, etc. The driver translates these into GPU commands.

**DRM (Direct Rendering Manager)**: The Linux kernel subsystem managing GPU access. `/dev/dri/renderD129` is the Intel GPU's *render node*—an unprivileged interface for compute/media operations (GPU doesn't need display access for this, unlike `/dev/dri/card2`).

**Your Jellyfin container config:**
```yaml
devices:
  - /dev/dri/renderD129:/dev/dri/renderD129  # Render node (VA-API)
  - /dev/dri/card2:/dev/dri/card2            # DRM card (needed for some ops)
group_add:
  - "989"  # render group (allows /dev/dri/renderD129 access)
  - "985"  # video group  (allows /dev/dri/card2 access)
```

The permissions from `ls -la /dev/dri/`:
```
crw-rw-rw-  1 root render 226, 129  renderD129  ← world-readable render node
crw-rw----+ 1 root video  226,   2  card2       ← needs video group
```

`renderD129` is `rw-rw-rw-` (world-readable), so the `render` group addition might be redundant. But it's good practice. The `video` group is required for `card2`.

**What happens during Quick Sync transcode (e.g., H.265 → H.264):**

```
1. Jellyfin reads video from NAS/storage file
2. VA-API decodes H.265 frame into GPU VRAM (DMA-BUF)
   ← The HEVC decode engine does this at hardware speed
3. (Optional: frame-level processing: subtitle burn-in, tone mapping for HDR)
4. VA-API encodes the raw frame as H.264 into a buffer
   ← The H.264 encode engine does this at hardware speed
5. Encoded frame is read back to CPU memory
6. Multiplexed into MPEG-TS or fragmented MP4 stream
7. Sent over HTTP to the client
```

Steps 2 and 4 are **zero-copy on the GPU** (data never leaves VRAM between decode and encode). Your i5-1035G1's Gen 11 GPU can do this simultaneously for multiple streams without significantly impacting the CPU.

**Performance numbers** (approximate for i5-1035G1 Ice Lake):
- H.265 hardware decode: up to ~4K @ 60fps
- H.264 hardware encode: up to ~4K @ 30fps
- H.264 hardware decode: up to ~4K @ 60fps
- Power consumption for transcode: ~3-5W extra (vs. 30-40W for software)

---

## Sunshine/Moonlight: The Game Streaming Protocol

Sunshine is an open-source implementation of NVIDIA's GameStream protocol (NvStream). It allows streaming your desktop to Moonlight clients with sub-15ms latency.

### Architecture

```
Laptop (Sunshine server)          TV (Moonlight client)
         │                                │
  ┌──────┴────────┐               ┌───────┴──────┐
  │ Capture       │               │ Decode       │
  │ (KMS/DRM)     │               │ Hardware H.264│
  │ Encode (VAAPI)│               │ Display       │
  │ Stream (RTP)  │               │ Input fwd.    │
  └───────────────┘               └──────────────┘
         │          Wi-Fi LAN              │
         │◄───────RTSP Control────────────►│
         │──────── RTP Video (UDP) ───────►│
         │◄──────── RTCP Feedback ─────────│
         │◄───── Input (controller/kb) ────│
         │──────── OPUS Audio (UDP) ──────►│
```

**Protocol stack:**

**RTSP (Real-Time Streaming Protocol)**: A signaling/control protocol (TCP). Like SIP for video. Sunshine and Moonlight use it to:
- Negotiate codec parameters (H.264 profile, bitrate, resolution, FPS)
- Set up RTP sessions (what ports to use)
- Handle session teardown

**RTP (Real-Time Protocol)**: Carries the actual video payload over UDP. Each RTP packet has:
```
RTP Header:
  - Version: 2
  - Timestamp: media timeline position
  - Sequence Number: for ordering/loss detection
  - SSRC: stream identifier
  - Payload Type: H.264
RTP Payload:
  - H.264 NAL units (video data)
```

**RTCP (RTP Control Protocol)**: Runs alongside RTP on a companion port. Moonlight sends RTCP Receiver Reports back to Sunshine:
- "I received 98% of packets (2% loss)"
- "My jitter is 3ms"
- "My estimated RTT is 8ms"

Sunshine uses this feedback to:
- Adjust bitrate (reduce if loss > threshold)
- Tune FEC (add more redundancy if loss is high)

**Forward Error Correction (FEC)**: Sunshine sends redundant "parity" packets alongside video data. If a video packet is lost, the receiver can *reconstruct it* from the parity packets (like RAID-6 parity). This adds bandwidth overhead but eliminates the need for retransmission (which would add latency). FEC is derived from erasure codes (Reed-Solomon or XOR-based).

---

## Sunshine's Wayland/PipeWire Capture

On X11, screen capture is simple: `XShmGetImage()` reads pixels from X server buffers. On Wayland/Hyprland, there's no central X server—security is better but capture is harder.

**Sunshine's capture path on Hyprland (Wayland):**

```
Hyprland compositor
    │
    │ DRM/KMS output (GPU renders directly to display)
    │
    ▼
/dev/dri/card2   (KMS node)
    │
    │ Sunshine uses wlr-export-dmabuf-unstable-v1 Wayland protocol
    │ OR uses PipeWire screen capture (portal)
    │
    ▼
DMA-BUF (Direct Memory Access Buffer)
    │
    │ GPU texture shared without copying to CPU RAM ← "zero-copy"
    │
    ▼
VA-API H.264 encode (directly from DMA-BUF)
    │
    ▼
RTP packets → Wi-Fi → Moonlight
```

**DMA-BUF** is a Linux kernel mechanism for sharing GPU memory between processes and drivers without copying data through CPU RAM. The GPU buffer holding your rendered desktop is shared directly to the VA-API encoder. This is why capture overhead is tiny.

**PipeWire** is the modern audio/video server on Linux (replaces PulseAudio for audio, V4L2/X11 for video routing). Sunshine can use PipeWire's `xdg-desktop-portal-wlr` for screen capture. PipeWire acts as a broker between Hyprland's output and Sunshine's input.

---

## Latency Budget: How Sub-15ms Glass-to-Glass Works

"Glass-to-glass" latency = time from photon hitting your laptop screen to photon reaching the TV screen.

```
Component                     Typical Latency
─────────────────────────────────────────────
Screen capture (KMS/DMA-BUF)   0.1 - 1ms
H.264 encode (QuickSync)        2 - 5ms
RTP packetization              0.1ms
Wi-Fi transmission              1 - 3ms  (802.11ac, 5GHz)
Network jitter buffer           2 - 5ms  (to handle jitter)
Moonlight receive + decode      1 - 3ms  (hardware H.264)
Display rendering + vsync       0 - 16ms (60Hz = 16ms per frame)
─────────────────────────────────────────────
Total:                          ~6 - 33ms
Best case (wired, 120Hz):       ~3 - 8ms
```

**Key latency reducers:**
- **Hardware encode/decode** (QuickSync on both ends): Software codec would add 20-50ms.
- **Fixed-interval capture**: Sunshine captures frames at exactly the display refresh rate, avoiding variable delays.
- **Low jitter buffer**: Moonlight keeps a small jitter buffer (you can tune this). Smaller buffer = lower latency but more stutters on jitter spikes.
- **5GHz Wi-Fi**: Lower congestion, higher bandwidth than 2.4GHz.
- **Wired connection**: Adds Ethernet's deterministic 0.1ms latency. If your TV has Ethernet and your router is nearby, a cable is worth it.

**FPS vs Latency**: 60fps = a new frame every 16.7ms. If your total pipeline latency exceeds 16.7ms, the viewer sees frames from 2+ frames ago (at least 33ms lag). Hardware codecs that encode in <8ms allow 60fps to feel responsive.

---

## PulseAudio Network Audio (Your TV Audio Trick)

Your `tv-tools.sh` uses `pactl load-module module-tunnel-sink` to route laptop audio to the TV's speakers via PipeWire/PulseAudio over TCP.

**How the PulseAudio TCP module works:**

On the TV (Termux PulseAudio server):
```bash
pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1;192.168.0.0/16"
```
This starts a PulseAudio daemon that accepts TCP connections from `192.168.0.0/16` and exposes the TV's audio output as a networked sink.

On the laptop:
```bash
pactl load-module module-tunnel-sink server=tcp:192.168.1.50:4713 sink_name=tv_soundbar
```
This creates a virtual audio output device (`tv_soundbar`). When you route audio to it, PulseAudio on the laptop:
1. Encodes PCM audio into chunks (the ring buffer).
2. Sends over TCP to `192.168.1.50:4713` (TV's PulseAudio).
3. TV's PulseAudio plays it through the TV's audio output.

**PCM audio**: Raw uncompressed audio. Each sample is 16 or 24 bits. At CD quality (44100 Hz, stereo, 16-bit), that's `44100 × 2 × 2 = 176 KB/s`. Your Wi-Fi handles this trivially.

**Latency**: PulseAudio negotiates a latency with the tunnel sink (default ~200ms to accommodate network jitter). You can tune it:
```bash
pactl load-module module-tunnel-sink server=... latency_msec=100
```
Lower = more responsive but more likely to stutter. For music/movies, 200ms is fine. For interactive use (games with Moonlight), you'd want Sunshine's built-in audio streaming (Opus-encoded, lower latency).

---

## Streaming Protocol Comparison

| Protocol | Transport | Latency  | Use Case                          |
|---|---|---|---|
| **RTSP/RTP** | UDP     | <100ms   | Sunshine/Moonlight, IP cameras    |
| **WebRTC**  | UDP (DTLS)| <50ms   | Browser-to-browser, video calls   |
| **SRT**     | UDP     | 100-300ms | Contribution feeds, OBS streaming |
| **HLS**     | HTTP/TCP| 10-30s   | Live TV, CDN delivery, Jellyfin fallback |
| **DASH**    | HTTP/TCP| 2-30s    | Netflix, YouTube (adaptive)       |
| **RTMP**    | TCP     | 3-5s     | OBS → Twitch/YouTube ingest       |

**HLS (HTTP Live Streaming)**: Splits video into 2-10 second segments (`.ts` files). Client downloads segments sequentially. Easy to implement, works over CDN, but latency = segment duration + a few segments buffer.

**Jellyfin uses HLS for browser streaming**: When you watch in a browser without a native app, Jellyfin transcodes to HLS. That's why it has more latency than the native Jellyfin app (which can do direct play or use different protocols).

**WebRTC**: The most complex but most powerful. Used for video calls (Google Meet, Jitsi). Includes built-in STUN/TURN NAT traversal (same concepts as Tailscale), adaptive bitrate, codec negotiation, encryption. Could theoretically replace Sunshine/Moonlight for remote desktop, but the ecosystem/tooling isn't there yet.

---

<a name="section-8"></a>
# Section 8: Linux Kernel Internals Relevant to Homelab

## /dev/dri: The Direct Rendering Manager

Your `/dev/dri/` directory:
```
/dev/dri/
├── by-path/
├── card1   (minor 226:1)  ← Intel integrated GPU (UHD 620 or similar)
├── card2   (minor 226:2)  ← Intel Iris Plus G1 (primary display)
├── renderD128 (minor 226:128) ← Render node for card1
└── renderD129 (minor 226:129) ← Render node for card2 (what Jellyfin uses)
```

**DRM (Direct Rendering Manager)**: The Linux kernel subsystem that manages GPU hardware. Before DRM, userspace OpenGL implementations directly accessed GPU registers, causing chaos. DRM provides:
- **Exclusive GPU access**: One context manages mode-setting (display configuration).
- **DMA buffer management**: GPU memory allocation, mapping, synchronization.
- **Kernel Mode Setting (KMS)**: Setting display resolution/refresh rate from kernel space, enabling smooth boot splash and VT switching.

**Card nodes vs Render nodes:**
- `/dev/dri/cardN`: Privileged. Required for KMS (display mode setting). Needs `video` group.
- `/dev/dri/renderDN`: Unprivileged. Compute and media operations only. Needs `render` group.

Jellyfin only needs to encode/decode video—it doesn't configure displays. So `renderD129` is sufficient (and more secure), but `card2` is also provided for compatibility.

**How VA-API calls become GPU commands:**
```
Jellyfin code:
  VADisplay dpy = vaGetDisplay(drm_fd);  // Opens renderD129
  vaCreateConfig(dpy, VAProfileH264High, VAEntrypointEncSlice, ...);
  vaCreateContext(dpy, config_id, width, height, ...);
  vaBeginPicture(dpy, context_id, surface);
  vaRenderPicture(dpy, context_id, bufs, num_bufs);
  vaEndPicture(dpy, context_id);
  vaSyncSurface(dpy, surface);  // Wait for GPU to finish

Translates to:
  intel-media-driver (iHD) → translates VA-API calls
  → GEM (Graphics Execution Manager) kernel interface
  → i915 driver submits GPU batch commands
  → Ring buffer → GPU executes Video Codec Engine (VCS)
  → Interrupt when done → vaSyncSurface() returns
```

---

## cgroups and Namespaces: The Foundation of Containers

"Container" is not a kernel primitive. Containers are built from two Linux kernel features: **namespaces** and **cgroups**.

**Namespaces** provide isolation—making a process think it's in a different world:

| Namespace | Isolates           | Example |
|---|---|---|
| **PID**   | Process IDs        | Container sees its own PID 1 (not host's init) |
| **NET**   | Network interfaces | Container has its own eth0, routing table |
| **MNT**   | Filesystem mounts  | Container sees its own `/`, `/proc`, `/sys` |
| **UTS**   | Hostname           | Container can have its own hostname |
| **IPC**   | IPC (semaphores, etc.) | Container IPC isolated from host |
| **USER**  | User/Group IDs     | Container UID 1000 ≠ host UID 1000 |
| **CGROUP**| cgroup hierarchy   | Container sees only its cgroup subtree |

When you run `docker run jellyfin/jellyfin`:
1. Docker calls `clone()` with namespace flags: `CLONE_NEWPID | CLONE_NEWNET | CLONE_NEWNS | CLONE_NEWUTS | CLONE_NEWIPC`
2. The new process (Jellyfin) is in new namespaces—it sees its own PID 1, its own `eth0`, its own filesystem root.
3. The container's filesystem is a *union mount* (OverlayFS): the image layers are stacked read-only, with a writable layer on top.

**cgroups (Control Groups)** limit resource usage:

```bash
# Docker creates cgroups like:
/sys/fs/cgroup/docker/<container_id>/
  memory.limit_in_bytes     # RAM limit
  cpu.cfs_quota_us          # CPU time limit
  blkio.throttle.read_bps_device  # Disk read limit
```

Your Immich machine learning container has:
```yaml
deploy:
  resources:
    limits:
      memory: 1500M  # → cgroup memory.limit = 1500MB
```
Without this, the ML model could consume all 16GB of RAM, starving other containers.

---

## iptables / nftables: Kernel Packet Filtering

The Linux kernel's `netfilter` subsystem lets userspace programs hook into packet processing. `iptables` and the newer `nftables` are userspace tools that configure these hooks.

**The netfilter hooks:**

```
Incoming packet:
  NIC → [PREROUTING] → routing decision → [FORWARD] → NIC (if forwarding)
                                        ↓
                                   [INPUT] → Process (if for this host)

Outgoing packet:
  Process → [OUTPUT] → routing → [POSTROUTING] → NIC
```

**Tables within netfilter:**
- `filter`: Allow/drop packets (firewall)
- `nat`: Address translation (SNAT, DNAT, MASQUERADE)
- `mangle`: Modify packet headers (QoS marking)
- `raw`: Bypass connection tracking

**Docker's iptables rules** (what gets created when you run your stacks):
```bash
# Docker creates these automatically:
iptables -t nat -N DOCKER
iptables -t nat -A PREROUTING -m addrtype --dst-type LOCAL -j DOCKER

# Port publishing: -p 8096:8096 creates:
iptables -t nat -A DOCKER -p tcp --dport 8096 -j DNAT --to-destination 172.18.0.4:8096

# Allow forwarded traffic to containers:
iptables -A FORWARD -d 172.18.0.4/32 ! -i br-homelab-net -p tcp --dport 8096 -j ACCEPT

# Masquerade container traffic going to internet:
iptables -t nat -A POSTROUTING -s 172.18.0.0/16 ! -o br-homelab-net -j MASQUERADE
```

**Why nftables?** It's the modern replacement for iptables, with a cleaner syntax, better performance (single traversal vs multiple tables), and atomic rule updates. Docker still uses iptables by default. On your Arch system, `/etc/nftables.conf` may contain base rules. Run `nft list ruleset` to see.

---

## Filesystem Hierarchy: Why These Directories Exist

```
/
├── /etc    Configuration files (text, human-readable)
│           AdGuard config in Docker? Mounted from APPDATA_PATH, similar concept
│           Actual: /etc/resolv.conf (DNS), /etc/hosts (static DNS)
│
├── /var    Variable data that changes at runtime
│           /var/log  - system logs (journald writes here)
│           /var/lib  - persistent app data
│           /var/run  → /run  - ephemeral runtime data (PID files, sockets)
│
├── /dev    Device files (kernel objects presented as files)
│           /dev/dri/renderD129  - your GPU
│           /dev/sda2            - your storage disk
│           /dev/null            - discard output
│           /dev/urandom         - secure random number source
│
├── /proc   Virtual filesystem: running kernel/process state
│           /proc/net/dev       - network statistics (you used this!)
│           /proc/meminfo       - memory stats
│           /proc/<pid>/        - per-process info, open files, namespaces
│           /proc/version       - kernel version
│
├── /sys    Virtual filesystem: hardware/driver configuration
│           /sys/fs/cgroup/     - cgroup hierarchy (Docker limits here)
│           /sys/class/net/     - network interface config
│           /sys/bus/pci/       - PCI device info (your GPU, NIC)
│
├── /mnt    Mount points for external drives
│           /mnt/storage       - your 1TB NTFS drive (sda2)
│
├── /run    Ephemeral (RAM-backed tmpfs)
│           /run/docker.sock   - Docker daemon socket
│           /run/user/1000/    - user session runtime dir
│
└── /home   User home directories
            /home/ghostblaster/Projects/homeLabs  - your project
```

**Why your appdata is on NVMe and media is on the HDD**: NVMe (`/dev/nvme0n1`) has:
- ~3000 MB/s reads (vs HDD's ~100 MB/s)
- Sub-1ms random I/O (vs HDD's ~10ms seek time)

Database random I/O (Postgres, SQLite) needs fast random access → NVMe. Sequential video reads (movies) → HDD is fine, sequential reads saturate HDD bandwidth anyway.

---

## systemd: The Init System and Service Manager

systemd is PID 1 on your Arch system. Everything else descends from it.

**Unit files** describe services:
```ini
# /etc/systemd/system/docker.service (Docker daemon)
[Unit]
Description=Docker Application Container Engine
After=network-online.target firewalld.service
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/dockerd -H fd://
ExecReload=/bin/kill -s HUP $MAINPID
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
```

**User systemd units** (`--user`):
```bash
systemctl --user enable --now sunshine
```
This creates a socket/service in `/home/ghostblaster/.config/systemd/user/`. It starts when you log in and stops when you log out—unless you enable **lingering**:
```bash
loginctl enable-linger ghostblaster
# Now user services start at boot even without login
```

**Socket activation**: systemd creates a socket, and only starts the service when a connection arrives. This allows instant service availability (the socket is always ready) without wasting RAM (the service isn't loaded until needed).

---

## Linux Power Management: Keeping the Laptop Alive

Your setup from the README:
```bash
# /etc/systemd/logind.conf.d/lid.conf
[Login]
HandleLidSwitch=ignore
HandleLidSwitchDocked=ignore
HandleLidSwitchExternalPower=ignore
```

**Why this is needed**: When the laptop lid closes, Linux (via `systemd-logind`) receives an **ACPI lid event** from the firmware. By default, logind suspends the system to RAM (S3 sleep state). This would kill all your Docker containers, Sunshine, and network connectivity.

**ACPI Power States:**

| State | Name | Description |
|---|---|---|
| S0 | Working | Normal operation |
| S1 | Sleep | CPU stopped, RAM powered, resume in <1s |
| S2 | Standby | CPU/cache powered off, RAM powered |
| S3 | Suspend to RAM | Only RAM powered (~1W), resume in ~3s |
| S4 | Hibernate | RAM written to disk, power off, resume in ~15s |
| S5 | Soft Off | Powered off, but PSU energized (for WoL) |

With `HandleLidSwitch=ignore`, closing the lid does nothing—the system stays in S0.

**Wake-on-LAN (WoL)**: If you completely power off the laptop, you can wake it remotely by sending a "Magic Packet" (broadcast UDP with the MAC address repeated 16 times) to the LAN. Requires WoL to be enabled in BIOS and `ethtool -s enp2s0 wol g`. Not applicable for Wi-Fi (most Wi-Fi doesn't support WoL).

**Keeping the screen off**: To save power while the lid is closed but system is running:
```bash
# Turn off display via DRM
echo 0 | sudo tee /sys/class/drm/card2-eDP-1/enabled  
# Or use hyprctl
hyprctl dispatch dpms off  # In your Hyprland setup
```

---

<a name="section-9"></a>
# Section 9: Security Model & Attack Surface

## Principle of Least Privilege in Docker

**PUID/PGID in your `.env`:**
```
PUID=1000
PGID=1000
```

By default, Docker containers run as root (UID 0) inside the container. If a container is compromised, the attacker has root inside—and if a container escape vulnerability exists, they have root on the host too.

**Your Jellyfin config:**
```yaml
user: "${PUID}:${PGID}"  # Run as UID 1000 (ghostblaster), not root
```

This means the Jellyfin process inside the container runs as UID 1000. Even if it's compromised, the attacker has user-level privileges at most (inside the container's namespace).

**Why `group_add: ["989", "985"]`?**

UID 1000 doesn't belong to `render` (989) or `video` (985) groups by default inside the container. The container has its own `/etc/group` (from the image). `group_add` adds these GIDs to the process's supplementary groups, allowing access to `/dev/dri/renderD129` (render group) and `/dev/dri/card2` (video group).

```bash
# Inside the Jellyfin container, process's effective groups would be:
# UID=1000 GID=1000 Groups=1000,989(render),985(video)
```

**Linux DAC (Discretionary Access Control)**: The traditional Unix permission model.
- Every file has an owner (UID) and group (GID).
- Permissions: owner rwx, group rwx, others rwx.
- A process can access a file if it matches owner (and has owner permissions), matches group (and has group permissions), or falls under "others."

`/dev/dri/renderD129` is `crw-rw-rw-` (226, 129):
```
c = character device
rw- = owner (root) can read/write
rw- = group (render) can read/write
rw- = others can read/write  ← Actually world-readable!
```

So `renderD129` doesn't even need the group. But `card2` is `crw-rw----+` (video group required, no other access).

**Rootless containers**: A step further—the Docker daemon itself runs without root. Containers run as unprivileged users even in the daemon process. Docker's rootless mode uses user namespaces to map container root (UID 0) to a high UID (e.g., 100000) on the host. A container escape would give the attacker UID 100000 on the host—harmless.

---

## Network Attack Surface: What's Exposed and to Whom

**Ports exposed on all interfaces (0.0.0.0) in your setup:**

| Port | Protocol | Service | Exposure |
|---|---|---|---|
| 53 | TCP+UDP | AdGuard Home (DNS) | LAN (if no port forward, not internet) |
| 80 | TCP | NPM (HTTP redirect) | LAN |
| 443 | TCP | NPM (HTTPS) | LAN |
| 81 | TCP | NPM admin UI | LAN — should restrict! |
| 3000 | TCP | AdGuard setup portal | LAN — close after setup |
| 8080 | TCP | AdGuard dashboard | LAN |
| 8096 | TCP | Jellyfin | LAN |
| 5001 | TCP | Dockge | LAN — sensitive! |
| 3001 | TCP | Uptime Kuma | LAN |
| 2283 | TCP | Immich | LAN |
| 8085 | TCP | File Browser | LAN |
| 13378 | TCP | Audiobookshelf | LAN |
| 47990 | TCP | Sunshine web UI | LAN |
| 47998-48010 | UDP | Sunshine streaming | LAN |

**None of these are internet-exposed** (assuming no port forwarding on your router). That's the right stance.

**Sensitive ports to be extra careful with:**
- **Port 5001 (Dockge)**: Has access to `docker.sock`. Whoever controls Dockge controls all containers. **Never expose this to untrusted networks.** If you access it through NPM, put it behind authentication.
- **Port 81 (NPM admin)**: Controls all your HTTPS certificates and routing. Same concern.
- **Port 8080 (AdGuard)**: Controls DNS for your entire network.

**Why Tailscale is safer than port forwarding:**

Traditional approach (Port forwarding):
```
Router: "all traffic on port 443 → 192.168.1.96"
Internet → (anyone) → 203.0.113.45:443 → your NPM
  Risk: Brute force, zero-days in NPM, TLS configuration errors
```

Tailscale approach:
```
No port forwarding. 
Remote access only via Tailscale tunnel.
  • Mutual authentication: WireGuard keys (your device + your laptop both must have keys)
  • No public IP exposure: laptop is not reachable without Tailscale credentials
  • Even if your laptop's services have vulnerabilities, attackers can't reach them
```

---

## SSH Security: TV Termux SSH Server

Your TV runs an SSH server in Termux on port 8022. Your laptop connects:
```bash
ssh -p 8022 192.168.1.50  # In tv-tools.sh
```

**Current setup uses password auth** (you ran `passwd` in the Termux setup). This is convenient but less secure.

**Better: Key-based auth:**
```bash
# On laptop:
ssh-keygen -t ed25519 -f ~/.ssh/tv_termux -C "homelab-tv"

# Copy public key to TV Termux:
ssh-copy-id -p 8022 -i ~/.ssh/tv_termux.pub 192.168.1.50

# Or manually:
cat ~/.ssh/tv_termux.pub | ssh -p 8022 192.168.1.50 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"

# Add to ~/.ssh/config on laptop:
Host tv-termux
  Hostname 192.168.1.50
  Port 8022
  User user
  IdentityFile ~/.ssh/tv_termux
  IdentitiesOnly yes
```

**After setting up key auth, disable password auth** in Termux's sshd:
```bash
# In Termux on TV:
echo "PasswordAuthentication no" >> $PREFIX/etc/ssh/sshd_config
# Restart sshd
pkill sshd; sshd -p 8022
```

**SSH security hardening principles:**
- **Only key-based auth**: Passwords can be brute-forced; Ed25519 keys cannot (2^255 search space).
- **No root login**: `PermitRootLogin no` (default in modern sshd).
- **Fail2ban**: Automatically blocks IPs with repeated failed attempts. For a LAN-only SSH server, less critical.
- **Non-standard port** (your 8022): Reduces automated scanning noise. Security-through-obscurity, but it works for noise reduction.
- **Known_hosts verification**: `ssh` warns if a host key changes (possible MITM). Don't disable `StrictHostKeyChecking`.

---

<a name="section-10"></a>
# Section 10: Brief Primer on Distributed Computing

## What Distributed Computing Actually Is

A **distributed system** is a collection of independent computers that appear to users as a single coherent system. The defining characteristic: components communicate only by passing messages (over a network), not by sharing memory directly.

**Shared-memory vs Shared-nothing:**

| Architecture | Example | How it scales |
|---|---|---|
| Shared-memory (SMP) | Your i5-1035G1 with 8 logical CPUs | Add cores/CPUs to same box |
| Shared-nothing (distributed) | Cassandra, Kafka clusters | Add more machines |
| Shared-disk | Traditional SAN, Oracle RAC | Multiple computers, one storage |

Your homelab is currently a **single-node shared-memory** system (one laptop, one CPU, shared RAM). All Docker containers share the same CPU, same RAM, same network stack. That's not distributed—it's multiplexed.

---

## The CAP Theorem

**CAP Theorem** (Brewer, 2000): A distributed system can provide at most **two** of the following three guarantees simultaneously:

```
         Consistency
              /\
             /  \
            /    \
           /      \
          /  CA    \
         /  (single \
        /    node)   \
       ─────────────────
      /                 \
  CP /                   \ AP
    /                     \
   /      PARTITION        \
  /     (network split)     \
Availability ─────────────────
```

- **Consistency (C)**: Every read returns the most recent write (or an error). All nodes see the same data at the same time.
- **Availability (A)**: Every request gets a response (not an error), though it might not be the latest data.
- **Partition Tolerance (P)**: The system continues operating even when network partitions (splits) occur between nodes.

**Why you can only pick 2**: In a distributed system, network partitions *will* happen (cables fail, switches reboot). When a partition occurs, you must choose between:
- **CP**: Stop serving requests from the disconnected partition (sacrifice availability to maintain consistency).
- **AP**: Keep serving requests but potentially serve stale data (sacrifice consistency to maintain availability).

**Real-world examples:**

| System | Choice | Behavior during partition |
|---|---|---|
| PostgreSQL (single-node) | CA (no partitions) | N/A—single machine, always consistent |
| Cassandra | AP | Continues serving, may return stale data |
| HBase | CP | Stops serving if can't reach quorum |
| MongoDB (new) | CP | Refuses writes without primary |
| DNS (caching) | AP | Returns cached (possibly stale) answers |

---

## How Your Homelab Lays the Groundwork

**Docker networking = proto-cluster mental model:**

You already think in services, not servers. Immich doesn't run "on your laptop"—it runs as a set of cooperating services: `immich_server`, `immich_machine_learning`, `immich_redis`, `immich_postgres`. These communicate over a named network. This is *exactly* the mental model for Kubernetes/Nomad—you'd just spread those services across multiple physical machines.

```
Your current setup (single node):
  homelab-net: [npm] [adguard] [jellyfin] [immich_server] [immich_postgres] [redis]
  All on 192.168.1.96

Future distributed setup (multi-node):
  Node 1 (192.168.1.96, laptop): npm, adguard, jellyfin (GPU)
  Node 2 (192.168.1.97, new NUC): immich_server, immich_ml
  Node 3 (192.168.1.98, old PC): immich_postgres, redis

  Overlay network (like homelab-net but spanning machines):
    Kubernetes CNI plugin (Flannel/Calico) or Docker Swarm overlay network
    Creates a virtual network: containers on different hosts communicate
    as if they're on the same local network
```

**Service discovery**: In your current setup, container names resolve via Docker DNS (`127.0.0.11`). In Kubernetes, this is `CoreDNS`—the same concept, scaled up. `immich-postgres.default.svc.cluster.local` resolves to the PostgreSQL service, wherever it's running.

**What horizontal scaling means:**

**Vertical scaling**: Make the existing machine bigger (more RAM, faster CPU). Limited by physics (one machine can only be so big) and expensive.

**Horizontal scaling**: Add more machines. Stateless services (web servers, API handlers) scale trivially—add more containers, put a load balancer in front. Stateful services (databases) are hard—data must be partitioned (sharded) or replicated across nodes.

Your Immich server is *horizontally scalable*: you could run 3 `immich_server` containers behind a load balancer. Requests from multiple users are distributed. The database (`immich_postgres`) is the scaling bottleneck.

**Kubernetes mental model** (for your future):

```
kubectl apply -f jellyfin-deployment.yaml
# "I want 1 instance of Jellyfin with GPU access"

Kubernetes scheduler:
  "Which node has a GPU? Node 1 (your laptop equivalent) has one"
  → Schedule Jellyfin on Node 1
  → Create Pod (analogous to docker run)
  → Allocate IP from cluster subnet
  → Register in CoreDNS
```

Everything you know from Docker Compose (services, networks, volumes, environment variables) translates directly to Kubernetes manifests. The concepts are the same; the scope is larger.

---

## The Right Mental Model Going Forward

Your homelab is not just a media server. It's a **systems thinking laboratory**. Every problem you solve here—"why can't the Immich container find the Postgres container?"—maps to a problem distributed systems engineers solve at scale.

```
Homelab problem → Distributed systems equivalent
─────────────────────────────────────────────────────────────────────
Container DNS resolution          →  Service discovery (Consul, CoreDNS)
Docker networks                   →  Overlay networks, VPC subnets
Port publishing (DNAT)            →  Load balancer ingress, NodePort
NPM reverse proxy                 →  Kubernetes Ingress controller
Tailscale subnet router           →  VPN Gateway, transit VPC
AdGuard DNS sinkhole              →  Internal DNS resolver, split horizon
NTFS locking issues               →  Distributed storage semantics (NFS, Ceph)
systemd service dependencies      →  Kubernetes init containers, readiness probes
Docker cgroups limits             →  Kubernetes resource requests/limits
Immich ML memory: 1500M           →  Kubernetes LimitRange, resource quotas
Jellyfin QuickSync device access  →  Kubernetes device plugins (GPU operator)
```

You're already thinking in the right abstractions. The jump from Docker Compose to Kubernetes or Nomad is mostly syntactic—the architectural thinking is identical.

---

## Appendix: Quick Reference — Your Homelab at a Glance

```
Host: 192.168.1.96 (wlp3s0, Wi-Fi)
      172.17.0.1   (docker0, default bridge)
      [homelab-net bridge, dynamic subnet]

Services (LAN access):
  http://192.168.1.96:8080  → AdGuard Home dashboard
  http://192.168.1.96:81    → NPM admin (CHANGE DEFAULT PASSWORD!)
  http://192.168.1.96:8096  → Jellyfin
  http://192.168.1.96:5001  → Dockge
  http://192.168.1.96:3001  → Uptime Kuma
  http://192.168.1.96:2283  → Immich
  http://192.168.1.96:8085  → File Browser
  http://192.168.1.96:13378 → Audiobookshelf
  https://localhost:47990    → Sunshine WebUI (local only)

Storage:
  Fast (NVMe, /dev/nvme0n1): / → /home/ghostblaster, databases, configs
  Bulk (HDD, /dev/sda2 NTFS): /mnt/storage → movies, photos, media

GPU:
  Intel Iris Plus G1 (Ice Lake Gen 11)
  /dev/dri/renderD129 → VA-API H.264/H.265 encode/decode
  /dev/dri/card2      → KMS display output

Key commands:
  ip addr show          # Network interfaces
  ip neigh show         # ARP table
  ip route show         # Routing table
  ss -tuln              # Open ports
  docker network ls     # Docker networks
  docker network inspect homelab-net  # Network details
  iptables -t nat -L -n # NAT rules
  nft list ruleset      # nftables rules
  journalctl -fu docker # Docker daemon logs
  systemctl --user status sunshine  # Sunshine service
  vainfo                # VA-API capabilities (run inside Jellyfin or on host with libva-intel-driver)
```

---

*This document reflects your actual running setup as of October 2026. The IP addresses, device paths, container names, and configuration values are drawn directly from your live system. As you expand the homelab (VLANs, additional nodes, Kubernetes), the concepts here remain the foundation—everything builds on these primitives.*
