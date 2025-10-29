variable "region" {
  type    = string
  default = "eu-central-1"
}
variable "account_id" { 
    type = string 
    default = "325583868777"
}
variable "github_owner" { 
    type = string 
    default = "caiocbcouto"
}
variable "repo_name" {
  type    = string
  default = "DP001-todo-list-app"
}
variable "branch" {
  type    = string
  default = "main"
}
variable "ecr_repo_name" {
  type    = string
  default = "DP001-todo-frontend"
}
variable "eks_cluster_name" {
  type    = string
  default = "eksDeepDiveFrankfurt"
}
variable "codestar_connection_arn" {
  type        = string
  description = "ARN da CodeStar Connection GitHub"
  default = "arn:aws:codeconnections:eu-central-1:325583868777:connection/d3814b79-28d1-4903-8dc2-c70499f6511f"
}
