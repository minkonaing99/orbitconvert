#!/bin/sh
set -eu
helper="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers/oxipng"
mkdir -p "$(dirname "$helper")" "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
cp "${SRCROOT}/ThirdParty/oxipng/oxipng" "$helper"
chmod 755 "$helper"
cp "${SRCROOT}/ThirdParty/oxipng/LICENSE" "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Oxipng-LICENSE.txt"
cp "${SRCROOT}/ThirdParty/oxipng/THIRD-PARTY-NOTICES.txt" "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Oxipng-THIRD-PARTY-NOTICES.txt"
if [ "${CODE_SIGNING_ALLOWED:-NO}" = YES ]; then
    /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --options runtime --entitlements "${SRCROOT}/ThirdParty/oxipng/helper.entitlements" "$helper"
else
    /usr/bin/codesign --force --sign - "$helper"
fi
