# nv template
Templates: reusable instance configuration snapshots.
A template bundles an image with its envs, ports and startup command so a
workload can be re-created from one id. Create and update answer
{"template_id": …} (not {"id": …}); the spec requires name, type and image
on create, and `instance` is the only officially documented type value.

```
nv template <verb> [flags]
```

## Commands

- [`nv template list`](template-list.md) — List templates as a table: id, name.
- [`nv template create`](template-create.md) — Create a template from an image.
- [`nv template update`](template-update.md) — Update a template (the update spec takes the create key set, none required).
- [`nv template delete`](template-delete.md) — Delete a template permanently.
