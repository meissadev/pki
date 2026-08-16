# This is a quantum aware pki installation and configuration in Debian-based Linux distributions

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

