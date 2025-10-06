## safebrowsing-zig

High-performance, Zig implementation of Google Safe Browsing v5 lookups (https://developers.google.com/safe-browsing/)

Safe Browsing is a Google service that lets client applications check URLs against Google's constantly updated lists of unsafe web resources. Examples of unsafe web resources are social engineering sites (phishing and deceptive sites) and sites that host malware or unwanted software.

This library provides a way to query URLs against pre-downloaded threat lists (`hashList`) provided by Google. These threat lists act as a kind of Bloom filter–like database, ensuring no false negatives. When a positive match is found, a verification query to the Google Safe Browsing API is required.

Google API is using protobuf. Deserialization code is generated using https://github.com/Arwalk/zig-protobuf

### How it works

1. **Expression URLs**

* For each input URL, compute the v5 host-suffix / path-prefix set.
* eTLD+1 are respected using [Public Suffix List](https://publicsuffix.org/)
* Each expression URL is hashed (SHA-256) to generate 4-byte (prefix) keys.

2. **Global Cache (Real-Time mode of operation)**

* Before querying the local threat database, check the global cache for known "safe" URLs.

3. **Local Database**

* Load and decode a hashList (threat list) database from Google's API.
* The protobuf payload is decoded and Golomb–Rice compressed chunks are expanded into a compact prefix set.

4. **Unsure prefixes**

* If a prefix is present in a threat list, emits it in the "unsure" output list for a follow-up hash search request to Google's hashes search endpoint.

## TODO

- [ ] Emit base64 prefix of unsure URLs to be checked against the search endpoint (https://developers.google.com/safe-browsing/reference/rest/v5/hashes/search)
- [ ] CLI flags to pass Hash lists database binary file
