# This is a quantum aware pki installation and configuration in Debian-based Linux distributions

# setup-root-ca.sh
# Step 1 of a Root CA / Intermediate CA PKI hierarchy.
# Creates the Root CA directory structure, config, private key, and
# self-signed root certificate.
#
# Usage: ./setup-root-ca.sh [ca-dir]
#   ca-dir defaults to "./ca"
#
# The req_distinguished_name defaults (country, state, locality, org, ...)
# can be overridden via environment variables so you don't have to edit the
# script. The intermediate CA script reads these same values back out of
# this root's openssl.cnf, so setting them here is enough to keep root and
# intermediate consistent.
#
#   CA_COUNTRY=SN CA_STATE=Dakar CA_LOCALITY=Dakar \
#   CA_ORG="My Organization" CA_ORG_UNIT="My Organization Root CA" \
#   CA_EMAIL=pki@example.com \
#   ./setup-root-ca.sh































## 1. Requirements

* **VMs:** at least 2
* **OS:** Debian-based Linux distribution (Debian 12+, Ubuntu 22.04+, or Kali 2024+)
* **Package Manager:** `apt`
* **A domain name server**
* **Make sure you can execute commands as root**

## 2. Configuration files
### 2.1. Clone the repo and initiate the project
`git clone https://github.com/meissadev/pki.git`
`cd pki`

Getting the OpenSSL configuration files on 
`https://jamielinux.com/docs/openssl-certificate-authority/appendix/index.html`

### 2.1. Copy the root CA configuration file to `./ca/openssl.cnf`:
`wget https://jamielinux.com/docs/openssl-certificate-authority/_downloads/root-config.txt -O ./root-ca/openssl.cnf`

### 2.2. Copy the intermediate CA configuration file to `./intermediate/openssl.cnf`:
`wget https://jamielinux.com/docs/openssl-certificate-authority/_downloads/intermediate-config.txt -O ./intermediate-ca/openssl.cnf`

You can go through the files to check or modify default values.
For more information refer to the OpenSSSL `man ca` and `https://jamielinux.com/docs/openssl-certificate-authority/index.html`

