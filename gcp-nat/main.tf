resource "google_compute_network" "main" {
  name                    = var.network_name
  auto_create_subnetworks = false
}


# Public Subnet
resource "google_compute_subnetwork" "public" {
  name          = "${var.network_name}-public-subnet"
  ip_cidr_range = var.public_subnet_cidr
  region        = var.region
  network       = google_compute_network.main.id

  # Public subnet doesn't need Private Google Access
  private_ip_google_access = false
}

# Private Subnet (with Private Google Access)
resource "google_compute_subnetwork" "private" {
  name          = "${var.network_name}-private-subnet"
  ip_cidr_range = var.private_subnet_cidr
  region        = var.region
  network       = google_compute_network.main.id

  # This allows private VMs / GKE nodes to access Google APIs
  private_ip_google_access = true
}


# # Cloud Router
resource "google_compute_router" "router" {
  name    = "${var.network_name}-router"
  region  = var.region
  network = google_compute_network.main.id
}

# Cloud NAT
resource "google_compute_router_nat" "nat" {
  name                               = "${var.network_name}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.private.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Firewall Rules
# Allow SSH from the internet to bastion host (public VM)
resource "google_compute_firewall" "allow_ssh_to_bastion" {
  name    = "${var.network_name}-allow-ssh-to-bastion"
  network = google_compute_network.main.name

  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # 🔥 For real environments, restrict this to your IP, not 0.0.0.0/0
  source_ranges = ["0.0.0.0/0"]

  target_tags = ["bastion"]
}

# Allow SSH from public subnet to private subnet
resource "google_compute_firewall" "allow_ssh_from_public_to_private" {
  name    = "${var.network_name}-allow-ssh-public-to-private"
  network = google_compute_network.main.name

  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Source is the public subnet IP CIDR
  source_ranges = [var.public_subnet_cidr]

  target_tags = ["private-vm"]
}


# Bastion VM (Public Subnet)
resource "google_compute_instance" "bastion" {
  name         = "bastion-host"
  machine_type = "e2-micro"
  zone         = var.zone
  tags         = ["bastion"]

  boot_disk {
    initialize_params {
      image = "projects/debian-cloud/global/images/family/debian-11"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.public.id

    # External IP so we can SSH from the internet
    access_config {}
  }

  # metadata = {
  #   ssh-keys = "user:${file("~/.ssh/id_rsa.pub")}"
  # }
}


# Private VM (Private Subnet)
resource "google_compute_instance" "private_vm" {
  name         = "private-vm"
  machine_type = "e2-micro"
  zone         = var.zone
  tags         = ["private-vm"]

  boot_disk {
    initialize_params {
      image = "projects/debian-cloud/global/images/family/debian-11"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private.id

    # No external IP -> private only
    # Do NOT add access_config here
  }

  # metadata = {
  #  ssh-keys = "user:${file("~/.ssh/id_rsa.pub")}"
  # }
}
