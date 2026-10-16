# Triple Store Container

A containerised Fuseki configurable and loaded with data.

## Build image

Build parameters:

- `config`: Fuseki config and log4j2 properties (defaults to `store/config`);
- `data`: Location of the `.ttl` files to load (defaults to `store/data`).

```sh
docker build --build-context config=store/config --build-context data=store/data --tag triple-store-container .
```


## Run container

```sh
docker run --rm -p 3030:3030 triple-store-container
```

SPARQL endpoint accessible at [http://localhost:3030/sparql](http://localhost:3030/sparql).

Example requests:
- [Get all statements](http://localhost:3030/sparql?query=CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o }) `CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o }`
- [Get the vocabulary](http://localhost:3030/sparql?query=CONSTRUCT%20%7B%20%3Fs%20%3Fp%20%3Fo%20.%20%7D%20WHERE%20%7B%20%3Fs%20%3Fp%20%3Fo%20%3B%20%3Chttp%3A%2F%2Fwww.w3.org%2F2000%2F01%2Frdf-schema%23isDefinedBy%3E%20%3Chttps%3A%2F%2Fns.volunteeringdata.io%2F%3E%20.%20%7D) `CONSTRUCT { ?s ?p ?o . } WHERE { ?s ?p ?o ; <http://www.w3.org/2000/01/rdf-schema#isDefinedBy> <https://ns.volunteeringdata.io/> . }`
