## safebrowsing-zig

High-performance, Zig implementation of Google Safe Browsing v5 lookups (https://developers.google.com/safe-browsing/)

* Host-Suffix Path-Prefix Expressions generation as defined [here](https://developers.google.com/safe-browsing/reference/URLs.and.Hashing#host-suffix-path-prefix-expressions) and complient using the [Public Suffix List](https://publicsuffix.org/)
* Local threat database decoding from protobuf using Golomb–Rice compression as defined [here](https://developers.google.com/safe-browsing/reference/Local.Database)
* Real-Time mode: first check the Global Cache list
* Check SHA-256 prefixes against the local database
* Designed to scan millions of URLs (sub-second on modern hardware)
* Outputs a list of "unsure" 4-byte prefixes to verify via Google's hash search endpoint

### How it works

1. Expression URLs

* For each input URL, we compute the v5 host-suffix / path-prefix set.
* Public suffixes are respected using publicsuffix.org data so we don’t over- or under-expand hosts.
* Each expression URL is canonicalized and hashed (SHA-256) to generate 4-byte (prefix) keys.

2. Global Cache (Real-Time)

* Before touching the local DB, we check the global cache list for real-time verdicts that can short-circuit lookups.

3. Local Database

* We load and decode the v5 threat list database from Google’s update API.
* The protobuf payload is decoded and Golomb–Rice compressed chunks are expanded into a compact prefix set.

4. Unsure prefixes

* If a prefix is present but a full hash verdict is required, we emit it in the “unsure” output list for a follow-up hash search request to Google.
* This minimizes online calls while preserving detection.
