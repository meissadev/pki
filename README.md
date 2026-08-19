# PKI setup

## Requirements

- Linux or another Unix-like operating system
- OpenSSL installed and available in PATH
- A writable local directory for the CA files
- A valid hostname or DNS name if you plan to use the certificates for TLS on a server
- Root privileges only when required for local certificate storage or system trust configuration

## Important note

The root and intermediate OpenSSL config files are already present in the repository under `ca/` and `intermediate/`.

The subject values in those config files are intentionally left blank, so the values must be provided through environment variables before running the scripts.

## Root CA

setup-root-ca.sh
Step 1 of a Root CA / Intermediate CA PKI hierarchy.

Operates on an ALREADY-EXISTING ./ca/openssl.cnf (the one that uses
${ENV::CA_COUNTRY} etc. substitutions) rather than generating one, so the
config stays checked into your repo and under version control.

Usage:
    CA_COUNTRY=SN CA_STATE=Dakar CA_LOCALITY=Dakar \
    CA_ORG="My Organization" CA_ORG_UNIT="My Organization Root CA" \
    CA_COMMON_NAME="My Organization Root CA" \
    [CA_EMAIL=pki@example.com] \
    ./setup-root-ca.sh [ca-dir]

ca-dir defaults to "./ca" and must already contain openssl.cnf.

All six identity vars above are REQUIRED except CA_EMAIL. The script also
writes <ca-dir>/ca-defaults.env, containing just the fields that MUST be
identical between root and intermediate (country/state/locality/org) —
policy_strict in openssl.cnf enforces that match when the root signs the
intermediate's CSR. setup-intermediate-ca.sh sources that file
automatically, so you only ever type those four values once.

**Example**:
    CA_COUNTRY="SN" \
    CA_STATE="Dakar" \
    CA_LOCALITY="Dakar" \
    CA_ORG="My Organization" \
    CA_ORG_UNIT="My Organization Root CA" \
    CA_COMMON_NAME="My Organization Root CA" \
    CA_EMAIL="mail@pki.conf" \
    ./setup-root-ca.sh

## Intermediate CA

setup-intermediate-ca.sh
Step 2 of a Root CA / Intermediate CA PKI hierarchy.

Operates on an ALREADY-EXISTING ./intermediate/openssl.cnf (${ENV::VAR} substitutions) — generates the intermediate key + CSR, then gets it
signed by the root and builds the chain file.

Usage:
    CA_ORG_UNIT="My Organization Intermediate CA" \
    CA_COMMON_NAME="My Organization Intermediate CA" \
    [CA_EMAIL=pki@example.com] \
    ./setup-intermediate-ca.sh <root-ca-dir> [intermediate-dir]

root-ca-dir      : path to the root created by setup-root-ca.sh (required)
intermediate-dir : defaults to "./intermediate", must already contain
                   openssl.cnf

CA_COUNTRY / CA_STATE / CA_LOCALITY / CA_ORG are NOT meant to be retyped
here: this script sources <root-ca-dir>/ca-defaults.env, written by
setup-root-ca.sh from the values used for the root, so C/ST/L/O are
automatically identical to the root's — required for policy_strict on the
root to accept the signing request in step 4 below. You only need to
supply CA_ORG_UNIT and CA_COMMON_NAME (and optionally CA_EMAIL), which are
meant to differ from the root's own OU/CN.

This is the "best way" to keep root and intermediate DN fields in sync:
no manual retyping, no risk of a C/ST/O typo silently breaking the sign
step later. If you genuinely need to override an inherited value for this
run only, export it yourself before invoking the script — the sourced
file uses ":=" so it never clobbers an already-exported variable.

**Example**:
    CA_COUNTRY="SN" \
    CA_STATE="Dakar" \
    CA_LOCALITY="Dakar" \
    CA_ORG="My Organization" \
    CA_ORG_UNIT="My Organization Root CA" \
    CA_COMMON_NAME="My Organization Root CA" \
    CA_EMAIL="mail@pki.conf" \
    ./setup-intermediate-ca.sh /path/to/ca

