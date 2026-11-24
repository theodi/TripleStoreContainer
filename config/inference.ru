# Build-time inference.
# The loader runs this SPARQL Update against the on-disk store again and again
# until it adds no new triples. The server then answers from precomputed
# triples, and memory use depends on how many triples each rule adds, not on
# the size of the data.
# Rules apply to the default graph. Remove this file to load the data as is.
#
# Supported: rdfs:subClassOf, rdfs:subPropertyOf, rdfs:domain, rdfs:range,
# owl:equivalentClass, owl:equivalentProperty, owl:inverseOf,
# owl:SymmetricProperty and owl:TransitiveProperty.
#
# Add an INSERT below for anything else you need. Jena holds every row of a
# WHERE clause in memory before inserting, so rules that join keep only new
# triples (FILTER NOT EXISTS) and drop duplicate rows (SELECT DISTINCT).

PREFIX rdf:  <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX owl:  <http://www.w3.org/2002/07/owl#>


## Schema

# Equivalence is subsumption both ways
INSERT { ?a rdfs:subClassOf ?b . ?b rdfs:subClassOf ?a }
WHERE  { ?a owl:equivalentClass ?b } ;

INSERT { ?a rdfs:subPropertyOf ?b . ?b rdfs:subPropertyOf ?a }
WHERE  { ?a owl:equivalentProperty ?b } ;

# Inverse is symmetric
INSERT { ?q owl:inverseOf ?p }
WHERE  { ?p owl:inverseOf ?q } ;

# Subsumption is transitive
INSERT { ?a rdfs:subClassOf ?c }
WHERE  {
    SELECT DISTINCT ?a ?c {
        ?a rdfs:subClassOf/rdfs:subClassOf+ ?c
        FILTER NOT EXISTS { ?a rdfs:subClassOf ?c }
    }
} ;

INSERT { ?a rdfs:subPropertyOf ?c }
WHERE  {
    SELECT DISTINCT ?a ?c {
        ?a rdfs:subPropertyOf/rdfs:subPropertyOf+ ?c
        FILTER NOT EXISTS { ?a rdfs:subPropertyOf ?c }
    }
} ;


## Properties

INSERT { ?s ?q ?o }
WHERE  {
    SELECT DISTINCT ?s ?q ?o {
        ?p rdfs:subPropertyOf ?q .
        ?s ?p ?o
        FILTER NOT EXISTS { ?s ?q ?o }
    }
} ;

INSERT { ?o ?q ?s }
WHERE  {
    SELECT DISTINCT ?s ?q ?o {
        ?p owl:inverseOf ?q .
        ?s ?p ?o
        FILTER (!isLiteral(?o))
        FILTER NOT EXISTS { ?o ?q ?s }
    }
} ;

INSERT { ?o ?p ?s }
WHERE  {
    SELECT DISTINCT ?s ?p ?o {
        ?p a owl:SymmetricProperty .
        ?s ?p ?o
        FILTER (!isLiteral(?o))
        FILTER NOT EXISTS { ?o ?p ?s }
    }
} ;

# Each pass at least doubles the length of chains covered
INSERT { ?a ?p ?c }
WHERE  {
    SELECT DISTINCT ?a ?p ?c {
        ?p a owl:TransitiveProperty .
        ?a ?p ?b .
        ?b ?p ?c
        FILTER NOT EXISTS { ?a ?p ?c }
    }
} ;


## Types

INSERT { ?s a ?c }
WHERE  {
    SELECT DISTINCT ?s ?c {
        ?p rdfs:domain ?c .
        ?s ?p ?o
        FILTER NOT EXISTS { ?s a ?c }
    }
} ;

INSERT { ?o a ?c }
WHERE  {
    SELECT DISTINCT ?o ?c {
        ?p rdfs:range ?c .
        ?s ?p ?o
        FILTER (!isLiteral(?o))
        FILTER NOT EXISTS { ?o a ?c }
    }
} ;

INSERT { ?x a ?c }
WHERE  {
    SELECT DISTINCT ?x ?c {
        ?b rdfs:subClassOf ?c .
        ?x a ?b
        FILTER NOT EXISTS { ?x a ?c }
    }
}
