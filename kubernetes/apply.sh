#!/usr/bin/env bash

cd $(dirname $0)

for template in *.yml; do
	envsubst < $template > out/$template
done

kubectl apply -f out/
