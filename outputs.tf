# Attribution outputs (STUB) — created resource IDs per kind + tracking tag,
# to be filled when the Azure resources land.

output "tracking_tag" {
  description = "The tracking tag applied to every decoy, echoed for platform registration."
  value = {
    key   = var.tracking_tag_key
    value = var.tracking_tag_value
  }
}
