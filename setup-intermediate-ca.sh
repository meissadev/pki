#!/usr/bin/env bash
#
# setup-intermediate-ca.sh
# Step 2 of a Root CA / Intermediate CA PKI hierarchy.
# Creates the Intermediate CA directory structure and config, generates its
# key + CSR, then gets it signed by the Root CA and builds the chain file.
#
# Usage: ./setup-intermediate-ca.sh <root-ca-dir> [intermediate-dir]
#   root-ca-dir       path to the Root CA created by setup-root-ca.sh (required)
#   intermediate-dir  defaults to "./intermediate"

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <root-ca-dir> [intermediate-dir]" >&2
  exit 1
fi

ROOT_CA_DIR="$(cd "$1" && pwd)"
INT_DIR="${2:-./intermediate}"

if [ ! -f "${ROOT_CA_DIR}/openssl.cnf" ] || [ ! -f "${ROOT_CA_DIR}/private/ca.key.pem" ]; then
  echo "[!] ${ROOT_CA_DIR} doesn't look like a Root CA dir (missing openssl.cnf or private/ca.key.pem)" >&2
  exit 1
fi

echo "[*] Using Root CA at: ${ROOT_CA_DIR}"

# -----------------------------------------------------------------------------
# 1. Directory structure
# -----------------------------------------------------------------------------
echo "[*] Creating intermediate CA directory structure at ${INT_DIR}"
mkdir -p "${INT_DIR}"
cd "${INT_DIR}"

mkdir -p certs crl csr newcerts private
chmod 700 private

touch index.txt
[ -f index.txt.attr ] || echo "unique_subject = yes" > index.txt.attr

[ -f serial ]    || echo 1000 > serial
[ -f crlnumber ] || echo 1000 > crlnumber

# -----------------------------------------------------------------------------
# 2. Configuration file (openssl.cnf)
# -----------------------------------------------------------------------------
# Generated locally (same reasoning as the root script) so it always matches
# what -extensions v3_intermediate_ca expects, and points "dir" at this
# intermediate tree rather than the root's.
echo "[*] Writing openssl.cnf"
cat > openssl.cnf <<EOF
# OpenSSL intermediate CA configuration file.

[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = .
certs             = \$dir/certs
crl_dir           = \$dir/crl
new_certs_dir     = \$dir/newcerts
database          = \$dir/index.txt
serial            = \$dir/serial
RANDFILE          = \$dir/private/.rand

private_key       = \$dir/private/intermediate.key.pem
certificate       = \$dir/certs/intermediate.cert.pem

crlnumber         = \$dir/crlnumber
crl               = \$dir/crl/intermediate.crl.pem
crl_extensions    = crl_ext
default_crl_days  = 365

default_md        = sha256

name_opt          = ca_default
cert_opt          = ca_default
default_days      = 375
preserve          = no
policy            = policy_loose

[ policy_strict ]
countryName             = match
stateOrProvinceName     = match
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ policy_loose ]
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
default_bits        = 4096
distinguished_name  = req_distinguished_name
string_mask         = utf8only
default_md          = sha256

[ req_distinguished_name ]
countryName                    = Country Name (2 letter code)
stateOrProvinceName             = State or Province Name
localityName                    = Locality Name
0.organizationName               = Organization Name
organizationalUnitName          = Organizational Unit Name
commonName                      = Common Name
emailAddress                    = Email Address

countryName_default             = SN
stateOrProvinceName_default     = Dakar
localityName_default            = Dakar
0.organizationName_default      = My Organization
organizationalUnitName_default  = My Organization Intermediate CA

[ v3_intermediate_ca ]
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints       = critical, CA:true, pathlen:0
keyUsage                = critical, digitalSignature, cRLSign, keyCertSign

[ usr_cert ]
basicConstraints        = CA:FALSE
nsCertType               = client, email
nsComment                = "OpenSSL Generated Client Certificate"
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid,issuer
keyUsage                 = critical, nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage         = clientAuth, emailProtection

[ server_cert ]
basicConstraints        = CA:FALSE
nsCertType               = server
nsComment                = "OpenSSL Generated Server Certificate"
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid,issuer:always
keyUsage                 = critical, digitalSignature, keyEncipherment
extendedKeyUsage         = serverAuth

[ crl_ext ]
authorityKeyIdentifier = keyid:always

[ ocsp ]
basicConstraints        = CA:FALSE
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid,issuer
keyUsage                 = critical, digitalSignature
extendedKeyUsage         = critical, OCSPSigning
EOF

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
echo "[*] Generating intermediate CSR"
openssl req -new \
  -config openssl.cnf \
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
# 6. Chain file (intermediate + root)
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