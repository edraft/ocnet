# OCNET PROTOCOL DOCUMENTATION

Version: 1.0  
Transport: OpenComputers native modem messages  
Encoding: plain text, UTF-8  
Port: configurable (default 42)

1. OVERVIEW

---

OCNet is a simple name-based communication and discovery protocol.
It provides:

- automatic gateway discovery
- client registration
- name resolution (DNS-like)
- segment-based separation
- simple keepalive and diagnostics (PING/PONG)

Each network segment has exactly one gateway (OCSense).
Clients register themselves to that gateway.
All communication is text-based and handled on the configured modem port.

2. ROLES

---

Gateway (OCSense)

- manages the registry of hostnames within its segment
- answers discovery, registration and resolve requests

Client (OCNet)

- discovers a gateway automatically
- registers its hostname and modem address
- can request name resolution

3. MESSAGE FORMAT

---

Each modem message consists of one or more space-separated words.
Example:
"REGISTER pc1 aabbccdd-1122-3344"

Messages are always sent via the OpenComputers modem component
using the configured port number (default 42).

General fields:
CMD [ARG1] [ARG2] ...

4. DISCOVERY

---

Client → Broadcast:
GW_DISC

Gateway → Unicast to client:
GW_HERE <gatewayAddress>

If the client has no configured gateway or its entry is invalid,
it broadcasts GW_DISC.
Gateways answer with GW_HERE followed by their modem address.
Clients store the first valid answer as their gateway.

5. REGISTRATION

---

Gateway → Broadcast:
CL_DISC

Client → Gateway (unicast):
REGISTER <hostname> <clientAddress>

Each client responds to CL_DISC messages from its gateway
by sending its name and modem address.
The gateway keeps a registry of all registered clients within its segment.

6. NAME RESOLUTION

---

Client → Gateway:
RESOLVE <hostname>

Gateway → Client:
RESOLVE_OK <hostname> <address>
or
RESOLVE_FAIL <hostname>

Gateways only resolve names that belong to their own segment.
Clients include the segment suffix if known (e.g. "host.segment").
If the requested segment does not match, the gateway returns RESOLVE_FAIL.

7. KEEPALIVE AND RE-REGISTRATION

---

Gateway → Broadcast:
DISC

Client → Gateway:
REGISTER <hostname> <clientAddress>

Gateways may send DISC to request all clients to re-register.
Clients receiving DISC immediately send REGISTER again.

8. DIAGNOSTICS

---

Client or Gateway → Target:
PING

Target → Sender:
PONG

Used for simple reachability checks.

9. CONFIGURATION

---

File: /etc/ocnet.conf
Format: Lua table

Example:
{
port = 42,
timeout = 3,
gateway = "aabbccdd-1122-3344",
}

- port: modem port for all messages
- timeout: default waiting time in seconds
- gateway: last known gateway modem address

10. SEGMENTS

---

Each gateway operates within a single segment.
Segment name is configured in /etc/ocsense.cfg:

segment = "local"

Clients register and resolve only hostnames within that segment.
Other segments are ignored or return RESOLVE_FAIL.

11. SUMMARY

---

Discovery:
Client -> GW_DISC (broadcast)
Gateway -> GW_HERE <address>

Registration:
Gateway -> CL_DISC (broadcast)
Client -> REGISTER <name> <addr>

Resolution:
Client -> RESOLVE <name>
Gateway -> RESOLVE_OK <name> <addr> | RESOLVE_FAIL <name>

Maintenance:
Gateway -> DISC (broadcast)
Client -> REGISTER <name> <addr>

Diagnostics:
any -> PING
response -> PONG
