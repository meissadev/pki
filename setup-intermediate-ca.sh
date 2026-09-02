#!/usr/bin/env bash

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <root-ca-dir> [intermediate-dir]" >&2
  exit 1
fi

CA_DIR_INPUT="${1:-./ca}"
if [ ! -d "${CA_DIR_INPUT}" ]; then
  echo "[!] Root CA directory does not exist: ${CA_DIR_INPUT}" >&2
    exit 1
fi

ROOT_CA_DIR="$(cd "${CA_DIR_INPUT}" && pwd)"
export ROOT_CA_DIR

if [ ! -f "${ROOT_CA_DIR}/openssl.cnf" ] || [ ! -f "${ROOT_CA_DIR}/private/ca.key.pem" ]; then
  echo "[!] ${ROOT_CA_DIR} doesn't look like a root CA dir (missing openssl.cnf or private/ca.key.pem)" >&2
  exit 1
fi

echo "[*] Using Root CA at: ${ROOT_CA_DIR}"

INT_DIR_INPUT="${2:-./intermediate}"
if [ ! -d "${INT_DIR_INPUT}" ]; then
  echo "[!] Intermediate CA directory does not exist: ${INT_DIR_INPUT}" >&2
    exit 1
fi

INT_DIR="$(cd "${INT_DIR_INPUT}" && pwd)"
export INT_DIR

cd "${INT_DIR}"
INT_CONFIG="./openssl.cnf"

if [ ! -s "${INT_CONFIG}" ]; then
  echo "[!] Missing or empty OpenSSL config file: ${INT_CONFIG}" >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# 0. Bake the intermediate CA directory path
# -----------------------------------------------------------------------------
echo "[*] Substituting real values into ${INT_CONFIG}"
 
sed_escape_repl() {
  printf '%s' "$1" | sed -e 's/[\&#]/\\&/g'
}
 
SED_SCRIPT="$(mktemp)"
trap 'rm -f "${SED_SCRIPT}"' EXIT
 
{
  printf 's#${ENV::INT_DIR}#%s#g\n'    "$(sed_escape_repl "${INT_DIR}")"
} > "${SED_SCRIPT}"
 
sed -i -f "${SED_SCRIPT}" "${INT_CONFIG}"

# -----------------------------------------------------------------------------
# 1. C/ST/L/O inherited from the root; OU/CN/email required for this run. 
# Pull them straight out of the root's already-baked openssl.cnf
# -----------------------------------------------------------------------------
get_cnf_value() {
  local key="$1" file="$2"
  sed -n "s/^${key}[[:space:]]*=[[:space:]]*//p" "${file}" | head -n1 | sed 's/[[:space:]]*$//'
}

ROOT_CNF="${ROOT_CA_DIR}/openssl.cnf"
CA_COUNTRY="$(get_cnf_value countryName_default "${ROOT_CNF}")"
CA_STATE="$(get_cnf_value stateOrProvinceName_default "${ROOT_CNF}")"
CA_LOCALITY="$(get_cnf_value localityName_default "${ROOT_CNF}")"
CA_ORG="$(get_cnf_value 0.organizationName_default "${ROOT_CNF}")"
CA_ORG_UNIT="$(get_cnf_value organizationalUnitName_default "${ROOT_CNF}")"
CA_COMMON_NAME="$(get_cnf_value commonName_default "${ROOT_CNF}")"
CA_EMAIL="$(get_cnf_value emailAddress_default "${ROOT_CNF}")"

if [ -z "${CA_COUNTRY}" ] || [ -z "${CA_ORG}" ]; then
  echo "[!] Could not read countryName_default / 0.organizationName_default from ${ROOT_CNF}" >&2
  echo "    Was the root baked by setup-root-ca.sh? Or export CA_COUNTRY/CA_STATE/CA_LOCALITY/CA_ORG manually." >&2
  exit 1
fi

