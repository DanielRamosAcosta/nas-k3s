build-databases:
  tk export dist/databases environments/databases --merge-strategy replace-envs

build-media:
  tk export dist/media environments/media --merge-strategy replace-envs

build-auth:
  tk export dist/auth environments/auth --merge-strategy replace-envs

build-monitoring:
  tk export dist/monitoring environments/monitoring --merge-strategy replace-envs

build-arr:
  tk export dist/arr environments/arr --merge-strategy replace-envs

encrypt-secrets:
  age --encrypt --recipients-file ../id_dani.pub --output ./lib/secrets.json.age ./lib/secrets.json

decrypt-secrets:
  age --decrypt --identity ~/.ssh/id_ed25519 --output ./lib/secrets.json ./lib/secrets.json.age

deploy:
  tk apply environments/databases

deploy-arr:
  tk apply environments/arr
