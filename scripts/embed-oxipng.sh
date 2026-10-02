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

for tool in pandoc gs; do
    case "$tool" in pandoc) package=pandoc ;; gs) package=ghostscript ;; esac
    destination="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers/$tool"
    /usr/bin/gunzip -c "${SRCROOT}/ThirdParty/$package/$tool.gz" > "$destination"
    chmod 755 "$destination"
    cp "${SRCROOT}/ThirdParty/$package/LICENSE" "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/$package-LICENSE.txt"
    if [ "${CODE_SIGNING_ALLOWED:-NO}" = YES ]; then
        /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --options runtime --entitlements "${SRCROOT}/ThirdParty/oxipng/helper.entitlements" "$destination"
    else
        /usr/bin/codesign --force --sign - "$destination"
    fi
done

cp "${SRCROOT}/ThirdParty/ghostscript/THIRD-PARTY-NOTICES.txt" "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/ghostscript-THIRD-PARTY-NOTICES.txt"
