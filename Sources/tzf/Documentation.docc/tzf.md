# ``tzf``

A fast timezone lookup library for Swift.

A Swift package for timezone lookup by geographic coordinates (longitude/latitude).
Since v2 the package is protobuf-free: the data source is the TZF embedded
binary format (`.tzb`) shipped by [tzf-dist](https://github.com/ringsaturn/tzf-dist),
and the package bundles the lite (topology-simplified) dataset.

Important Notes:

- The timezone boundary data has been simplified to reduce size; every
  simplified boundary stays within ~111 m of the full-precision border.
- A point exactly on a shared border belongs to every touching timezone;
  ``F/getTimezones(lng:lat:)`` returns them sorted lexicographically.

The package offers two finder implementations, both conforming to ``F``:

- ``DefaultFinder``: Recommended. Expands the `.tzb` geometry into polygons
  at load; ``F/getTimezone(lng:lat:)`` answers from the FUZZY preindex tiles
  with exact point-in-polygon fallback.
- ``EmbeddedFinder``: Low-memory. Queries the `.tzb` bytes in place (~4 MB
  total); identical results, microsecond queries on boundary cases.

Both accept caller-owned `.tzb` bytes (for example tzf-dist's full-precision
`full.tzb`) through `init(tzb:)`.

## Topics

### Finders

- ``F``
- ``DefaultFinder``
- ``EmbeddedFinder``
- ``TZFDist``
- ``TZFError``

### GeoJSON

- ``GeoJSONFeatureCollection``
- ``GeoJSONFeature``
- ``GeoJSONGeometry``
- ``GeoJSONProperties``

---

Other related projects:

| Language or Sever         | Link                                                                    | Note                |
| ------------------------- | ----------------------------------------------------------------------- | ------------------- |
| Go                        | [`ringsaturn/tzf`](https://github.com/ringsaturn/tzf)                   |                     |
| Ruby                      | [`HarlemSquirrel/tzf-rb`](https://github.com/HarlemSquirrel/tzf-rb)     | build with tzf-rs   |
| Rust                      | [`ringsaturn/tzf-rs`](https://github.com/ringsaturn/tzf-rs)             |                     |
| Swift                     | [`ringsaturn/tzf-swift`](https://github.com/ringsaturn/tzf-swift)       |                     |
| Python                    | [`ringsaturn/tzfpy`](https://github.com/ringsaturn/tzfpy)               | build with tzf-rs   |
| HTTP API                  | [`racemap/rust-tz-service`](https://github.com/racemap/rust-tz-service) | build with tzf-rs   |
| JS via Wasm(browser only) | [`ringsaturn/tzf-wasm`](https://github.com/ringsaturn/tzf-wasm)         | build with tzf-rs   |
| Online                    | [`ringsaturn/tzf-web`](https://github.com/ringsaturn/tzf-web)           | build with tzf-wasm |

Please see [project-tzf](https://project-tzf.ringsaturn.me) for more information.
