# Clash YAML Manual Converter Design

## Goal

Add a standalone LuCI "Subscription Converter" page that manually converts Clash YAML nodes into share links and imports selected nodes into either dae or daed.

## Confirmed Scope

- Input supports an HTTP/HTTPS subscription URL or pasted Clash YAML.
- Conversion runs only while the LuCI page is open. There is no background refresh.
- The page previews all detected nodes before import and defaults to selecting compatible, non-duplicate nodes.
- First release supports Shadowsocks, VMess, VLESS, Trojan, TUIC, Hysteria2, and AnyTLS.
- Unsupported nodes remain visible with a reason; they are never silently discarded.
- Duplicate detection uses the normalized complete share link, not the node name.
- Subscription URLs, YAML, daed credentials, and daed tokens are not persisted.
- Only top-level Clash `proxies` are converted. Proxy groups, rules, DNS, and remote proxy-provider URLs are out of scope.

## Architecture

The browser owns YAML parsing, protocol conversion, preview state, and target selection. A small router-side fetch helper retrieves URL input using a Clash-compatible User-Agent, applies protocol, timeout, and response-size limits, and returns text to LuCI.

The converter is implemented independently under Apache-2.0-compatible project code. The GPL-3.0 `urlclash-converter` project is a behavioral reference only. A vendored MIT YAML parser is permitted.

Import paths remain backend-specific:

- dae: add selected links as UCI `node` sections, skip existing identical links, commit UCI, and run the existing config generator.
- daed: request username and password at import time, obtain an in-memory bearer token, and call GraphQL `importNodes`. Credentials and token are cleared after the request.

## Components

### Converter Core

A focused browser-compatible JavaScript module:

- accepts parsed proxy objects;
- converts each supported protocol to a dae-compatible share link;
- returns per-node success or a structured incompatibility reason;
- normalizes links for exact duplicate comparison;
- has no LuCI, DOM, UCI, or network dependencies.

### Router Fetch Helper

A shell helper invoked through LuCI ACL:

- accepts one HTTP/HTTPS URL;
- uses a ClashMeta User-Agent;
- follows redirects;
- enforces a timeout and maximum response size;
- writes only the response body to stdout;
- does not log or persist the URL or response.

### LuCI Page

The new standalone menu entry guides the user through:

1. Enter URL or paste YAML.
2. Parse and preview nodes.
3. Filter and select compatible new nodes.
4. Select an installed target backend.
5. Import and show a per-result summary.

### Backend Importers

dae and daed import behavior are isolated behind separate functions so their authentication, duplicate handling, and error reporting remain independent.

## Error Handling

- Fetch failures distinguish invalid URL, timeout, oversized response, and HTTP/network failure.
- YAML parse failures show the parser error.
- Missing or empty top-level `proxies` is an explicit error.
- One unsupported or malformed node does not block other nodes.
- Import is partial-success: successful nodes remain imported while failed and duplicate nodes are reported.
- daed authentication failures do not expose the password in messages or logs.

## Security And Resource Limits

- URL input permits only HTTP and HTTPS.
- Input and credentials remain in browser memory only.
- No `yq` dependency is added.
- Fetch response size is capped.
- RPC/file ACL additions are limited to the new helper and existing UCI/generator operations.

## Verification

- Local converter tests cover every supported protocol, malformed fields, mixed supported/unsupported YAML, and exact-link deduplication.
- Fetch helper tests cover scheme rejection, timeout/error behavior, and size rejection.
- On device 252, verify the real LuCI page, URL and pasted YAML flows, phone-width layout, dae import followed by `dae validate`, and daed authentication/import behavior.

