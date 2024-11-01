# AWS region variable
variable "region" {
  type        = string
  description = "Deployment region."
  default     = "ap-southeast-2"
}

# AWS configuration
variable "common-tags" {
  type        = map(string)
  description = "A set of tags to attach to every created resource."
}