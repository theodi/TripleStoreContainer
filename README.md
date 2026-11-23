# Triple Store Container

A containerised Fuseki configurable and loaded with data.

## Build image

Build parameters:

- `config`: Fuseki config and log4j2 properties (defaults to `config`);
- `data`: Location of the RDF files to load, searched recursively (defaults to `data`). Files ending in `.ttl`, `.nt`, `.nq`, `.trig`, `.rdf`, `.owl` or `.jsonld`, optionally gzipped, are loaded; anything else is ignored.

```sh
docker build --file Containerfile --tag triple-store-container .
```

To use other folders, pass them as build contexts:

```sh
docker build --file Containerfile --build-context config=path/to/config --build-context data=path/to/data --tag triple-store-container .
```

Podman finds the `Containerfile` without `--file` and accepts the same options.


## Run container

```sh
docker run --rm -p 3030:3030 triple-store-container
```

SPARQL endpoint accessible at [http://localhost:3030/sparql](http://localhost:3030/sparql).

The server is read-only and exposes only the endpoints defined in `config.ttl`: `/sparql` (SPARQL query) and `/graph` (Graph Store Protocol, read).

Example requests:
- [Get all statements](http://localhost:3030/sparql?query=CONSTRUCT%20%7B%20%3Fs%20%3Fp%20%3Fo%20%7D%20WHERE%20%7B%20%3Fs%20%3Fp%20%3Fo%20%7D) `CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o }`
- [Get the vocabulary](http://localhost:3030/sparql?query=CONSTRUCT%20%7B%20%3Fs%20%3Fp%20%3Fo%20.%20%7D%20WHERE%20%7B%20%3Fs%20%3Fp%20%3Fo%20%3B%20%3Chttp%3A%2F%2Fwww.w3.org%2F2000%2F01%2Frdf-schema%23isDefinedBy%3E%20%3Chttps%3A%2F%2Fns.volunteeringdata.io%2F%3E%20.%20%7D) `CONSTRUCT { ?s ?p ?o . } WHERE { ?s ?p ?o ; <http://www.w3.org/2000/01/rdf-schema#isDefinedBy> <https://ns.volunteeringdata.io/> . }`
