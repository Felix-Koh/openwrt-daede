#!/bin/sh

LuciAppRepo="${DAEDE_LUCI_REPO:-Felix-Koh/openwrt-daede}"
CoreRepo="${DAEDE_CORE_REPO:-kenzok8/openwrt-daede}"
GITHUB_PROXY_PREFIX="${GITHUB_PROXY_PREFIX:-https://ghfast.top/}"
RELEASE_CACHE_DIR="${DAEDE_RELEASE_CACHE_DIR:-/tmp/luci-app-daede.release}"
RELEASE_CACHE_TTL="${DAEDE_RELEASE_CACHE_TTL:-900}"

fetch_text() {
	url="$1"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$url" 2>/dev/null
		return $?
	fi
	wget -qO- "$url" 2>/dev/null
}

download_file() {
	url="$1"
	out="$2"
	if command -v curl >/dev/null 2>&1; then
		curl -fL "$url" -o "$out"
		return $?
	fi
	wget -O "$out" "$url"
}

download_url() {
	url="$1"
	case "$url" in
		https://github.com/*)
			printf '%s%s\n' "$GITHUB_PROXY_PREFIX" "$url"
			;;
		*)
			printf '%s\n' "$url"
			;;
	esac
}

detect_manager() {
	if command -v opkg >/dev/null 2>&1; then
		echo opkg
		return 0
	fi
	if command -v apk >/dev/null 2>&1; then
		echo apk
		return 0
	fi
	return 1
}

detect_arch() {
	pm="$1"
	if [ "$pm" = "opkg" ]; then
		opkg print-architecture | awk '/^arch / {print $2}' | tail -n 1
		return
	fi

	distrib_arch="$(sed -n "s/^DISTRIB_ARCH=['\"]\([^'\"]*\)['\"].*/\1/p" /etc/openwrt_release 2>/dev/null | head -n 1)"
	if [ -n "$distrib_arch" ]; then
		printf '%s\n' "$distrib_arch"
	else
		apk --print-arch
	fi
}

fallback_arch() {
	case "$1" in
		aarch64_generic) return 1 ;;
		aarch64_*) printf 'aarch64_generic\n' ;;
		*) return 1 ;;
	esac
}

asset_ext() {
	case "$1" in
		apk) echo apk ;;
		*) echo ipk ;;
	esac
}

installed_version() {
	pm="$1"
	pkg="$2"

	if [ "$pm" = "apk" ]; then
		if apk info -e "$pkg" >/dev/null 2>&1; then
			apk list -I "$pkg" 2>/dev/null | awk -v p="$pkg" '
				$1 ~ "^" p "-" {
					sub("^" p "-", "", $1);
					print $1;
					exit
				}
			'
		fi
	else
		opkg status "$pkg" 2>/dev/null | awk -F': ' '$1=="Version"{print $2; exit}'
	fi
}

version_ge() {
	a="$1"
	b="$2"
	[ -n "$a" ] && [ -n "$b" ] || return 1
	[ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -n 1)" = "$a" ]
}

release_payload() {
	repo="$1"
	api_url="$(release_api_url "$repo")"
	cache_file="$(release_cache_file "$repo")"
	now="$(date +%s)"
	if [ -s "$cache_file" ]; then
		mtime="$(date -r "$cache_file" +%s 2>/dev/null || echo 0)"
		if [ "$((now - mtime))" -lt "$RELEASE_CACHE_TTL" ]; then
			cat "$cache_file"
			return 0
		fi
	fi

	mkdir -p "$RELEASE_CACHE_DIR"
	tmp="${cache_file}.$$"
	for url in "$api_url" "${GITHUB_PROXY_PREFIX}${api_url}"; do
		case "$url" in
			https://ghfast.top/https://api.github.com/*|https://api.github.com/*) ;;
			*) continue ;;
		esac
		payload="$(fetch_text "$url" || true)"
		if printf '%s' "$payload" | grep -q '"browser_download_url"'; then
			printf '%s\n' "$payload" >"$tmp"
			mv "$tmp" "$cache_file"
			cat "$cache_file"
			return 0
		fi
	done

	rm -f "$tmp"
	if [ -s "$cache_file" ]; then
		cat "$cache_file"
		return 0
	fi
	return 1
}

release_urls() {
	repo="$1"
	release_payload "$repo" | sed -n 's/.*"browser_download_url":[[:space:]]*"\([^"]*\)".*/\1/p'
}

resolve_release_asset() {
	pkg="$1"
	pm="$2"
	arch="$3"
	repo="$(repo_for_pkg "$pkg" 2>/dev/null || true)"
	ext="$(asset_ext "$pm")"
	[ -n "$repo" ] || return 1
	urls="$(release_urls "$repo")"
	[ -n "$urls" ] || return 1

	for resolved_arch in "$arch" $(fallback_arch "$arch" || true); do
		if [ "$pkg" = "luci-app-daede" ]; then
			if [ "$ext" = "apk" ]; then
				url="$(printf '%s\n' "$urls" | grep -E "/luci-app-daede-[^/]*-${resolved_arch}\.apk$" | head -n 1)"
			else
				url="$(printf '%s\n' "$urls" | grep -E '/luci-app-daede_[^/]*_all\.ipk$' | head -n 1)"
			fi
		else
			if [ "$ext" = "apk" ]; then
				url="$(printf '%s\n' "$urls" | grep -E "/${pkg}-[^/]*-${resolved_arch}\.apk$" | head -n 1)"
			else
				url="$(printf '%s\n' "$urls" | grep -E "/${pkg}_[^/]*_${resolved_arch}\.ipk$" | head -n 1)"
			fi
		fi

		[ -n "$url" ] || continue

		base="$(basename "$url")"
		if [ "$ext" = "apk" ]; then
			file="${base%.apk}"
			version="${file#${pkg}-}"
			version="${version%-${resolved_arch}}"
		else
			file="${base%.ipk}"
			version="${file#${pkg}_}"
			if [ "$pkg" = "luci-app-daede" ]; then
				version="${version%_all}"
			else
				version="${version%_${resolved_arch}}"
			fi
		fi

		printf '%s\t%s\t%s\n' "$version" "$url" "$resolved_arch"
		return 0
	done

	return 1
}

allow_apk_arch() {
	arch="$1"
	[ -n "$arch" ] || return 0
	if ! grep -qxF "$arch" /etc/apk/arch 2>/dev/null; then
		echo "$arch" >> /etc/apk/arch
	fi
}
repo_for_pkg() {
	case "$1" in
		luci-app-daede) printf '%s\n' "$LuciAppRepo" ;;
		dae|daed) printf '%s\n' "$CoreRepo" ;;
		*) return 1 ;;
	esac
}

release_api_url() {
	repo="$1"
	printf 'https://api.github.com/repos/%s/releases/latest\n' "$repo"
}

release_cache_file() {
	repo="$1"
	key="$(printf '%s' "$repo" | tr '/:' '__')"
	printf '%s/%s.json\n' "$RELEASE_CACHE_DIR" "$key"
}
