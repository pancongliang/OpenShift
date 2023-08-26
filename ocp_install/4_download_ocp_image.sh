#!/bin/bash

oc adm -a ${LOCAL_SECRET_JSON} release mirror \
  --from=quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE}-${ARCHITECTURE} \
  --to=${LREGISTRY_HOSTNAME}:5000/${LOCAL_REPOSITORY} \
  --to-release-image=${LREGISTRY_HOSTNAME}:5000/${LOCAL_REPOSITORY}:${OCP_RELEASE}-${ARCHITECTURE} 

sudo sleep 60

curl -u $REGISTRY_ID:$REGISTRY_PW -k https://${REGISTRY_HOSTNAME}:5000/v2/_catalog
