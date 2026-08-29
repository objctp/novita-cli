# nv catalog
Public catalog: GPU products per category, and regions.
The products endpoint requires BOTH query params — type=gpu and
category=instance|serverless — or the API answers 400, so each verb pins
them. Product ids feed `nv pod create --product` / `nv serverless create
--product`; region ids feed --region / --region-id.

```
nv catalog <verb> [flags]
```

## Commands

- [`nv catalog gpu`](catalog-gpu.md) — List GPU products rentable as instances (pods).
- [`nv catalog serverless`](catalog-serverless.md) — List GPU products rentable by serverless endpoints.
- [`nv catalog regions`](catalog-regions.md) — List regions with their supported GPU types.
