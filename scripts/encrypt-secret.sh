#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage:" >&2
  echo "  Strict (bound to namespace+name):" >&2
  echo "    echo 'secret-value' | $0 <namespace> <secret-name>" >&2
  echo "  Cluster-wide (reusable across namespaces):" >&2
  echo "    echo 'secret-value' | $0 --cluster-wide" >&2
  exit 1
}

if [ $# -eq 0 ]; then
  usage
fi

if [ -t 0 ]; then
  echo "Error: no input on stdin. Pipe the secret value." >&2
  usage
fi

value="$(cat)"

if [ "$1" = "--cluster-wide" ]; then
  echo -n "$value" | kubeseal --raw \
    --scope cluster-wide \
    --controller-name sealed-secrets \
    --controller-namespace kube-system \
    --from-file=/dev/stdin
elif [ $# -eq 2 ]; then
  namespace="$1"
  secret_name="$2"
  echo -n "$value" | kubeseal --raw \
    --scope strict \
    --namespace "$namespace" \
    --name "$secret_name" \
    --controller-name sealed-secrets \
    --controller-namespace kube-system \
    --from-file=/dev/stdin
else
  usage
fi
