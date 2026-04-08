# ``tzf``

A fast timezone lookup library for Swift.

A Swift package for timezone lookup by geographic coordinates (longitude/latitude).
This package uses a simplified polygon data structure for timezone boundaries.

Important Notes:

- The timezone boundary data has been simplified to reduce complexity
- Accuracy may be reduced around timezone borders

The package offers three finder implementations:

- `PreindexFinder`: Uses pre-indexed map tiles for fast lookups
- `Finder`: Uses polygon-based lookups with simplified boundary data
- `DefaultFinder`: Combines both approaches for optimal results

---

Other related projects:

| Language or Sever         | Link                                                                    | Note                |
| ------------------------- | ----------------------------------------------------------------------- | ------------------- |
| Go                        | [`ringsaturn/tzf`](https://github.com/ringsaturn/tzf)                   |                     |
| Ruby                      | [`HarlemSquirrel/tzf-rb`](https://github.com/HarlemSquirrel/tzf-rb)     | build with tzf-rs   |
| Rust                      | [`ringsaturn/tzf-rs`](https://github.com/ringsaturn/tzf-rs)             |                     |
| Swift                     | [`ringsaturn/tzf-swift`](https://github.com/ringsaturn/tzf-swift)       |                     |
| Python                    | [`ringsaturn/tzfpy`](https://github.com/ringsaturn/tzfpy)               | build with tzf-rs   |
| HTTP API                  | [`ringsaturn/tzf-server`](https://github.com/ringsaturn/tzf-server)     | build with tzf      |
| HTTP API                  | [`racemap/rust-tz-service`](https://github.com/racemap/rust-tz-service) | build with tzf-rs   |
| Redis Server              | [`ringsaturn/tzf-server`](https://github.com/ringsaturn/tzf-server)     | build with tzf      |
| Redis Server              | [`ringsaturn/redizone`](https://github.com/ringsaturn/redizone)         | build with tzf-rs   |
| JS via Wasm(browser only) | [`ringsaturn/tzf-wasm`](https://github.com/ringsaturn/tzf-wasm)         | build with tzf-rs   |
| Online                    | [`ringsaturn/tzf-web`](https://github.com/ringsaturn/tzf-web)           | build with tzf-wasm |
