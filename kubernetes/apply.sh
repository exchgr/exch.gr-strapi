#!/usr/bin/env bash

set -e

cd $(dirname $0)

for template in *.yml; do
	envsubst < $template > out/$template
done

kubectl apply -f out/
kubectl rollout status deploy/exch-gr-strapi
