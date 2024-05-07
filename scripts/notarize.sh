#!/bin/bash

myname=`basename "$0"`
usage() {
    echo "Usage: ${myname} /path/to/product.zip"
}

if [ "$#" -lt 1 ]; then
    usage
    exit 1
fi

UPLOAD_INFO_PLIST=./NotarizationUploadInfo.plist
PRODUCT_PATH="$1"

echo "Uploading ${PRODUCT_PATH} for notarization..."
xcrun notarytool submit \
    --team-id "${NOTARIZATION_TEAM}" --apple-id "${NOTARIZATION_USER}" --password "${NOTARIZATION_PASSWORD}" \
    "${PRODUCT_PATH}" \
    --wait \
    --output-format plist > "${UPLOAD_INFO_PLIST}"

status=`/usr/libexec/PlistBuddy -c "Print :status" "${UPLOAD_INFO_PLIST}"`
uuid=`/usr/libexec/PlistBuddy -c "Print :id" "${UPLOAD_INFO_PLIST}"`
rm -rf "${UPLOAD_INFO_PLIST}"

if [ -z "$uuid" ]; then
    echo "ERROR: Unable to parse a request id, aborting"
    exit 1
fi

log=`xcrun notarytool log \
        --team-id "${NOTARIZATION_TEAM}" --apple-id "${NOTARIZATION_USER}" --password "${NOTARIZATION_PASSWORD}" \
        --output-format json "${uuid}"`

if [ "${status}" != "Accepted" ]; then
    echo "[ERROR] Upload failed, error report: ${log}"
    exit 1
fi

echo "[DONE] Notarization succeeded with the following report: ${log}"
exit 0
