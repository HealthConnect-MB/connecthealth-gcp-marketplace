# ConnectHealth on Google Cloud

ConnectHealth is an AI-assisted EHR integration platform for FHIR and HL7. It connects
electronic health record systems through configurable, auditable workflows.

This repository contains the **deployment assets** for the Google Cloud Marketplace
listing: the Terraform blueprint that provisions the infrastructure, and the parameter
schema used by the Marketplace deployment form. The application itself is distributed
as a container image from Artifact Registry.

## How deployment works

ConnectHealth deploys in two stages, because the two halves are managed by different
systems:

1. **Infrastructure** — a Terraform blueprint, deployed with Infrastructure Manager,
   creates the VPC, GKE Autopilot cluster, KMS key, Firestore database, Cloud Storage
   buckets, Pub/Sub topic, service account, static IP and Cloud Armor policy in *your*
   project.
2. **Application** — deployed from Cloud Marketplace into the cluster created in
   stage 1. You supply the names of the resources from stage 1 on the deployment form.

Stage 1 must complete before stage 2 begins.

## Prerequisites

- A Google Cloud project with billing enabled
- A domain you control, for the application's hostname
- Permission to create the resources listed above
- For CLI deployment: `gcloud`, `kubectl`, `helm` and
  [`mpdev`](https://github.com/GoogleCloudPlatform/marketplace-k8s-app-tools)

## Stage 1 — Deploy the infrastructure

Deploy this blueprint with Infrastructure Manager, supplying at minimum your project ID
and the domain the application will be served on:

```bash
gcloud infra-manager deployments apply \
  projects/PROJECT_ID/locations/us-east1/deployments/connecthealth \
  --service-account=projects/PROJECT_ID/serviceAccounts/SA_EMAIL \
  --local-source="." \
  --input-values=project_id=PROJECT_ID,app_domain=connecthealth.example.com
```

When it completes, read the outputs — every value the Marketplace form asks for comes
from here:

```bash
gcloud infra-manager deployments describe \
  projects/PROJECT_ID/locations/us-east1/deployments/connecthealth \
  --format="value(latestRevision)"
```

### Point DNS at the load balancer

Create an `A` record for your domain pointing at the `ingress_static_ip_address`
output **before** deploying the application. Google will not issue the managed TLS
certificate until the domain already resolves, and a certificate that fails this check
does not retry on its own.

## Stage 2 — Deploy the application

### From the Cloud Console

Find ConnectHealth on Google Cloud Marketplace, click **Deploy**, select the cluster
created in stage 1, and complete the form using the mapping below.

### From the command line

```bash
export DEPLOYER=us-docker.pkg.dev/mindbowser-public/connecthealth/deployer:1.0

mpdev install \
  --deployer="$DEPLOYER" \
  --parameters='{
    "name": "connecthealth",
    "namespace": "default",
    "gcpProjectId": "PROJECT_ID",
    "appDomain": "connecthealth.example.com",
    "serviceAccount.gcpServiceAccount": "SERVICE_ACCOUNT_EMAIL",
    "ingress.staticIpName": "STATIC_IP_NAME",
    "filestore.storageClass.network": "VPC_NETWORK_NAME",
    "filestore.storageClass.reservedIpRange": "FILESTORE_RANGE_NAME",
    "config.gcsBucketName": "FLOWS_BUCKET",
    "config.firestoreContextDatabase": "FIRESTORE_DATABASE",
    "config.pubsubTopicId": "PUBSUB_TOPIC",
    "config.auditLog.bucket": "AUDIT_LOG_BUCKET",
    "config.applicationLog.bucket": "APPLICATION_LOG_BUCKET",
    "config.secretBasePrefix": "ehrconnect/prod/"
  }'
```

## Deployment parameters

Each form field maps to one output of the stage 1 blueprint.

| Marketplace field | Helm value | Source | Required |
|---|---|---|---|
| Google Cloud project ID | `gcpProjectId` | the project you deployed the blueprint into | Yes |
| Application service account | `serviceAccount.gcpServiceAccount` | `gcp_service_account_email` | Yes |
| Application domain | `appDomain` | `app_domain` | Yes |
| Static IP name | `ingress.staticIpName` | `ingress_static_ip_name` | Yes |
| Cloud Armor policy name | `cloudArmor.securityPolicyName` | `cloud_armor_policy_name` | No |
| VPC network name | `filestore.storageClass.network` | `vpc_network_name` | Yes |
| Filestore reserved IP range name | `filestore.storageClass.reservedIpRange` | `filestore_reserved_range_name` | Yes |
| Flows bucket | `config.gcsBucketName` | `flows_bucket_name` | Yes |
| Firestore database | `config.firestoreContextDatabase` | `firestore_database_name` | Yes |
| Pub/Sub topic | `config.pubsubTopicId` | `container_sync_topic_name` | Yes |
| Audit log bucket | `config.auditLog.bucket` | `app_audit_log_bucket` | Yes |
| Application log bucket | `config.applicationLog.bucket` | `app_operational_log_bucket` | Yes |
| Log bucket region | `config.auditLog.location` | `app_log_bucket_location` | No |
| Application log bucket region | `config.applicationLog.location` | `app_log_bucket_location` | No |
| Secret Manager prefix | `config.secretBasePrefix` | choose a value unique to this deployment | Yes |
The token signing key, workflow credential key and initial administrator password are
**generated by Marketplace** at install time and are not entered on the form.

> **`config.secretBasePrefix` cannot be changed after installation.** It namespaces every
> secret the application creates in Secret Manager — the administrator login, signing
> keys and integration credentials. Changing it later strands all of them. Two
> deployments sharing a prefix also share their administrator account.

## After installation

The Google-managed TLS certificate takes 15–60 minutes to provision, and cannot begin
until the Ingress exists. Until it reports `Active`, HTTPS will fail:

```bash
kubectl get managedcertificate -n NAMESPACE \
  -o jsonpath='{.items[0].status.certificateStatus}'
```

Sign in at `https://YOUR_DOMAIN` as `administrator`, using the initial password shown on
the Marketplace deployment page, and change it immediately.

## Storage note

The application uses a shared `ReadWriteMany` volume provisioned by the Filestore CSI
driver. It is created on first mount and is **not** removed when the cluster is deleted,
because Kubernetes does not delete volume contents on cluster teardown. Delete the
Helm release before deleting the cluster, or remove the Filestore instance manually.

## Support

- Documentation: https://www.mindbowser.com
- Issues with this deployment: open an issue on this repository
