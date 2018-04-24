#!/usr/bin/env bash

set +x

{
  echo "-----BEGIN PGP PRIVATE KEY BLOCK-----"
  echo ""
  echo "${GPG_SECRET}" | fold -w64
  echo "-----END PGP PRIVATE KEY BLOCK-----"
} | gpg --import || true

gpg -K
gpg -k

passphrase=$(mktemp /dev/shm/pass.XXXXXX)
echo "${GPG_PASS}" > "${passphrase}"
