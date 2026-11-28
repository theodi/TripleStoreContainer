# Triple Store Container

A containerised Fuseki configurable and loaded with data.

## Build image

Build parameters:

- `config`: Fuseki config (`config.ttl` and the files it imports, such as `text-indexing.ttl` for full-text search and `spatial-indexing.ttl` for GeoSPARQL), log4j2 properties and the optional `inference.ttl` (defaults to `config`). When `inference.ttl` is present, the default graph is run through its reasoner ([OWL Micro](https://jena.apache.org/documentation/inference/#OWLcoverage) by default) at build time and the inferred triples are stored with it, so queries don't pay for reasoning. Named graphs are stored as loaded, without inference. Without it, the data is served as loaded;
- `data`: Location of the RDF files to load, searched recursively (defaults to `data`). Files ending in `.ttl`, `.nt`, `.nq`, `.trig`, `.rdf`, `.owl` or `.jsonld`, optionally gzipped, are loaded; anything else is ignored.

```sh
docker build --file Containerfile --tag triple-store-container .
```

To use other folders, pass them as build contexts:

```sh
docker build --file Containerfile --build-context config=path/to/config --build-context data=path/to/data --tag triple-store-container .
```

The reasoner holds its inferences in memory and gets 75% of the build container's memory by default. To set its heap explicitly, pass JVM options as a build argument:

```sh
docker build --file Containerfile --build-arg INFERENCE_JAVA_OPTIONS=-Xmx8g --tag triple-store-container .
```

Podman finds the `Containerfile` without `--file` and accepts the same options.

To build for several platforms, pass them with `--platform`. Data loading, inference and indexing run once, natively on the build machine, as their output is the same on every platform: only the final image is built for each platform. Docker needs a builder that supports multi-platform images (the containerd image store, or `docker buildx create`) and emulation for platforms other than the build machine's (QEMU, included in Docker Desktop):

```sh
docker build --file Containerfile --platform linux/amd64,linux/arm64 --tag triple-store-container .
```

Podman builds them into a manifest list:

```sh
podman build --platform linux/amd64,linux/arm64 --manifest triple-store-container .
```


## Run container

```sh
docker run --rm -p 3030:3030 triple-store-container
```

SPARQL endpoint accessible at [http://localhost:3030/sparql](http://localhost:3030/sparql).

The server is read-only and exposes only the endpoints defined in `config.ttl`: `/sparql` (SPARQL query) and `/graph` (Graph Store Protocol, read).

Queries can use full-text search ([Jena text](https://jena.apache.org/documentation/query/text-query.html)) and [GeoSPARQL](https://jena.apache.org/documentation/geosparql/). Both indexes are built with the image: the text index from the properties listed in `config.ttl`, and the spatial index from the geometries in the data (`geo:asWKT` or `geo:asGML` literals of features linked by `geo:hasGeometry`). For example, features within 10 km of a point:

```sparql
PREFIX spatial: <http://jena.apache.org/spatial#>
SELECT ?feature WHERE { ?feature spatial:nearby (51.5072 -0.1276 10 <http://www.opengis.net/def/uom/OGC/1.0/kilometre>) }
```

To turn spatial indexing off, remove the import of `spatial-indexing.ttl` from `config.ttl` and point `text:dataset` at the store, as the comment there shows.

Example requests:
- [Get all statements](http://localhost:3030/sparql?query=CONSTRUCT%20%7B%20%3Fs%20%3Fp%20%3Fo%20%7D%20WHERE%20%7B%20%3Fs%20%3Fp%20%3Fo%20%7D) `CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o }`
- [Get the vocabulary](http://localhost:3030/sparql?query=CONSTRUCT%20%7B%20%3Fs%20%3Fp%20%3Fo%20.%20%7D%20WHERE%20%7B%20%3Fs%20%3Fp%20%3Fo%20%3B%20%3Chttp%3A%2F%2Fwww.w3.org%2F2000%2F01%2Frdf-schema%23isDefinedBy%3E%20%3Chttps%3A%2F%2Fexample.org%2Fns%2F%3E%20.%20%7D) `CONSTRUCT { ?s ?p ?o . } WHERE { ?s ?p ?o ; <http://www.w3.org/2000/01/rdf-schema#isDefinedBy> <https://example.org/ns/> . }`


## Publish image

This repository doesn't publish images itself: its `data` folder is an example for local builds only. Other repositories publish their own triple store image by calling the reusable workflow `.github/workflows/publish.yml`. It loads the data of the public repositories listed in the calling repository, builds the image for `linux/amd64` and `linux/arm64` from the `Containerfile` at the version of the workflow called (`@main`, a tag or a commit SHA), and pushes it tagged `latest` and `sha-<commit>`.

In the calling repository, `data-repositories.json` lists the repositories whose RDF files are loaded, at any depth, each with an optional `ref` (tag, branch or commit SHA; the default branch if omitted):

```json
[
  {"repository": "theodi/ontology", "ref": "v1.0.0"},
  {"repository": "theodi/data"}
]
```

Changes to the data are made to this file, so they are reviewed in pull requests and published when merged. Pin a `ref` to publish a known version of a repository; without one, its latest default branch is loaded on each publish. The repositories are checked out in parallel, one job each, including files stored with Git LFS.

A workflow calls the reusable one, e.g. `.github/workflows/publish.yml`:

```yaml
name: Publish triple store image

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  publish:
    uses: theodi/TripleStoreContainer/.github/workflows/publish.yml@main
    permissions:
      actions: read # Find the version of the workflow called
      contents: read # Check out the repositories
      packages: write # Push to GitHub Container Registry
```

Inputs:

- `image`: image name to push, without tag (defaults to `<registry>/<owner>/<repo>` of the calling repository, e.g. `ghcr.io/theodi/my-knowledge-graph`);
- `repositories-file`: JSON file of the calling repository listing the data repositories (defaults to `data-repositories.json`);
- `config-path`: folder of the calling repository to use as the config (`config.ttl` and the files it imports, `log4j2.properties` and the optional `inference.ttl`; defaults to this repository's `config`);
- `registry`, `username` and the `registry-password` secret: registry to push to (defaults to `ghcr.io` with the calling workflow's `GITHUB_TOKEN`);
- `platforms`: platforms to build for (defaults to `linux/amd64,linux/arm64`).

To push to several registries, call the workflow once per registry.
