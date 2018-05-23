#!/bin/sh
set -e

function get_region {
  local region=$REGION
  if [[ "$region" == "" ]]; then
    region=$(aws $(get_profile) configure get region)
  fi
  if [[ "$region" == "" ]]; then
    region=$(wget -q -O- ${AWS_IAM} | grep 'region' |cut -d'"' -f4)
  fi
  echo $region
}

function get_credentials {
  local auth_token=$($AWS_CMD ecr get-authorization-token --output text | awk '{print $2}')
  if [[ "$auth_token" == "" ]]; then
    >&2 echo "could not get authorization token"
    return 1
  fi
  echo $auth_token
}

function get_resolver {
  local resolver=$RESOLVER
  if [[ "$resolver" == "host" ]]; then
    echo $(cat /etc/resolv.conf | grep "nameserver" | awk '{print $2}' | tr '\n' ' ')
  else
    echo ${RESOLVER:-8.8.8.8 8.8.4.4}
  fi
}

function update_conf {
  echo "updating the config"
  template_file=/etc/nginx/nginx.conf.tmpl
  nginx_cfg=/etc/nginx/nginx.conf
    
  cat "$template_file" | envsubst '$RESOLVER,$REGISTRY_URL,$CREDENTIALS,$USER' > "$nginx_cfg"
}

function renew_loop {
 while sleep ${RENEW_TOKEN:-6h}
 do
   update_conf
   nginx -s reload
 done
}

function get_profile {
  if [[ "$PROFILE" != "" ]]; then
    echo "--profile $PROFILE"
  fi
}

AWS_IAM='http://169.254.169.254/latest/dynamic/instance-identity/document'
AWS_FOLDER='/root/.aws'
REGION=$(get_region)
AWS_CMD="aws $(get_profile) --region $REGION"

if [[ "$REGISTRY_URL" == "" ]]; then
  account=$($AWS_CMD sts get-caller-identity --output text | awk '{print $1}')
  REGISTRY_URL="${account}.dkr.ecr.${REGION}.amazonaws.com"
  echo "defaulted to REGISTRY_URL=$REGISTRY_URL"
fi

export CREDENTIALS=$(get_credentials)
export USER="AWS"
export REGISTRY_URL="https://$REGISTRY_URL"
export RESOLVER=$(get_resolver)

if [[ "$CREDENTIALS" == "" ]]; then
  echo "could not get CREDENTIALS giving up"
  exit 1
fi

update_conf
renew_loop "$AWS_CMD" &

exec "$@"
