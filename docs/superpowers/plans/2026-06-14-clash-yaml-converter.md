# Clash YAML Manual Converter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a manual Clash YAML conversion and preview page that imports selected compatible nodes into dae or daed.

**Architecture:** A pure browser-compatible converter module parses supported Clash proxy objects into share links. The LuCI page coordinates input, preview, duplicate detection, and backend-specific import, while a constrained router helper fetches URL input with a Clash-compatible User-Agent.

**Tech Stack:** LuCI JavaScript, js-yaml browser bundle, BusyBox shell/uclient-fetch, UCI, daed GraphQL

---

### Task 1: Converter Core

**Files:**
- Create: `luci-app-daede/htdocs/luci-static/resources/view/daede/clash-converter.js`
- Test locally: `/tmp/daede-converter-test.js`

- [ ] Write failing Node tests for SS, VMess, VLESS, Trojan, TUIC, Hysteria2, AnyTLS, malformed nodes, unsupported protocols, and normalized duplicate keys.
- [ ] Run `node /tmp/daede-converter-test.js` and verify failure because the converter module does not exist.
- [ ] Implement pure conversion functions without LuCI or DOM dependencies.
- [ ] Run `node /tmp/daede-converter-test.js` and verify all cases pass.

### Task 2: YAML Parser And Fetch Helper

**Files:**
- Create: `luci-app-daede/htdocs/luci-static/resources/view/daede/vendor/js-yaml.min.js`
- Create: `luci-app-daede/root/usr/share/luci-app-daede/fetch-clash-yaml.sh`
- Modify: `luci-app-daede/root/usr/share/rpcd/acl.d/luci-app-daede.json`
- Test locally: `/tmp/daede-fetch-test.sh`

- [ ] Write failing helper tests for invalid schemes and valid HTTP retrieval.
- [ ] Run the helper tests and verify failure because the helper does not exist.
- [ ] Add the MIT YAML browser bundle and implement the constrained fetch helper.
- [ ] Add the exact ACL execution permission for the helper.
- [ ] Run helper tests and verify scheme and retrieval behavior.

### Task 3: Standalone LuCI Converter Page

**Files:**
- Create: `luci-app-daede/htdocs/luci-static/resources/view/daede/converter.js`
- Modify: `luci-app-daede/root/usr/share/luci/menu.d/luci-app-daede.json`
- Modify: `luci-app-daede/htdocs/luci-static/resources/view/daede/styles.js`

- [ ] Add the standalone menu entry and page skeleton.
- [ ] Implement URL and pasted-YAML input with mutually exclusive source handling.
- [ ] Parse top-level `proxies`, convert every node, and render compatible, duplicate, and unsupported statuses.
- [ ] Default-select compatible non-duplicate nodes and add filtering/select-all controls.
- [ ] Keep all input state in memory and clear sensitive daed state after import.

### Task 4: dae Import

**Files:**
- Modify: `luci-app-daede/htdocs/luci-static/resources/view/daede/converter.js`

- [ ] Add existing dae UCI link lookup and exact-link duplicate classification.
- [ ] Add selected links as UCI `node` sections with generated unique tags.
- [ ] Commit/apply UCI and invoke `gen-dae-config.sh generate`.
- [ ] Report added, duplicate, and failed counts without starting dae implicitly.

### Task 5: daed Import

**Files:**
- Modify: `luci-app-daede/htdocs/luci-static/resources/view/daede/converter.js`

- [ ] Add an import-time username/password dialog.
- [ ] Obtain a daed bearer token through GraphQL and keep it only in a local variable.
- [ ] Query existing manual nodes, mark exact duplicates, and call `importNodes(rollbackError:false)`.
- [ ] Clear credentials/token and report per-item import results.

### Task 6: Translation, Packaging, And Device Verification

**Files:**
- Modify: `luci-app-daede/po/templates/daede.pot`
- Modify: `luci-app-daede/po/zh-cn/daede.po`
- Modify: `luci-app-daede/po/zh_Hans/daede.po`
- Modify: `luci-app-daede/Makefile`

- [ ] Add page strings and bump package release.
- [ ] Run JavaScript syntax checks, converter tests, JSON validation, and shell syntax checks.
- [ ] Deploy changed files to 252 and clear LuCI caches.
- [ ] Verify URL conversion, pasted YAML, unsupported-node reporting, dae import plus `dae validate`, and daed authenticated import.
- [ ] Verify desktop and phone-width screenshots through the LuCI Playwright UI loop.

