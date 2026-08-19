#!/usr/bin/env bash

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <root-ca-dir> [intermediate-dir]" >&2
  exit 1
fi

ROOT_CA_DIR="$(cd "$1" && pwd)"
export ROOT_CA_DIR
INT_DIR="${2:-./intermediate}"

if [ ! -f "${ROOT_CA_DIR}/openssl.cnf" ] || [ ! -f "${ROOT_CA_DIR}/private/ca.key.pem" ]; then
  echo "[!] ${ROOT_CA_DIR} doesn't look like a root CA dir (missing openssl.cnf or private/ca.key.pem)" >&2
  exit 1
fi

echo "[*] Using Root CA at: ${ROOT_CA_DIR}"

# -----------------------------------------------------------------------------
# 0. C/ST/L/O inherited from the root; OU/CN/email required for this run
# -----------------------------------------------------------------------------
if [ -f "${ROOT_CA_DIR}/ca-defaults.env" ]; then
  echo "[*] Sourcing shared DN fields from ${ROOT_CA_DIR}/ca-defaults.env"
  # shellcheck disable=SC1091
  source "${ROOT_CA_DIR}/ca-defaults.env"
else
  echo "[!] ${ROOT_CA_DIR}/ca-defaults.env not found." >&2
  echo "    Was the root created with the current setup-root-ca.sh? Falling back to" >&2
  echo "    requiring CA_COUNTRY / CA_STATE / CA_LOCALITY / CA_ORG to be set manually." >&2
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
export CA_COUNTRY CA_STATE CA_LOCALITY CA_ORG CA_ORG_UNIT CA_COMMON_NAME
CA_EMAIL="${CA_EMAIL:-}"
export CA_EMAIL

echo "[*] Distinguished Name for this intermediate:"
echo "      C=${CA_COUNTRY}  ST=${CA_STATE}  L=${CA_LOCALITY}  (inherited from root)"
echo "      O=${CA_ORG}  (inherited from root)"
echo "      OU=${CA_ORG_UNIT}  CN=${CA_COMMON_NAME}  emailAddress=${CA_EMAIL:-<none>}"

# -----------------------------------------------------------------------------
# 1. Directory structure
# -----------------------------------------------------------------------------
echo "[*] Using existing intermediate directory: ${INT_DIR}"
if [ ! -d "${INT_DIR}" ]; then
  echo "[!] Directory does not exist: ${INT_DIR}" >&2
  exit 1
fi

cd "${INT_DIR}"
INT_CONFIG="./openssl.cnf"

if [ ! -s "${INT_CONFIG}" ]; then
  echo "[!] Missing or empty OpenSSL config file: ${INT_CONFIG}" >&2
  exit 1
fi

mkdir -p certs crl csr newcerts private
chmod 700 private

touch index.txt
[ -f index.txt.attr ] || echo "unique_subject = yes" > index.txt.attr

[ -f serial ]    || echo 1000 > serial
[ -f crlnumber ] || echo 1000 > crlnumber

# -----------------------------------------------------------------------------
# 2. Intermediate private key
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
# 3. CSR
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
# 4. Sign the CSR with the Root CA
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
# 5. Chain file (intermediate + root)
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