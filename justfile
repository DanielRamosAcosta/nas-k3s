encrypt-secrets:
  age --encrypt --recipients-file ./id_dani.pub --output ./lib/secrets.json.age ./lib/secrets.json

decrypt-secrets:
  age --decrypt --identity ~/.ssh/id_ed25519 --output ./lib/secrets.json ./lib/secrets.json.age
