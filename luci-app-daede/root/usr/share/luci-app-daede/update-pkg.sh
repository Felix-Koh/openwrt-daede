#!/bin/sh
# update-pkg.sh <dae|daed|luci-app-daede>
# Refresh package indexes and upgrade the named package via apk (25.12+) or
# opkg (24.10). Forks the work to background so the LuCI RPC call returns
# immediately; the result is streamed to /tmp/luci-app-daede.pkg.<name>.log.

PKG="$1"
LIB="/usr/share/luci-app-daede/release-lib.sh"
case "$PKG" in
	dae|daed|luci-app-daede) ;;
	*)
		echo "usage: $0 <dae|daed|luci-app-daede>" >&2
		exit 64
		;;
esac

[ -r "$LIB" ] || {
	echo "missing helper: $LIB" >&2
	exit 1
}

# run from a /tmp copy so upgrading luci-app-daede (which replaces this script)
# can't corrupt the in-flight upgrade
case "$0" in
	/tmp/.daede-upd-*) ;;
	*)
		_self="/tmp/.daede-upd-$$"
		cp "$0" "$_self" 2>/dev/null && exec sh "$_self" "$@"
		;;
esac

LOCK="/tmp/luci-app-daede.pkg-${PKG}.lock"
LOG="/tmp/luci-app-daede.pkg-${PKG}.log"

if [ -f "$LOCK" ]; then
	mtime=$(date -r "$LOCK" +%s 2>/dev/null || echo 0)
	age=$(( $(date +%s) - mtime ))
	if [ "$age" -lt 300 ]; then
		echo "${PKG} update already in progress (PID $(cat "$LOCK" 2>/dev/null), age ${age}s)" >&2
		exit 75
	fi
	rm -f "$LOCK"
fi

if ! ( set -C; echo "$$" >"$LOCK" ) 2>/dev/null; then
	echo "${PKG} update already in progress" >&2
	exit 75
fi

(
	exec >"$LOG" 2>&1
	trap 'rm -f "$LOCK"; [ "${0#/tmp/.daede-upd-}" != "$0" ] && rm -f "$0"' EXIT INT TERM
	. "$LIB"

	echo "$(date '+%F %T') begin upgrade: $PKG"

	PM="$(detect_manager || true)"
	if [ -z "$PM" ]; then
		echo "no package manager found"
		exit 3
	fi

	ARCH="$(detect_arch "$PM" 2>/dev/null || true)"
	if [ -z "$ARCH" ]; then
		echo "cannot detect architecture"
		exit 4
	fi

	info="$(resolve_release_asset "$PKG" "$PM" "$ARCH" 2>/dev/null || true)"
	TARGET_VER="$(printf '%s' "$info" | awk -F '\t' 'NR==1{print $1}')"
	TARGET_URL="$(printf '%s' "$info" | awk -F '\t' 'NR==1{print $2}')"
	RESOLVED_ARCH="$(printf '%s' "$info" | awk -F '\t' 'NR==1{print $3}')"
	CUR_VER="$(installed_version "$PM" "$PKG" 2>/dev/null || true)"
	EXT="$(asset_ext "$PM")"
	OUT="/tmp/luci-app-daede.${PKG}.${EXT}"

	if [ -z "$TARGET_VER" ] || [ -z "$TARGET_URL" ]; then
		echo "cannot resolve latest GitHub release asset for $PKG ($ARCH)"
		exit 5
	fi

	if [ -n "$CUR_VER" ] && version_ge "$CUR_VER" "$TARGET_VER"; then
		echo "result: installed=${CUR_VER}, latest=${TARGET_VER}"
		rc=0
	else
		echo "resolved release asset: $(basename "$TARGET_URL")"
		[ -n "$CUR_VER" ] && echo "installed version: $CUR_VER"
		echo "target version: $TARGET_VER"
		echo "downloading from GitHub release..."
		download_file "$(download_url "$TARGET_URL")" "$OUT" 2>&1 || {
			echo "download failed: $TARGET_URL"
			exit 6
		}

		if [ "$PM" = "apk" ]; then
			# shared apk lock with any other package operation
			(
				flock 9
				[ -n "$RESOLVED_ARCH" ] && [ "$RESOLVED_ARCH" != "$ARCH" ] && allow_apk_arch "$RESOLVED_ARCH"
				echo "--- apk add --allow-untrusted $(basename "$OUT") ---"
				apk add --allow-untrusted "$OUT" 2>&1
			) 9>/tmp/luci-app-daede.apk.lock
		else
			echo "--- opkg install $(basename "$OUT") ---"
			opkg install "$OUT" 2>&1
		fi

		NEW_VER="$(installed_version "$PM" "$PKG" 2>/dev/null || true)"
		if [ -n "$NEW_VER" ] && version_ge "$NEW_VER" "$TARGET_VER"; then
			echo "result: installed=${NEW_VER}, latest=${TARGET_VER}"
			rc=0
		else
			echo "result: install did not reach target version (installed=${NEW_VER:-unknown}, latest=${TARGET_VER})"
			rc=1
		fi
	fi

	if [ "$rc" = 0 ]; then echo "$(date '+%F %T') ✓ 完成"; else echo "$(date '+%F %T') ✗ 失败 (rc=$rc)"; fi

	# luci-app-daede upgrade replaces ACL JSON — reload rpcd so changes apply.
	if [ "$PKG" = "luci-app-daede" ] && [ "$rc" = "0" ]; then
		echo "reloading rpcd to pick up new ACL"
		/etc/init.d/rpcd reload 2>&1
	fi
) </dev/null >/dev/null 2>&1 &

echo "started in background, see $LOG"
exit 0