for required_var in CA_COUNTRY CA_STATE CA_LOCALITY CA_ORG CA_ORG_UNIT CA_COMMON_NAME; do
  if [ -z "${!required_var:-}" ]; then
    echo "[!] Required environment variable ${required_var} is not set." >&2
    echo "    Example:" >&2
    echo "      CA_ORG_UNIT='My Organization Intermediate CA' \\" >&2
    echo "      CA_COMMON_NAME='My Organization Intermediate CA' \\" >&2
    echo "      ./setup-intermediate-ca.sh ${ROOT_CA_DIR}" >&2
    exit 1
  fi
done
export CA_COUNTRY CA_STATE CA_LOCALITY CA_ORG CA_ORG_UNIT CA_COMMON_NAME CA_EMAIL

echo "[*] Distinguished Name for this intermediate:"
echo "      C=${CA_COUNTRY}  ST=${CA_STATE}  L=${CA_LOCALITY}  (inherited from root)"
echo "      O=${CA_ORG}  (inherited from root)"
echo "      OU=${CA_ORG_UNIT}  CN=${CA_COMMON_NAME}  emailAddress=${CA_EMAIL:-<none>}"

# -----------------------------------------------------------------------------
# 2. Directory structure
# -----------------------------------------------------------------------------
mkdir -p certs crl csr newcerts private
chmod 700 private

touch index.txt
[ -f index.txt.attr ] || echo "unique_subject = yes" > index.txt.attr

[ -f serial ]    || echo 1000 > serial
[ -f crlnumber ] || echo 1000 > crlnumber

# -----------------------------------------------------------------------------
# 3. Intermediate private key
# -----------------------------------------------------------------------------
if [ -f private/intermediate.key.pem ]; then
  echo "[*] Intermediate key already exists, skipping generation"
else
  echo "[*] Generating intermediate CA private key (4096-bit RSA, AES-256 encrypted)"
  echo "    Use a passphrase different from the root key's."
  openssl genrsa -aes256 -out private/intermediate.key.pem 4096
  chmod 400 private/intermediate.key.pem
fi

# -----------------------------------------------------------------------------
# 4. CSR
# -----------------------------------------------------------------------------
SUBJECT="/C=${CA_COUNTRY}/ST=${CA_STATE}/L=${CA_LOCALITY}/O=${CA_ORG}/OU=${CA_ORG_UNIT}/CN=${CA_COMMON_NAME}"
if [ -n "${CA_EMAIL}" ]; then
  SUBJECT="${SUBJECT}/emailAddress=${CA_EMAIL}"
fi

echo "[*] Generating intermediate CSR"
openssl req -new \
  -config "${INT_CONFIG}" \
  -subj "${SUBJECT}" \
  -key private/intermediate.key.pem \
  -out csr/intermediate.csr.pem \
  -sha256

# -----------------------------------------------------------------------------
# 5. Sign the CSR with the Root CA
# -----------------------------------------------------------------------------
echo "[*] Signing CSR with Root CA (730 days)"
echo "    You'll be prompted for the ROOT key passphrase, then to confirm signing."
openssl ca -days 730 \
  -config "${ROOT_CA_DIR}/openssl.cnf" \
  -extensions v3_intermediate_ca \
  -in csr/intermediate.csr.pem \
  -out certs/intermediate.cert.pem \
  -md sha256 \
  -notext
chmod 444 certs/intermediate.cert.pem

echo "[*] Verifying intermediate cert against root"
openssl verify -CAfile "${ROOT_CA_DIR}/certs/ca.cert.pem" certs/intermediate.cert.pem

# -----------------------------------------------------------------------------
# 7. Chain file (intermediate + root)
# -----------------------------------------------------------------------------
echo "[*] Building CA chain file"
cat certs/intermediate.cert.pem "${ROOT_CA_DIR}/certs/ca.cert.pem" > certs/ca-chain.cert.pem
chmod 444 certs/ca-chain.cert.pem

echo
echo "[+] Intermediate CA created at: $(pwd)"
echo "    Key:   private/intermediate.key.pem"
echo "    Cert:  certs/intermediate.cert.pem"
echo "    Chain: certs/ca-chain.cert.pem  (use this to serve end-entity certs)"
echo
echo "Next step: issue end-entity (server/client) certs signed by this intermediate."