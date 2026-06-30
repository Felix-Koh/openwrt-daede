#!/bin/sh
# pkg-info.sh <package>
# Prints "<installed>\t<latest>" for the named package, where either field is
# empty when unknown. Used by the Updates view to decide whether to enable
# the [Upgrade] button.

PKG="$1"
LIB="/usr/share/luci-app-daede/release-lib.sh"

case "$PKG" in
	dae|daed|luci-app-daede) ;;
	*) echo "" ; exit 64 ;;
esac

[ -r "$LIB" ] || {
	printf '\t\n'
	exit 1
}

. "$LIB"

installed=""
latest=""

PM="$(detect_manager || true)"
ARCH="$(detect_arch "$PM" 2>/dev/null || true)"

if [ -n "$PM" ]; then
	installed="$(installed_version "$PM" "$PKG" 2>/dev/null || true)"
	if [ -n "$ARCH" ]; then
		latest="$(resolve_release_asset "$PKG" "$PM" "$ARCH" 2>/dev/null | awk -F '\t' 'NR==1{print $1}')"
	fi
fi

printf '%s\t%s\n' "$installed" "$latest"
