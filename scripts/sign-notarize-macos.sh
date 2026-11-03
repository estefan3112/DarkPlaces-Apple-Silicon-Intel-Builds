#!/bin/bash
#
# Sign Darkplaces.app with a Developer ID certificate, notarize it with Apple,
# staple the ticket to the app and zip it for download.
#
# Usage:  scripts/sign-notarize-macos.sh <arch label>     e.g. arm64 or intel
# Output: Darkplaces-<arch>.zip  (run from the repository root after bundle-macos.sh)
#
# On GitHub Actions these come from the repository secrets:
#   MACOS_CERTIFICATE      base64 of the "Developer ID Application" .p12 export
#   MACOS_CERTIFICATE_PWD  password chosen when exporting the .p12
#   APPLE_ID               Apple ID e-mail of the developer account
#   APPLE_TEAM_ID          10-character Team ID
#   APPLE_APP_PASSWORD     app-specific password from appleid.apple.com
#
# On your own Mac, instead:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE="name"  (saved earlier with: xcrun notarytool store-credentials)
#   or APPLE_ID / APPLE_TEAM_ID / APPLE_APP_PASSWORD as above

set -euo pipefail

arch="${1:?Usage: $0 <arch label>}"
app="Darkplaces.app"
zip="Darkplaces-${arch}.zip"

tmp=$(mktemp -d)
keychain=""
cleanup() {
	if [[ -n "$keychain" ]]; then security delete-keychain "$keychain" 2>/dev/null || true; fi
	rm -rf "$tmp"
}
trap cleanup EXIT


echo "STEP 1 - SIGNING IDENTITY"

if [[ -n "${MACOS_CERTIFICATE:-}" ]]; then
	# GitHub Actions: put the certificate into a temporary keychain that is deleted afterwards
	keychain="$tmp/signing.keychain-db"
	kcpass=$(openssl rand -base64 24)
	echo "$MACOS_CERTIFICATE" | base64 --decode > "$tmp/cert.p12"
	security create-keychain -p "$kcpass" "$keychain"
	security set-keychain-settings -lut 21600 "$keychain"
	security unlock-keychain -p "$kcpass" "$keychain"
	security import "$tmp/cert.p12" -k "$keychain" -P "$MACOS_CERTIFICATE_PWD" -T /usr/bin/codesign
	security set-key-partition-list -S apple-tool:,apple: -s -k "$kcpass" "$keychain" > /dev/null
	# shellcheck disable=SC2046  # the existing keychain list is meant to be split into words
	security list-keychains -d user -s "$keychain" $(security list-keychains -d user | tr -d '"')
	identity=$(security find-identity -v -p codesigning "$keychain" | awk '/Developer ID Application/ {print $2; exit}')
else
	identity="${SIGN_IDENTITY:?Set MACOS_CERTIFICATE (GitHub) or SIGN_IDENTITY (your Mac)}"
fi

if [[ -z "$identity" ]]; then
	echo "ERROR: no 'Developer ID Application' certificate found. Was the .p12 exported with its private key?"
	exit 1
fi
echo "Using identity: $identity"


echo "STEP 2 - CODE SIGNING"

sign() {
	codesign --force --timestamp --options runtime --sign "$identity" "$@"
}

# Inside out: every Mach-O file first (bundled libraries, then the program),
# then the bundle itself, which also seals Info.plist and the resources.
# The libSDL3.dylib alias is a symlink and is skipped here (find -type f).
while IFS= read -r -d '' f; do
	if file -b "$f" | grep -q "Mach-O"; then
		echo "Signing ${f#"$app"/}"
		sign "$f"
	fi
done < <(find "$app/Contents/Frameworks" "$app/Contents/MacOS" -type f -print0)

sign "$app"
codesign --verify --deep --strict --verbose=2 "$app"


echo "STEP 3 - NOTARIZE"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
	creds=(--keychain-profile "$NOTARY_PROFILE")
else
	creds=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
fi

# Apple needs an archive to notarize; this zip is only for the upload
ditto -c -k --keepParent "$app" "$tmp/notarize.zip"
result=$(xcrun notarytool submit "$tmp/notarize.zip" "${creds[@]}" --wait --timeout 30m --output-format json)
echo "$result"
status=$(plutil -extract status raw - <<< "$result")
subid=$(plutil -extract id raw - <<< "$result")

if [[ "$status" != "Accepted" ]]; then
	echo "ERROR: notarization status is '$status'. Apple's log:"
	xcrun notarytool log "$subid" "${creds[@]}" || true
	exit 1
fi


echo "STEP 4 - STAPLE AND ZIP"

# A zip can't carry the ticket, so it goes onto the app itself. Fetching it right
# after notarization sometimes fails at first - so try a few times.
stapled=no
for attempt in 1 2 3 4 5; do
	if xcrun stapler staple "$app"; then
		stapled=yes
		break
	fi
	echo "Stapling attempt $attempt failed - retrying in 30 seconds"
	sleep 30
done
if [[ "$stapled" != "yes" ]]; then
	echo "ERROR: could not staple the ticket after 5 attempts"
	exit 1
fi
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"

rm -f "$zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
echo "DONE: $zip"
