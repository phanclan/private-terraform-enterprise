#!/bin/bash

set -x
exec > /home/centos/install-tfe.log 2>&1

# Get private and public IPs of the EC2 instance
PRIVATE_IP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)
PRIVATE_DNS=$(curl http://169.254.169.254/latest/meta-data/local-hostname)

if [ "${public_ip}" == "true" ]; then
  PUBLIC_IP=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)
fi

# Write out replicated.conf configuration file
cat > /etc/replicated.conf <<EOF
{
  "DaemonAuthenticationType": "password",
  "DaemonAuthenticationPassword": "${tfe_admin_password}",
  "TlsBootstrapType": "self-signed",
  "ImportSettingsFrom": "/home/centos/tfe-settings.json",
  "LicenseFileLocation": "/home/centos/tfe-license.rli",
  "BypassPreflightChecks": true
}
EOF

# Write out PTFE settings file
cat > /home/centos/tfe-settings.json <<EOF
{
  "hostname": {
    "value": "${hostname}"
  },
  "ca_certs": {
    "value": "${ca_certs}"
  },
  "installation_type": {
    "value": "${installation_type}"
  },
  "production_type": {
    "value": "${production_type}"
  },
  "capacity_concurrency": {
    "value": "${capacity_concurrency}"
  },
  "capacity_memory": {
    "value": "${capacity_memory}"
  },
  "enc_password": {
    "value": "${enc_password}"
  },
  "enable_metrics_collection": {
    "value": "${enable_metrics_collection}"
  },
  "extra_no_proxy": {
    "value": "${extra_no_proxy},$PRIVATE_DNS"
  },
  "pg_dbname": {
    "value": "${pg_dbname}"
  },
  "pg_extra_params": {
    "value": "${pg_extra_params}"
  },
  "pg_netloc": {
    "value": "${pg_netloc}"
  },
  "pg_password": {
    "value": "${pg_password}"
  },
  "pg_user": {
    "value": "${pg_user}"
  },
  "placement": {
    "value": "${placement}"
  },
  "aws_instance_profile": {
    "value": "${aws_instance_profile}"
  },
  "s3_bucket": {
    "value": "${s3_bucket}"
  },
  "s3_region": {
    "value": "${s3_region}"
  },
  "s3_sse": {
    "value": "${s3_sse}"
  },
  "s3_sse_kms_key_id": {
    "value": "${s3_sse_kms_key_id}"
  },
  "vault_path": {
    "value": "${vault_path}"
  },
  "vault_store_snapshot": {
    "value": "${vault_store_snapshot}"
  },
  "custom_image_tag": {
      "value": "${custom_image_tag}"
  },
  "tbw_image": {
      "value": "${tbw_image}"
  }
}
EOF

# Install aws CLI
curl -O https://bootstrap.pypa.io/get-pip.py
python get-pip.py --user
echo "export PATH=/root/.local/bin:$PATH" >> /root/.bash_profile
source /root/.bash_profile
pip install awscli --upgrade --user
aws configure set s3.signature_version s3v4

# Get License File from S3 bucket
aws s3 cp s3://${source_bucket_name}/${tfe_license} /home/centos/tfe-license.rli

# Set SELinux to permissive
setenforce 0

# Install psql client for connecting to PostgreSQL
yum install -y https://download.postgresql.org/pub/repos/yum/9.4/redhat/rhel-7-x86_64/pgdg-redhat94-9.4-3.noarch.rpm
yum install -y postgresql94

# Create the PTFE database schemas
cat > /home/centos/create_schemas.sql <<EOF
CREATE SCHEMA IF NOT EXISTS rails;
CREATE SCHEMA IF NOT EXISTS vault;
CREATE SCHEMA IF NOT EXISTS registry;
EOF

host=$(echo ${pg_netloc} | cut -d ":" -f 1)
port=$(echo ${pg_netloc} | cut -d ":" -f 2)
PGPASSWORD=${pg_password} psql -h $host -p $port -d ${pg_dbname} -U ${pg_user} -f /home/centos/create_schemas.sql

# Install PTFE
curl https://install.terraform.io/ptfe/stable > /home/centos/install.sh
if [ "${public_ip}" == "true" ]; then
  bash /home/centos/install.sh \
    no-proxy \
    private-address=$PRIVATE_IP \
    public-address=$PUBLIC_IP
else
  bash /home/centos/install.sh \
  no-proxy \
  private-address=$PRIVATE_IP \
  public-address=$PRIVATE_IP
fi

# Allow centos user to use docker
# This will not take effect until after you logout and back in
usermod -aG docker centos

# Check status of install
while ! curl -ksfS --connect-timeout 5 https://$PRIVATE_IP/_health_check; do
    sleep 15
done

# Create initial admin user and organization
# if they don't exist yet
if [ "${create_first_user_and_org}" == "true" ]
then
  echo "Creating initial admin user and organization"
  cat > /home/centos/initialuser.json <<EOF
{
  "username": "${initial_admin_username}",
  "email": "${initial_admin_email}",
  "password": "${initial_admin_password}"
}
EOF

  initial_token=$(replicated admin --tty=0 retrieve-iact)
  iact_result=$(curl --header "Content-Type: application/json" --request POST --data @/home/centos/initialuser.json "https://${hostname}/admin/initial-admin-user?token=$${initial_token}")
  api_token=$(echo $iact_result | python -c "import sys, json; print(json.load(sys.stdin)['token'])")
  echo "API Token of initial admin user is: $api_token"

  # Create first PTFE organization
  cat > /home/centos/initialorg.json <<EOF
{
  "data": {
    "type": "organizations",
    "attributes": {
      "name": "${initial_org_name}",
      "email": "${initial_org_email}"
    }
  }
}
EOF

  org_result=$(curl  --header "Authorization: Bearer $api_token" --header "Content-Type: application/vnd.api+json" --request POST --data @/home/centos/initialorg.json "https://${hostname}/api/v2/organizations")
  org_id=$(echo $org_result | python -c "import sys, json; print(json.load(sys.stdin)['data']['id'])")

fi
