#!/usr/bin/env bash

set -euo pipefail

CA_DIR="${1:-./ca}"

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
echo "[*] Creating CA directory structure at ${CA_DIR}"
mkdir -p "${CA_DIR}"
cd "${CA_DIR}"

mkdir -p certs crl newcerts private csr
chmod 700 private

touch index.txt
[ -f index.txt.attr ] || echo "unique_subject = yes" > index.txt.attr

# Serial/crlnumber: avoid clobbering an existing CA on re-run
[ -f serial ]    || echo 1000 > serial
[ -f crlnumber ] || echo 1000 > crlnumber

# -----------------------------------------------------------------------------
# 2. Configuration file (openssl.cnf)
# -----------------------------------------------------------------------------
# Generated locally rather than fetched, since the jamielinux.com URL serves
# an HTML doc page, not the raw config — piping that into openssl.cnf would
# produce a broken config.
#
# Heredoc is UNQUOTED so CA_COUNTRY etc. get substituted by bash; every
# OpenSSL-native $var (like $dir) is escaped with a backslash so OpenSSL
# still expands those itself at run time.
echo "[*] Writing openssl.cnf"
cat > openssl.cnf <<EOF
# OpenSSL root CA configuration file.

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

private_key       = \$dir/private/ca.key.pem
certificate       = \$dir/certs/ca.cert.pem

crlnumber         = \$dir/crlnumber
crl               = \$dir/crl/ca.crl.pem
crl_extensions    = crl_ext
default_crl_days  = 365

default_md        = sha256

name_opt          = ca_default
cert_opt          = ca_default
default_days      = 375
preserve          = no
policy            = policy_strict

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
x509_extensions     = v3_ca

[ req_distinguished_name ]
countryName                    = Country Name (2 letter code)
stateOrProvinceName             = State or Province Name
localityName                    = Locality Name
0.organizationName               = Organization Name
organizationalUnitName          = Organizational Unit Name
commonName                      = Common Name
emailAddress                    = Email Address

countryName_default             = ${CA_COUNTRY}
stateOrProvinceName_default     = ${CA_STATE}
localityName_default            = ${CA_LOCALITY}
0.organizationName_default      = ${CA_ORG}
organizationalUnitName_default  = ${CA_ORG_UNIT}
EOF

# emailAddress_default is only written if CA_EMAIL was set, so an empty
# value doesn't force an empty-but-present field in the req prompts.
if [ -n "${CA_EMAIL}" ]; then
  echo "emailAddress_default             = ${CA_EMAIL}" >> openssl.cnf
fi

cat >> openssl.cnf <<'EOF'

[ v3_ca ]
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints       = critical, CA:true
keyUsage                = critical, digitalSignature, cRLSign, keyCertSign

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
  -config openssl.cnf \
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