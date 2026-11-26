variable "project_id" {
  description = "GCP project ID that will host the n8n infrastructure."
  type        = string
}

variable "region" {
  description = "Default region for regional resources (state bucket). Must be one of GCP's Compute Engine Always Free e2-micro regions (us-west1/us-central1/us-east1) to keep the VM itself free."
  type        = string
  default     = "us-west1"
}

variable "github_repo" {
  description = "GitHub repository allowed to assume the Terraform CI service account, in \"owner/repo\" form."
  type        = string
}

variable "security_log_retention_days" {
  description = "Retention (days) of the dedicated security-logs bucket (access logs, host journal, Data Access audit logs). _Default's 30 days is too short to investigate an incident noticed late."
  type        = number
  default     = 90
}

variable "alert_email" {
  description = "Address security alerts are emailed to. Sensitive: this repository and its plan output are public."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be an email address (TF_VAR_alert_email, or the ALERT_EMAIL repository secret in CI)."
  }
}

variable "operator_email" {
  description = "Google account of the human operator: excluded from the secret-access alert, and its OS Login user from the SSH alert. Sensitive for the same reason as alert_email."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+$", var.operator_email))
    error_message = "operator_email must be an email address (TF_VAR_operator_email, or the OPERATOR_EMAIL repository secret in CI)."
  }
}

variable "n8n_login_failure_threshold" {
  description = "Number of failed n8n logins within 10 minutes that raises an alert."
  type        = number
  default     = 5
}
