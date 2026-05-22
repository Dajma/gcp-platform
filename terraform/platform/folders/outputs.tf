output "folder_ids" {
  description = "Map of logical folder key to numeric folder ID (e.g. '123456789012')"
  value = {
    for k, v in google_folder.top_level : k => v.folder_id
  }
}

output "folder_names" {
  description = "Map of logical folder key to full resource name (folders/{id})"
  value = {
    for k, v in google_folder.top_level : k => v.name
  }
}
