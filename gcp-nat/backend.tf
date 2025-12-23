terraform {
  backend "gcs" {
    bucket  = "terraform-state-gcp-bucket-02"  # Cloud Storage bucket name
    prefix  = "network/terraform-state"
  }
}
