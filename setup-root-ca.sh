#!/usr/bin/env bash

set -euo pipefail

CA_DIR_INPUT="${1:-./ca}"
echo "[*] Using existing CA directory: ${CA_DIR_INPUT}"
if [ ! -d "${CA_DIR_INPUT}" ]; then
  echo "[!] Directory does not exist: ${CA_DIR_INPUT}" >&2
    exit 1
fi

ROOT_CA_DIR="$(cd "${CA_DIR_INPUT}" && pwd)"
export ROOT_CA_DIR

cd "${ROOT_CA_DIR}"
CA_CONFIG="./openssl.cnf"

if [ ! -s "${CA_CONFIG}" ]; then
  echo "[!] Missing or empty OpenSSL config file: ${CA_CONFIG}" >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# 0. Required subject values for the root certificate
# -----------------------------------------------------------------------------
for required_var in CA_COUNTRY CA_STATE CA_LOCALITY CA_ORG CA_ORG_UNIT CA_COMMON_NAME; do
  if [ -z "${!required_var:-}" ]; then
    echo "[!] Required environment variable ${required_var} is not set." >&2
    echo "    Example:" >&2
    echo "      CA_COUNTRY=SN CA_STATE=Dakar CA_LOCALITY=Dakar \\" >&2
    echo "      CA_ORG='My Organization' CA_ORG_UNIT='My Organization Root CA' \\" >&2
    echo "      CA_COMMON_NAME='My Organization Root CA' ./setup-root-ca.sh" >&2
    exit 1
  fi
done
export CA_COUNTRY CA_STATE CA_LOCALITY CA_ORG CA_ORG_UNIT CA_COMMON_NAME
CA_EMAIL="${CA_EMAIL:-}"
export CA_EMAIL

echo "[*] Distinguished Name for this root:"
echo "      C=${CA_COUNTRY}  ST=${CA_STATE}  L=${CA_LOCALITY}"
echo "      O=${CA_ORG}  OU=${CA_ORG_UNIT}  CN=${CA_COMMON_NAME}"
echo "      emailAddress=${CA_EMAIL:-<none>}"

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
# 2. Bake the real values into openssl.cnf
# -----------------------------------------------------------------------------
echo "[*] Substituting real values into ${CA_CONFIG}"
 
sed_escape_repl() {
  printf '%s' "$1" | sed -e 's/[\&#]/\\&/g'
}
 
SED_SCRIPT="$(mktemp)"
trap 'rm -f "${SED_SCRIPT}"' EXIT
 
{
  printf 's#${ENV::ROOT_CA_DIR}#%s#g\n'    "$(sed_escape_repl "${ROOT_CA_DIR}")"
  printf 's#${ENV::CA_COUNTRY}#%s#g\n'     "$(sed_escape_repl "${CA_COUNTRY}")"
  printf 's#${ENV::CA_STATE}#%s#g\n'       "$(sed_escape_repl "${CA_STATE}")"
  printf 's#${ENV::CA_LOCALITY}#%s#g\n'    "$(sed_escape_repl "${CA_LOCALITY}")"
  printf 's#${ENV::CA_ORG}#%s#g\n'         "$(sed_escape_repl "${CA_ORG}")"
  printf 's#${ENV::CA_ORG_UNIT}#%s#g\n'    "$(sed_escape_repl "${CA_ORG_UNIT}")"
  printf 's#${ENV::CA_COMMON_NAME}#%s#g\n' "$(sed_escape_repl "${CA_COMMON_NAME}")"
  printf 's#${ENV::CA_EMAIL}#%s#g\n'       "$(sed_escape_repl "${CA_EMAIL}")"
} > "${SED_SCRIPT}"
 
sed -i -f "${SED_SCRIPT}" "${CA_CONFIG}"

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
# -subj makes this fully non-interactive regardless of whether the
# ${ENV::...} defaults in openssl.cnf resolve to anything.
SUBJECT="/C=${CA_COUNTRY}/ST=${CA_STATE}/L=${CA_LOCALITY}/O=${CA_ORG}/OU=${CA_ORG_UNIT}/CN=${CA_COMMON_NAME}"
if [ -n "${CA_EMAIL}" ]; then
  SUBJECT="${SUBJECT}/emailAddress=${CA_EMAIL}"
fi

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
