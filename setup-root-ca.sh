#!/usr/bin/env bash

set -euo pipefail

CA_DIR="${1:-./ca}"
cd "${CA_DIR}"
CA_CONFIG="./openssl.cnf"

# -----------------------------------------------------------------------------
# 0. Required subject values for the root certificate
# -----------------------------------------------------------------------------
for required_var in CA_COUNTRY CA_STATE CA_LOCALITY CA_ORG CA_ORG_UNIT CA_COMMON_NAME; do
  if [ -z "${!required_var:-}" ]; then
    echo "[!] Required environment variable ${required_var} is not set." >&2
    echo "    Example:" >&2
    echo "      CA_COUNTRY=SN CA_STATE=Dakar CA_LOCALITY=Dakar " >&2
    echo "      CA_ORG='My Organization' CA_ORG_UNIT='My Organization Root CA' " >&2
    echo "      CA_COMMON_NAME='My Organization Root CA' ./setup-root-ca.sh" >&2
    exit 1
  fi
done

CA_EMAIL="${CA_EMAIL:-}"

echo "[*] Using existing CA directory: ${CA_DIR}"
if [ ! -d "${CA_DIR}" ]; then
  echo "[!] Directory does not exist: ${CA_DIR}" >&2
  exit 1
fi

if [ ! -f "${CA_CONFIG}" ]; then
  echo "[!] Missing OpenSSL config file: ${CA_CONFIG}" >&2
  exit 1
fi

echo "[*] Distinguished Name values for this CA:"
echo "      C=${CA_COUNTRY}  ST=${CA_STATE}  L=${CA_LOCALITY}"
echo "      O=${CA_ORG}  OU=${CA_ORG_UNIT}  CN=${CA_COMMON_NAME}"
echo "      emailAddress=${CA_EMAIL:-<none>}"
echo "    Values are read from environment variables; no DN defaults are set in the repo config."

# -----------------------------------------------------------------------------
# 0. Distinguished Name defaults (override via env vars)
# -----------------------------------------------------------------------------
CA_COUNTRY="${CA_COUNTRY:-SN}"
CA_STATE="${CA_STATE:-Dakar}"
CA_LOCALITY="${CA_LOCALITY:-Dakar}"
CA_ORG="${CA_ORG:-My Organization}"
CA_ORG_UNIT="${CA_ORG_UNIT:-My Organization Root CA}"
CA_EMAIL="${CA_EMAIL:-}"

echo "[*] Distinguished Name defaults for this CA:"
echo "      C=${CA_COUNTRY}  ST=${CA_STATE}  L=${CA_LOCALITY}"
echo "      O=${CA_ORG}  OU=${CA_ORG_UNIT}  emailAddress=${CA_EMAIL:-<none>}"
echo "    Override with CA_COUNTRY / CA_STATE / CA_LOCALITY / CA_ORG / CA_ORG_UNIT / CA_EMAIL"

# -----------------------------------------------------------------------------
# 0. Distinguished Name defaults (override via env vars)
# -----------------------------------------------------------------------------
CA_COUNTRY="${CA_COUNTRY:-SN}"
CA_STATE="${CA_STATE:-Dakar}"
CA_LOCALITY="${CA_LOCALITY:-Dakar}"
CA_ORG="${CA_ORG:-My Organization}"
CA_ORG_UNIT="${CA_ORG_UNIT:-My Organization Root CA}"
CA_EMAIL="${CA_EMAIL:-}"

echo "[*] Distinguished Name defaults for this CA:"
echo "      C=${CA_COUNTRY}  ST=${CA_STATE}  L=${CA_LOCALITY}"
echo "      O=${CA_ORG}  OU=${CA_ORG_UNIT}  emailAddress=${CA_EMAIL:-<none>}"
echo "    Override with CA_COUNTRY / CA_STATE / CA_LOCALITY / CA_ORG / CA_ORG_UNIT / CA_EMAIL"

# -----------------------------------------------------------------------------
# 1. Directory structure
# -----------------------------------------------------------------------------
mkdir -p certs crl newcerts private csr
chmod 700 private

touch index.txt
[ -f index.txt.attr ] || echo "unique_subject = yes" > index.txt.attr

# Serial/crlnumber: avoid clobbering an existing CA on re-run
[ -f serial ]    || echo 1000 > serial
[ -f crlnumber ] || echo 1000 > crlnumber

# -----------------------------------------------------------------------------
# 2. Use the existing OpenSSL config; do not overwrite it
# -----------------------------------------------------------------------------
if [ ! -s "${CA_CONFIG}" ]; then
  echo "[!] ${CA_CONFIG} is empty. Restore the repository's configuration before continuing." >&2
  exit 1
fi

# Build the subject explicitly from env vars so the req defaults in the config
# may remain empty while the script still runs non-interactively.
SUBJECT="/C=${CA_COUNTRY}/ST=${CA_STATE}/L=${CA_LOCALITY}/O=${CA_ORG}/OU=${CA_ORG_UNIT}/CN=${CA_COMMON_NAME}"
if [ -n "${CA_EMAIL}" ]; then
  SUBJECT="${SUBJECT}/emailAddress=${CA_EMAIL}"
fi

# -----------------------------------------------------------------------------
# 3. Root private key
# -----------------------------------------------------------------------------
if [ -f private/ca.key.pem ]; then
  echo "[*] Root key already exists, skipping generation"
else
  echo "[*] Generating root CA private key (4096-bit RSA, AES-256 encrypted)"
  echo "    You will be prompted for a passphrase — store it in a secrets manager, not on disk."
  openssl genrsa -aes256 -out private/ca.key.pem 4096
  chmod 400 private/ca.key.pem
fi

# -----------------------------------------------------------------------------
# 4. Root certificate (self-signed)
# -----------------------------------------------------------------------------
echo "[*] Generating self-signed root certificate (10 years, sha256)"
openssl req -new -x509 -days 3650 \
  -config "${CA_CONFIG}" \
  -subj "${SUBJECT}" \
  -key private/ca.key.pem \
  -out certs/ca.cert.pem \
  -extensions v3_ca \
  -sha256
chmod 444 certs/ca.cert.pem

echo "[*] Verifying certificate"
openssl x509 -noout -text -in certs/ca.cert.pem | head -n 20

echo
echo "[+] Root CA created at: $(pwd)"
echo "    Key:  private/ca.key.pem  (keep offline/air-gapped ideally)"
echo "    Cert: certs/ca.cert.pem"
echo
echo "Next step: intermediate CA, signed by this root."