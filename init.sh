#!/usr/bin/env sh

set -e -o pipefail

tenant_id=$(printenv TF_VAR_tenant_id)
subscription_id=$(printenv TF_VAR_subscription_id)
client_id=$(printenv TF_VAR_client_id)
client_secret=$(printenv TF_VAR_client_secret)

resource_group_name=
storage_account_name=
key=

terraform init \
    -backend-config="tenant_id=$tenant_id" \
    -backend-config="subscription_id=$subscription_id" \
    -backend-config="client_id=$client_id" \
    -backend-config="client_secret=$client_secret" \
    -backend-config="resource_group_name=$resource_group_name" \
    -backend-config="storage_account_name=$storage_account_name" \
    -backend-config="key=$key" 