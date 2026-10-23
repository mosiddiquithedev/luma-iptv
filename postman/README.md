# Local Xtream compatibility fixture

This Postman simulation serves a minimal Xtream-compatible read-only API at `http://localhost:4900/xtream`. It is based on the existing macOS `ProviderClient.swift` contract: login, three catalog kinds, category lists, movie details, and numerically sorted episode details. Metadata is fictional; the only accepted credentials are `fixture` / `fixture`. It deliberately returns 501 for unmodeled paths/actions.

```sh
postman simulation run postman/simulations/iptv.sim.yaml --port 4900 --output ndjson
```

Postman CLI >=1.70 is required (validated with 1.75). No cloud push or deployment is needed. The provider-owner mock search was skipped after Postman reported no authorization; this local fixture is not an official provider contract. Android instrumentation uses `adb reverse tcp:4900 tcp:4900` to run the actual Java HTTP client against the simulation. Logs stay outside Git because real request logs can include credentials.
