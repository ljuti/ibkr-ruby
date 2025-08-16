# Cryptographic Certificates Directory

This directory should contain your RSA private keys and Diffie-Hellman parameters required for IBKR OAuth authentication.

## Required Files

Place the following files in this directory:

```
config/certs/
├── private_encryption.pem    # RSA private key for encryption operations
├── private_signature.pem     # RSA private key for signature generation  
└── dhparam.pem              # Diffie-Hellman parameters for key exchange
```

## Getting These Files

### From IBKR Self Service Portal

1. **Login** to the IBKR Self Service Portal (provided during onboarding)
2. **Generate** or download your:
   - Consumer Key (goes in config file)
   - Access Token (goes in config file) 
   - Access Token Secret (goes in config file)
   - Private Encryption Key → save as `private_encryption.pem`
   - Private Signature Key → save as `private_signature.pem`
   - DH Parameters → save as `dhparam.pem`

### File Format

All files should be in PEM format:

```
-----BEGIN RSA PRIVATE KEY-----
[Base64 encoded key content]
-----END RSA PRIVATE KEY-----
```

```
-----BEGIN DH PARAMETERS-----
[Base64 encoded DH parameters]
-----END DH PARAMETERS-----
```

## Security Notes

- ⚠️  **These files contain sensitive cryptographic material**
- ✅ Files in this directory are automatically excluded from git (see `.gitignore`)
- ✅ Keep backups in a secure location
- ✅ Use appropriate file permissions (600 or 400)
- ❌ Never commit these files to version control
- ❌ Never share these files or include them in logs

## File Permissions

Set appropriate permissions for security:

```bash
chmod 600 config/certs/*.pem
```

## Testing

You can verify the files are properly formatted:

```bash
# Test RSA private keys
openssl rsa -in config/certs/private_encryption.pem -check -noout
openssl rsa -in config/certs/private_signature.pem -check -noout

# Test DH parameters  
openssl dhparam -in config/certs/dhparam.pem -check -noout
```

## Development vs Production

- **Development**: Use sandbox credentials and test certificates
- **Production**: Use production credentials with live trading certificates
- Keep separate sets of files for each environment if needed

## Troubleshooting

If you get configuration errors:

1. **Check file paths** in `config/ibkr.local.yml` are correct
2. **Verify file permissions** allow reading
3. **Validate file format** using OpenSSL commands above
4. **Ensure files exist** and are not empty
5. **Check file encoding** (should be ASCII/UTF-8, not binary)

## Alternative: Environment Variables

For containerized deployments, you can use environment variables instead:

```bash
export IBKR_PRIVATE_KEY_CONTENT="$(cat config/certs/private_encryption.pem)"
export IBKR_SIGNATURE_KEY_CONTENT="$(cat config/certs/private_signature.pem)"  
export IBKR_DH_PARAM_CONTENT="$(cat config/certs/dhparam.pem)"
```

The configuration will automatically use content from environment variables if file paths are not available.