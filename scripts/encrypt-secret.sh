#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 3 ]; then
  echo "Usage: echo 'secret-value' | $0 <namespace> <secret-name> <key>" >&2
  exit 1
fi

namespace="$1"
secret_name="$2"
key="$3"

if [ -t 0 ]; then
  echo "Error: no input on stdin. Pipe the secret value." >&2
  echo "Example: echo -n 'my-secret' | $0 $namespace $secret_name $key" >&2
  exit 1
fi

value="$(cat)"

echo -n "$value" | kubeseal --raw \
  --namespace "$namespace" \
  --name "$secret_name" \
  --controller-name sealed-secrets \
  --controller-namespace kube-system \
  --from-file=/dev/stdin
