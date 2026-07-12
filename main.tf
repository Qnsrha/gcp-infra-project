provider "google" {
    project = "infra-project-501705"
    region = "asia-northeast3"
}

resource "google_compute_network" "vpc_network" {
    name = "vpc"
    auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "private_subnet" {
    name = "private-subnet"
    ip_cidr_range = "10.0.1.0/24"
    region = "asia-northeast3"
    network = google_compute_network.vpc_network.id
}

resource "google_compute_router" "router" {
    name = "router1"
    region = "asia-northeast3"
    network = google_compute_network.vpc_network.id
}

resource "google_compute_router_nat" "nat" {
    name = "nat1"
    router = google_compute_router.router.name
    region = google_compute_router.router.region
    nat_ip_allocate_option = "AUTO_ONLY"
    source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

    subnetwork {
        name = google_compute_subnetwork.private_subnet.id
        source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
    }
}

resource "google_compute_firewall" "allow_iap_ssh" {
    name = "allow-iap-ssh"
    network = google_compute_network.vpc_network.id
    
    allow {
        protocol = "tcp"
        ports = ["22"]
    }

    source_ranges = ["35.235.240.0/20"]
}

resource "google_project_service" "container" {
    service = "container.googleapis.com"
    disable_on_destroy = false
}

resource "google_container_cluster" "primary" {
    name = "gke-cluster"
    location = "asia-northeast3-a"
    deletion_protection = false

    network = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.private_subnet.id

    remove_default_node_pool = true
    initial_node_count = 1

    private_cluster_config {
        enable_private_nodes = true
        enable_private_endpoint = false
    }

    depends_on = [google_project_service.container]
}

resource "google_container_node_pool" "primary_nodes" {
    name = "node-pool"
    location = "asia-northeast3-a"
    cluster = google_container_cluster.primary.name
    node_count = 1

    node_config {
        preemptible = true
        machine_type = "e2-medium"

        labels = {
            env = "project"
        }

        oauth_scopes = [
            "https://www.googleapis.com/auth/cloud-platform"
        ]
    }

}

resource "google_project_service" "artifactregistry" {
    service = "artifactregistry.googleapis.com"
    disable_on_destroy = false
}

resource "google_artifact_registry_repository" "project_repo" {
    location = "asia-northeast3"
    repository_id = "project-docker-repo"
    description = "Doker repository for project applications"
    format = "DOCKER"

    depends_on = [google_project_service.artifactregistry]
}

resource "google_project_service" "iamcredentials" {
    service = "iamcredentials.googleapis.com"
    disable_on_destroy = false
}

resource "google_iam_workload_identity_pool" "github_pool" {
    workload_identity_pool_id = "github-actions-pool"
    display_name = "GitHub Actions Pool"
    description = "Identity pool for GitHub Actions automation"
    depends_on = [google_project_service.iamcredentials]
}

resource "google_iam_workload_identity_pool_provider" "github_provider" {
    workload_identity_pool_id = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
    workload_identity_pool_provider_id = "github-provider"
    display_name = "GitHub Provider"

    attribute_mapping = {
        "google.subject" = "assertion.sub"
        "attribute.repository" = "assertion.repository"
    }
    attribute_condition = "assertion.repository != ''"

    oidc {
        issuer_uri = "https://token.actions.githubusercontent.com"
    }
}

resource "google_service_account" "github_deployer" {
    account_id = "github-deployer"
    display_name = "gitHub Actions Deployer"
}

resource "google_project_iam_member" "repo_admin" {
    project = "infra-project-501705"
    role = "roles/artifactregistry.writer"
    member = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "google_project_iam_member" "gke_developer" {
    project = "infra-project-501705"
    role = "roles/container.developer"
    member = "serviceAccount:${google_service_account.github_deployer.email}"
}

resource "google_service_account_iam_member" "github_oidc_binding" {
    service_account_id = google_service_account.github_deployer.name
    role = "roles/iam.workloadIdentityUser"
    member = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/Qnsrha/gcp-infra-project"
}

output "workload_identity_provider" {
    value = google_iam_workload_identity_pool_provider.github_provider.name
}

output "service_account_email" {
    value = google_service_account.github_deployer.email
}