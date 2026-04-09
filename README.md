# GlobalSign Atlas API CLI

![Bash](https://img.shields.io/badge/Bash-sh-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Linux-informational.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)
![Status](https://img.shields.io/badge/Status-Active-success.svg)
[![API](https://img.shields.io/badge/API-GlobalSign%20Atlas-blue.svg)](https://api.docs.globalsign.com/)

A production-ready Bash CLI for interacting with the GlobalSign Atlas Certificate Management API.

This tool provides a structured, menu-driven interface for:
- Certificate issuance (automated and manual)
- Certificate lifecycle management (retrieve, revoke, reissue)
- Domain validation workflows
- IP validation workflows
- Certificate statistics and policy inspection

This project is designed for **operators, engineers, and platform teams** managing TLS certificates at scale.

# Purpose

This project is designed to provide additional flexibility and options for managing your certificates. It is not intended to replace any existing tools you may already be using, but rather to complement them and expand your available workflows.

Please note that this is a personal initiative created to support the community. You are allowed to modify, adapt, and integrate it into your own environment as needed.

<img width="1707" height="710" alt="image" src="https://github.com/user-attachments/assets/45168435-bbf8-485a-a85b-b6af50ac799b" />



# Table of Contents

- Overview
- Architecture and Design Philosophy
- Prerequisites
- Configuration
- Usage Overview
- Issuing Certificates
  - Auto Issuance
  - Request a New Certificate
  - Get Certificate by ID
  - Revoke Certificate
  - Rekey / Reissue Certificate
  - Retrieve Trust Chain
- Certificate Checking
- Domain Claims Workflow
- IP Claims Workflow
- request.json Explained
- reissue.json Explained
- PEM Formatting Requirements
- Error Handling and Debugging
- Operational Best Practices



# Overview

This CLI wraps GlobalSign Atlas API into an interactive workflow while preserving:

- Full API transparency (raw responses are shown)
- Correct HTTP semantics
- Proper certificate lifecycle handling

It is designed to **mirror real-world certificate operations**, not abstract them away.



# Architecture and Design Philosophy

This tool follows these principles:

### 1. No Hidden Logic
Every API call maps directly to GlobalSign Atlas endpoints.

### 2. Operator Control
Users explicitly choose:
- Automated flows
- Manual API-level operations

### 3. Stateless Execution
Each action:
- Authenticates
- Executes
- Displays result

No hidden caching or state mutation.

### 4. Safe Failure Handling
Failures:
- Do not crash the CLI
- Return to menu safely
- Show full API response



# Prerequisites

- Bash (Linux / macOS / WSL)
- `curl`
- `jq`
- `openssl`

You must have:

- Atlas API credentials (API Key & Secret)
- mTLS certificate (`.pem`)
- mTLS Private key (`.key`)



# Configuration

The script will prompt for:

- `BASE_URL`
- `API_KEY`
- `API_SECRET`
- `MTLS_CERT`
- `MTLS_KEY`


```bash
BASE_URL=https://emea.api.hvca.globalsign.com:8443/v2
````

You can specify the paths for your mTLS certificate and private key directly in the code. If these are not predefined, the script will prompt you to enter them at runtime.

For the API credentials (`API_KEY` and `API_SECRET`), you have two options:

* Export them as environment variables before running the tool, or
* Provide them interactively when prompted

Example

```bash
export API_KEY=''
export API_SECRET='' 
./globalsign_atlas_api_cli.sh
```

Setting these values as environment variables ensures they are available to the script at runtime, as exported variables are inherited by child processes.

This approach helps keep sensitive information out of the source code, reducing the risk of accidental exposure (for example, through version control). It also promotes better separation between configuration and code, making the tool easier to manage across different environments. 




# Usage Overview

Run the script:

You need to run it like a program so `chmod +x` is required.

```bash
chmod +x globalsign_atlas_api_cli.sh
./globalsign_atlas_api_cli.sh
```

Main menu:

```
1) Issue certificates
2) Check certificates
3) Claim domain
4) Claim IP
5) Exit
```



# Issue Certificates

## 1) Auto Issuance

This is a **fully automated workflow**:

1. Reads `request.json`
2. Submits certificate request
3. Extracts certificate ID
4. Polls until issued
5. Saves certificate
6. Retrieves trust chain
7. Builds fullchain

### Output artifacts:

```
output/
├── <serial>.crt
├── <serial>.json
├── chain.pem
├── fullchain.pem
```

Use this for:

* Automation pipelines
* Production issuance
* CI/CD workflows


## 2) Request a New Certificate

Endpoint:

```
POST /v2/certificates
```

This:

* Sends `request.json`
* Returns immediate API response
* Does NOT poll

Use this when:

* You want raw API behavior
* You manage polling externally



## 3) Get Certificate by ID

Endpoint:

```
GET /v2/certificates/{certificate}
```

Requires:

* Certificate ID (serial)

Returns:

* Status
* Certificate (if issued)
* Metadata


## 4) Revoke Certificate

Endpoint:

```
PATCH /v2/certificates/{certificate}
```

### Required field:

```json
{
  "revocation_reason": "keyCompromise"
}
```

### Supported reasons:

* unspecified
* keyCompromise
* affiliationChanged
* cessationOfOperation
* superseded

### Special Case: keyCompromise

May include:

* `revocation_time`
* `key_compromise_attestation`



## 5) Rekey / Reissue Certificate

Endpoint:

```
POST /v2/certificates/{certificate}/rekey
```

### Minimum payload:

```json
{
  "public_key": "-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----"
}
```

### Optional:

```json
{
  "signature": {
    "algorithm": "RSA-PSS",
    "hash_algorithm": "SHA-256"
  },
  "public_key": "-----BEGIN PUBLIC KEY-----\\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAwU2imlDf02o8DPveLN73\\nwbrQKScch9AnkMuQqBxxq5YBUAvPDXYeeA8tkgk+N2Q5FNL/BXI0m1QTlq8FbdAQ\\nKkpi93vimsymHpkBFTxZSqMcI55vyLanjfMOnZ7Xbgq0hhub/K6FZpFCJ2oqoLwr\\nY5hBYAGYQco5qw4nbR9Mpeu41QGQzrGjYIKNOVgXh/m41FOGDsQntecaLAluTg+E\\n/Qmb8U7XZVBn3/DPyiXrfobuBlnmEbPjQ95LAvRLzcHzWY0YB1dfGzbcK1PaGRLE\\nod2C1QCGK+YWzeUWEyHqgNEncQDMFYFKUd1IhR6OSmVB1ukXa0y8eZBVWsoxXr2X\\nlQIDAQAB\\n-----END PUBLIC KEY-----",
  "public_key_signature": "MIGIAkIA6CotF+LAs2MeymHWul2KuatxcqWDpvhgaEJCI+joyj7p9XEUyH5pBTJ2VqvO0hKYEm+dZl8KKD7ISHWz8Vfb9cECQgFwaB7u/5cw4kT5gv9BPTlxCSiZRlRPVbTbYWl/BeaWAwrt3oEqDuHXOwIQscj/887bBEN/SnYGpKkKe/qdKEd0gw=="
}
```

### Important notes:

* Only `public key` is required for reissuance
* These are not required:

  * `"signature":""`
  * `"public_key_signature":""`



## 6) Retrieve Trust Chain

Endpoint:

```
GET /v2/trustchain
```

Returns:

* CA chain
* PEM formatted

Used to build:

```
fullchain.pem = certificate + chain.pem
```


# Certificate Checking

Includes:

* Validation policy
* Issued count
* Revoked count
* Issued list
* Revoked list
* Expiring list
* Issuance quota

### Note:

Stats endpoints are time-based.

Default windows may return:

```json
[]
```


This behavior is expected when no activity exists. Additionally, any endpoint under `/stats/` will return an empty array (`[]`) unless the required query parameters are provided.

Be sure to include the following query parameters when making requests (already included in this tool):

* `page` and `per_page` for pagination
* `from` and `to` to define the time range

According to the official documentation, the maximum supported time window is 30 days. If no time range is specified, the default value is the last 10 minutes from the current time.



# Domain Claims Workflow

## Required Flow

1. Claim domain
2. Retrieve claim list
3. Get claim ID
4. Perform validation

### Validation Methods:

* DNS
* HTTP
* Email


## Key Concept

Atlas operates on **Claim IDs**, not raw domains.

You MUST:

1. Claim
2. Retrieve ID
3. Use ID for validation or to query the status


# IP Claims Workflow

Same pattern as domain:

1. Claim IP
2. Retrieve claims
3. Extract claim ID
4. Validate (HTTP)


# request.json

This file defines:

* Certificate subject
* SANs
* Validation type
* Product configuration

It MUST align with:

* Your Atlas validation policy

Example structure:

```json
{
"validity": {
"secondsmin": 3600,
"secondsmax": 86400,
"not_before_negative_skew": 120,
"not_before_positive_skew": 3600,
"issuer_expiry": 1735732800
},
"subject_dn": {
"common_name": {
"presence": "REQUIRED",
"format": "^[A-Za-z][A-Za-z -]+$"
},
"surname": {
"presence": "REQUIRED",
"format": "^[A-Za-z][A-Za-z -]+$"
},
"given_name": {
"presence": "REQUIRED",
"format": "^[A-Za-z][A-Za-z -]+$"
},
"organization": {
"presence": "STATIC",
"format": "GMO GlobalSign"
},
"organizational_unit": {
"static": false,
"list": [
"^[A-Za-z][A-Za-z \\-]+$"
],
"mincount": 1,
"maxcount": 3
},
"organization_identifier": {
"presence": "OPTIONAL",
"format": "^[A-Za-z][A-Za-z \\-]+$"
},
"country": {
"presence": "STATIC",
"format": "GB"
},
"state": {
"presence": "OPTIONAL",
"format": "^[A-Za-z][A-Za-z \\-]+$"
},
"locality": {
"presence": "OPTIONAL",
"format": "^[A-Za-z][A-Za-z \\-]+$"
},
"street_address": {
"presence": "OPTIONAL",
"format": "^[A-Za-z0-9][A-Za-z0-9 \\-]+$"
},
"postal_code": {
"presence": "OPTIONAL",
"format": "^[A-Za-z][A-Za-z -]+$"
},
"email": {
"presence": "FORBIDDEN",
"format": "^\\w[-._\\w]*\\w@\\w[-._\\w]*\\w.\\w{2,3}"
},
"pseudonym": {
"presence": "OPTIONAL",
"format": "^[A-Za-z][A-Za-z]+$"
},
"jurisdiction_of_incorporation_locality_name": {
"presence": "OPTIONAL",
"format": "^[A-Za-z \\-]*$"
},
"jurisdiction_of_incorporation_state_or_province_name": {
"presence": "OPTIONAL",
"format": "^[A-Za-z \\-]*$"
},
"jurisdiction_of_incorporation_country_name": {
"presence": "FORBIDDEN",
"format": "^[A-Za-z \\-]*$"
},
"business_category": {
"presence": "FORBIDDEN",
"format": "^[A-Za-z \\-]*$"
},
"serial_number": {
"presence": "OPTIONAL",
"format": "^[A-Za-z \\-]*$"
},
"extra_attributes": {
"1.3.6.1.5.5.7.48.1.5": {
"static": true,
"value_type": "PRINTABLESTRING",
"value_format": "static attribute",
"mincount": 1,
"maxcount": 1
},
"1.3.6.1.5.5.7.48.1.6": {
"static": false,
"value_type": "UTF8STRING",
"value_format": "^[A-Za-z \\\\-]*$",
"mincount": 0,
"maxcount": 3
}
}
},
"san": {
"dns_names": {
"static": false,
"list": [],
"mincount": 0,
"maxcount": 0
},
"emails": {
"static": false,
"list": [
"^\\w[-._\\w]*\\w@\\w[-._\\w]*\\w.\\w{2,3}$"
],
"mincount": 0,
"maxcount": 1
},
"ip_addresses": {
"static": false,
"list": [],
"mincount": 0,
"maxcount": 0
},
"uris": {
"static": false,
"list": [],
"mincount": 0,
"maxcount": 0
},
"other_names": {
"1.3.6.1.5.5.7.48.1.5": {
"static": false,
"value_type": "UTF8STRING",
"value_format": "^[A-Za-z.-]@demo.globalsign.com",
"mincount": 0,
"maxcount": 1
}
}
},
"subject_da": {
"gender": {
"presence": "OPTIONAL",
"format": "^[MmFf]$"
},
"date_of_birth": "OPTIONAL",
"place_of_birth": {
"presence": "OPTIONAL",
"format": "^[A-Za-z \\\\-]*$"
},
"country_of_citizenship": {
"static": true,
"list": [
"GB",
"US"
],
"mincount": 2,
"maxcount": 2
},
"country_of_residence": {
"static": false,
"list": [
"GB",
"US"
],
"mincount": 0,
"maxcount": 2
},
"extra_attributes": {
"1.3.6.1.5.5.7.48.1.5": {
"static": true,
"value_type": "PRINTABLESTRING",
"value_format": "static attribute",
"mincount": 1,
"maxcount": 1
},
"1.3.6.1.5.5.7.48.1.6": {
"static": false,
"value_type": "UTF8STRING",
"value_format": "^[A-Za-z \\\\-]*$",
"mincount": 1,
"maxcount": 3
}
}
},
"signature": {
"algorithm": {
"presence": "STATIC",
"list": [
"RSA-PSS"
]
},
"hash_algorithm": {
"presence": "REQUIRED",
"list": [
"SHA-256",
"SHA-512"
]
}
},
"public_key": {
"key_type": "RSA",
"allowed_lengths": [
2048,
4096
],
"key_format": "PKCS8"
},
"public_key_signature": "REQUIRED"
}
```



# reissue.json

Used for rekey/reissue.

### Minimum:

```json
{
  "public_key": "-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----"
}
```

### Optional:

```json
{
  "signature": {
    "algorithm": "RSA-PSS",
    "hash_algorithm": "SHA-256"
  },
  "public_key": "-----BEGIN PUBLIC KEY-----\\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAwU2imlDf02o8DPveLN73\\nwbrQKScch9AnkMuQqBxxq5YBUAvPDXYeeA8tkgk+N2Q5FNL/BXI0m1QTlq8FbdAQ\\nKkpi93vimsymHpkBFTxZSqMcI55vyLanjfMOnZ7Xbgq0hhub/K6FZpFCJ2oqoLwr\\nY5hBYAGYQco5qw4nbR9Mpeu41QGQzrGjYIKNOVgXh/m41FOGDsQntecaLAluTg+E\\n/Qmb8U7XZVBn3/DPyiXrfobuBlnmEbPjQ95LAvRLzcHzWY0YB1dfGzbcK1PaGRLE\\nod2C1QCGK+YWzeUWEyHqgNEncQDMFYFKUd1IhR6OSmVB1ukXa0y8eZBVWsoxXr2X\\nlQIDAQAB\\n-----END PUBLIC KEY-----",
  "public_key_signature": "MIGIAkIA6CotF+LAs2MeymHWul2KuatxcqWDpvhgaEJCI+joyj7p9XEUyH5pBTJ2VqvO0hKYEm+dZl8KKD7ISHWz8Vfb9cECQgFwaB7u/5cw4kT5gv9BPTlxCSiZRlRPVbTbYWl/BeaWAwrt3oEqDuHXOwIQscj/887bBEN/SnYGpKkKe/qdKEd0gw=="
}
```


# Error Handling and Debugging

## HTTP 400

Invalid payload:

* Wrong field names
* Bad formatting

## HTTP 415

Bad Content-Type:

```
application/json;charset=utf-8
```

## HTTP 422

Invalid field usage:

* Static fields modified
* Unsupported combinations


For more detailed information, please refer to the official GlobalSign API documentation:
[GlobalSign HVCA API Documentation](https://api.docs.globalsign.com/?utm_source=christnd.codes)

The documentation provides comprehensive guidance on available endpoints, required parameters, authentication methods, and usage examples for the Atlas API. [api.docs.globalsign.com][1]

# Operational Best Practices

* Always validate CSR/public key before submission
* Use Auto Issuance for production
* Use manual flows for debugging
* Store outputs securely
* Rotate keys regularly
* Monitor revocation events


# Summary

This CLI provides:

* Full certificate lifecycle management
* Clear operational workflows
* Safe error handling
* Direct Atlas API mapping

It is built for:

* DevOps teams
* Security engineers
* Platform operators


[1]: https://api.docs.globalsign.com/?utm_source=christnd.codes "GlobalSign API Docs"

# License

Project Use

```


