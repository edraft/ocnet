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

> GW_HERE

> CL_DISC

> REGISTER

> RESOLVE

> LIST

> SENSE_DISC

> SENSE_HI

> ROUTE

> TRACE

> PING

## 3. Gateway (OCSense)

## 4. Client

> useModem(modem)

> getLocalAddress()

> reset()

> send(fqdn, port, ...)

> listen(port, handler)

> unlisten(port)
