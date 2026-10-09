#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  碳迹 —— 本地签名（无需 DevEco Studio 图形界面）
#
#  原理：SDK 自带 OpenHarmony 调试签名材料（hap-sign-tool.jar + OpenHarmony.p12
#  + OpenHarmonyProfileDebug.pem），用它做本地签名，产出可安装到模拟器/调试设备的 HAP。
#
#  流程：
#    1. 复制 OpenHarmony.p12（不改动 SDK 原件）
#    2. 导出根 CA / 二级 CA 证书（注意：hap-sign-tool 只认 .cer 扩展名，不认 .pem）
#    3. 生成应用签名密钥对
#    4. 用 OpenHarmony Application CA 签发应用证书链
#    5. 按本应用的 bundleName 生成调试 profile 并签名
#    6. 用应用密钥 + 证书链 + profile 签 HAP
#
#  用法：
#    tools/sign.sh <unsigned.hap> [输出.hap]
#    可选环境变量：
#      CARBON_SIGN_DIR   签名材料目录（默认在工程内的 signing/）
#      CARBON_UDID       调试设备 UDID（模拟器/真机），留空则用模板内置值
#      CARBON_BUNDLE     应用包名（默认从 AppScope/app.json5 读取）
# ---------------------------------------------------------------------------
set -euo pipefail

WS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_PROJECT="${CARBON_PROJECT_DIR:-$HOME/DevEcoStudioProjects/carbon-footprint}"
# 签名材料放在工程内的 signing/ 目录，使工程自包含
SIGN_DIR="${CARBON_SIGN_DIR:-$HOME/DevEcoStudioProjects/carbon-footprint/signing}"

DEVECO_APP="${DEVECO_APP:-/Applications/DevEco-Studio.app}"
LIB="$DEVECO_APP/Contents/sdk/default/openharmony/toolchains/lib"
JAVA="$DEVECO_APP/Contents/jbr/Contents/Home/bin/java"
KEYTOOL="$DEVECO_APP/Contents/jbr/Contents/Home/bin/keytool"

IN_HAP="${1:-}"
OUT_HAP="${2:-}"
if [ -z "$IN_HAP" ]; then
  IN_HAP="$(find "$SRC_PROJECT/entry/build" -name '*-unsigned.hap' 2>/dev/null | head -1)"
fi
if [ -z "$IN_HAP" ] || [ ! -f "$IN_HAP" ]; then
  echo "错误：找不到未签名 HAP。用法：tools/sign.sh <unsigned.hap> [out.hap]" >&2
  exit 1
fi
if [ -z "$OUT_HAP" ]; then
  OUT_HAP="${IN_HAP%-unsigned.hap}-signed.hap"
fi

# 从工程读 bundleName，保证与 profile 一致
if [ -z "${CARBON_BUNDLE:-}" ]; then
  CARBON_BUNDLE="$(python3 -c "
import re,sys
s=open('$SRC_PROJECT/AppScope/app.json5').read()
m=re.search(r'\"bundleName\"\s*:\s*\"([^\"]+)\"', s)
print(m.group(1) if m else '')
")"
fi
if [ -z "$CARBON_BUNDLE" ]; then
  echo "错误：无法确定 bundleName" >&2
  exit 1
fi

PWD_STORE="123456"
KEY_ALIAS="carbon-app-key"

mkdir -p "$SIGN_DIR"
echo "签名目录：$SIGN_DIR"
echo "应用包名：$CARBON_BUNDLE"
echo "输入 HAP：$IN_HAP"

# ---------- 1) 复制密钥库（不动 SDK 原件） ----------
STORE="$SIGN_DIR/oh-keystore.p12"
if [ ! -f "$STORE" ]; then
  cp "$LIB/OpenHarmony.p12" "$STORE"
  echo "[1/6] 已复制 OpenHarmony.p12 → $STORE"
else
  echo "[1/6] 密钥库已存在，跳过"
fi

# ---------- 2) 导出 CA 证书 ----------
if [ ! -f "$SIGN_DIR/root-ca.cer" ] || [ ! -f "$SIGN_DIR/sub-ca.cer" ]; then
  "$KEYTOOL" -exportcert -alias "openharmony application root ca" \
    -keystore "$STORE" -storetype PKCS12 -storepass "$PWD_STORE" -rfc \
    -file "$SIGN_DIR/root-ca.cer" >/dev/null 2>&1
  "$KEYTOOL" -exportcert -alias "openharmony application ca" \
    -keystore "$STORE" -storetype PKCS12 -storepass "$PWD_STORE" -rfc \
    -file "$SIGN_DIR/sub-ca.cer" >/dev/null 2>&1
  echo "[2/6] 已导出根 CA 与二级 CA 证书"
else
  echo "[2/6] CA 证书已存在，跳过"
fi

