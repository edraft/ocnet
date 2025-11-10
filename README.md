# OCNET PROTOCOL DOCUMENTATION

Transport: OpenComputers native modem messages  
Port: configurable (default 42)

## 1. OVERVIEW

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

## 2. Protocol

> GW_DISC

Gateway discovery.  
Sent by clients to detect available OCSense gateways on the local network segment.  
A gateway receiving this message replies with `GW_HERE`.

Format:
GW_DISC

---

> GW_HERE

Gateway announcement / discovery response.  
Sent by an OCSense gateway in reply to `GW_DISC`, to announce its presence and address to clients.

Format:
GW_HERE <gateway_address>

---

> CL_DISC

Client discovery.  
Sent by a gateway (or OCSense instance) to request all clients on the same segment to re-register.  
This is typically used during startup, configuration reloads, or after network changes.

Format:
CL_DISC

---

> REGISTER

Client registration message.  
Sent by clients to register their hostname and address at the OCSense gateway.  
The registration may include an optional `public` flag to mark the host as externally visible for other segments.

Format:
REGISTER <hostname> [address] [public]

Example:
REGISTER srv1.local 1234abcd true

---

> RESOLVE

Hostname resolution request.  
Sent by clients or other OCSense instances to resolve a FQDN (fully qualified domain name) to its network address.  
If the name belongs to another segment, the request may be forwarded through multiple Senses.

Format:
RESOLVE <fqdn> [requesting_segment]

Responses:

- RESOLVE_OK <fqdn> <address>
- RESOLVE_FAIL <fqdn> <message>

---

> LIST

Service and client listing.  
Requests all visible names and addresses from an OCSense instance.  
Each sense returns only entries that are visible for the requesting segment (controlled by the `public` flag).  
Used to enumerate available hosts across the network.

Format:
LIST [requesting_segment]

Responses:

- LIST_OK <name:addr,name:addr,...>

---

> SENSE_DISC

Sense discovery.  
Used by OCSense instances to find each other and establish inter-segment connectivity.  
When a Sense receives this message, it responds with `SENSE_HI`.

Format:
SENSE_DISC <segment> <sender_address>

---

> SENSE_HI

Sense handshake.  
Response to `SENSE_DISC`, used to confirm presence and exchange segment identifiers.  
Both sides register each other in their internal `sense_registry`.

Format:
SENSE_HI <segment> <sender_address>

---

> ROUTE

Packet forwarding between segments.  
Carries arbitrary payload between clients across different Senses.  
Each Sense decrements TTL (time-to-live) and forwards the packet until it reaches the destination host or TTL expires.

Format:
ROUTE <src_fqdn> <dest_fqdn> <port> <ttl> [payload...]

---

> TRACE

Route tracing / diagnostic message.  
Used to trace the path of a hostname across segments.  
Each Sense appends its segment and address to the trace chain, and forwards it until the destination is reached.

Format:
TRACE <fqdn> [trace_chain] [requesting_segment]

Responses:

- TRACE_OK <fqdn> <trace_chain>
- TRACE_FAIL <fqdn> <message> <trace_chain>

---

> PING

Simple reachability check.  
Used between clients or between client and gateway to test connectivity.  
A recipient replies

## 3. Gateway (OCSense)

## 4. Client

> useModem(modem)

Selects the modem component to be used by the client library.  
This must be called before any network communication functions.  
It binds the library to a specific physical or virtual modem for sending and receiving packets.

Format:
useModem(<modem_component>)

Example:
useModem(component.modem)

---

> getLocalAddress()

Returns the local modem’s network address as known to the system.  
This address uniquely identifies the client within its current network segment.

Format:
getLocalAddress()

Return:
<string> – the local modem address

Example:
local addr = getLocalAddress()

---

> reset()

Resets the internal state of the client library.  
Closes all open ports, clears listener registrations, and stops active event handlers.  
Useful when reinitializing the network connection or changing modems.

Format:
reset()

---

> send(fqdn, port, ...)

Sends a message to a remote host identified by its fully qualified domain name (FQDN).  
The library internally resolves the FQDN through OCSense using the `RESOLVE` protocol and transmits the payload to the resolved address.

Format:
send(<fqdn>, <port>, <payload...>)

Arguments:

- fqdn: target host name (e.g. "srv1.local")
- port: destination port number
- payload...: one or more Lua values or strings to send

Returns:
boolean success, string|nil error_message

Example:
send("srv1.local", 123, "PING")

---

> listen(port, handler)

Registers a handler function for incoming messages on the given port.  
When a message arrives, the handler is called with the same arguments as received from the modem event:
`handler(from, port, ...)`.

Format:
listen(<port>, <function>)

Arguments:

- port: numeric port number to listen on
- handler: function(from, port, ...)

Example:
listen(42, function(from, port, msg)
print("message from", from, ":", msg)
end)

---

> unlisten(port)

Removes a previously registered listener for the specified port.  
After calling this, messages on that port will be ignored by the library.

Format:
unlisten(<port>)

Arguments:

- port: numeric port number to stop listening on

Example:
unlisten(42)
