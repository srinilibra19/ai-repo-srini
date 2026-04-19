variable "aws_region" {
  description = "AWS region where the Terraform state backend resources are created."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name applied to all resource tags."
  type        = string
  default     = "ContainersWithMiddleware"
}

variable "environment" {
  description = "Environment tag for the bootstrap resources (e.g., 'shared' — the state bucket serves all environments)."
  type        = string
  default     = "shared"
}

variable "owner" {
  description = "Team or individual responsible for these resources. Applied to all tags."
  type        = string
}

variable "cost_center" {
  description = "Cost center code for billing allocation. Applied to all tags."
  type        = string
}