# ---------- 3) 生成应用签名密钥 ----------
if ! "$KEYTOOL" -list -keystore "$STORE" -storetype PKCS12 -storepass "$PWD_STORE" \
     -alias "$KEY_ALIAS" >/dev/null 2>&1; then
  "$JAVA" -jar "$LIB/hap-sign-tool.jar" generate-keypair \
    -keyAlias "$KEY_ALIAS" -keyPwd "$PWD_STORE" \
    -keyAlg ECC -keySize NIST-P-256 \
    -keystoreFile "$STORE" -keystorePwd "$PWD_STORE" >/dev/null
  echo "[3/6] 已生成应用签名密钥 $KEY_ALIAS"
else
  echo "[3/6] 应用签名密钥已存在，跳过"
fi

# ---------- 4) 签发应用证书链 ----------
if [ ! -f "$SIGN_DIR/app-cert.pem" ]; then
  "$JAVA" -jar "$LIB/hap-sign-tool.jar" generate-app-cert \
    -keyAlias "$KEY_ALIAS" -keyPwd "$PWD_STORE" \
    -issuer "C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=OpenHarmony Application CA" \
    -issuerKeyAlias "openharmony application ca" -issuerKeyPwd "$PWD_STORE" \
    -subject "C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=Carbon Footprint" \
    -validity 3650 -signAlg SHA256withECDSA \
    -keystoreFile "$STORE" -keystorePwd "$PWD_STORE" \
    -issuerKeystoreFile "$STORE" -issuerKeystorePwd "$PWD_STORE" \
    -outForm certChain \
    -rootCaCertFile "$SIGN_DIR/root-ca.cer" \
    -subCaCertFile "$SIGN_DIR/sub-ca.cer" \
    -outFile "$SIGN_DIR/app-cert.pem" >/dev/null
  echo "[4/6] 已签发应用证书链"
else
  echo "[4/6] 应用证书链已存在，跳过"
fi

# ---------- 5) 生成并签名调试 profile ----------
export CARBON_BUNDLE SIGN_DIR CARBON_UDID="${CARBON_UDID:-}"
python3 - <<'PY'
import json, os, time
sign_dir = os.environ['SIGN_DIR']
bundle = os.environ['CARBON_BUNDLE']
udid = os.environ.get('CARBON_UDID', '').strip()

chain = open(os.path.join(sign_dir, 'app-cert.pem')).read()
blocks = [b for b in chain.split('-----END CERTIFICATE-----') if 'BEGIN CERTIFICATE' in b]
leaf = blocks[0] + '-----END CERTIFICATE-----\n'

now = int(time.time())
profile = {
    "version-name": "2.0.0",
    "version-code": 2,
    "uuid": "fe686e1b-3770-4824-a938-961b140a7c98",
    "validity": {"not-before": now - 86400, "not-after": now + 3650 * 86400},
    "type": "debug",
    "bundle-info": {
        "developer-id": "OpenHarmony",
        "development-certificate": leaf,
        "bundle-name": bundle,
        "apl": "normal",
        "app-feature": "hos_normal_app"
    },
    "acls": {"allowed-acls": [""]},
    "permissions": {"restricted-permissions": []},
    "debug-info": {
        "device-ids": [udid] if udid else [],
        "device-id-type": "udid"
    },
    "issuer": "pki_internal"
}
with open(os.path.join(sign_dir, 'profile.json'), 'w') as f:
    json.dump(profile, f, indent=4, ensure_ascii=False)
print(f"[5/6] 已生成 profile.json（bundle={bundle}, udid={udid or '（空，由设备校验策略决定）'}）")
PY

"$JAVA" -jar "$LIB/hap-sign-tool.jar" sign-profile \
  -mode localSign \
  -keyAlias "openharmony application profile debug" -keyPwd "$PWD_STORE" \
  -profileCertFile "$LIB/OpenHarmonyProfileDebug.pem" \
  -inFile "$SIGN_DIR/profile.json" \
  -signAlg SHA256withECDSA \
  -keystoreFile "$STORE" -keystorePwd "$PWD_STORE" \
  -outFile "$SIGN_DIR/carbon.p7b" >/dev/null
echo "      已签名 profile → carbon.p7b"

# ---------- 6) 签 HAP ----------
"$JAVA" -jar "$LIB/hap-sign-tool.jar" sign-app \
  -mode localSign \
  -keyAlias "$KEY_ALIAS" -keyPwd "$PWD_STORE" \
  -appCertFile "$SIGN_DIR/app-cert.pem" \
  -profileFile "$SIGN_DIR/carbon.p7b" \
  -inFile "$IN_HAP" \
  -signAlg SHA256withECDSA \
  -keystoreFile "$STORE" -keystorePwd "$PWD_STORE" \
  -outFile "$OUT_HAP" \
  -compatibleVersion 12 \
  -signCode 1 >/dev/null

echo "[6/6] 已签名 HAP → $OUT_HAP"
ls -la "$OUT_HAP"
