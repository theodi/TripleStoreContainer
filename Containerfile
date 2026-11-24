ARG JAVA_VERSION=25
ARG UBUNTU_CODENAME=resolute
ARG JENA_VERSION=6.2.0
ARG FUSEKI_SHA1=d3490295a2b95677c1227d25bca8564d40f993a7


# Internal, passed between stages.
## Fuseki
ARG FUSEKI_DIR=/fuseki
ARG FUSEKI_JAR=jena-fuseki-server-${JENA_VERSION}.jar


## ---- Stage: Java runtime (Temurin JRE on Ubuntu)
FROM eclipse-temurin:${JAVA_VERSION}-jre-${UBUNTU_CODENAME} AS jre


## ---- Stage: download Fuseki JAR
FROM jre AS fuseki-download

ARG JENA_VERSION
ARG FUSEKI_DIR
ARG FUSEKI_SHA1
ARG FUSEKI_JAR
ARG REPO=https://repo1.maven.org/maven2
ARG FUSEKI_JAR_URL=${REPO}/org/apache/jena/jena-fuseki-server/${JENA_VERSION}/${FUSEKI_JAR}

WORKDIR ${FUSEKI_DIR}

# The Temurin image has no wget or curl, so BuildKit fetches the JAR. Maven
# Central only publishes a SHA-1 (ADD --checksum needs SHA-256), so check it here.
# Remote ADD files default to mode 600: make the JAR readable by the service user.
ADD --chmod=644 ${FUSEKI_JAR_URL} ./${FUSEKI_JAR}
RUN echo "${FUSEKI_SHA1}  ${FUSEKI_JAR}" | sha1sum -c -


## ---- Stage: Default build context value for the config folder
FROM scratch AS config
COPY config/ /

## ---- Stage: Default build context value for the data folder
FROM scratch AS data
COPY data/ /


## ---- Stage: load data, apply inference, build text index
FROM jre AS loader

ARG FUSEKI_DIR
ARG FUSEKI_JAR
# Reasoner JVM options. Inferences are held in memory, so give most of the build container's memory rather than the JVM default of 25%.
ARG INFERENCE_JAVA_OPTIONS="-XX:MaxRAMPercentage=75"

WORKDIR ${FUSEKI_DIR}

COPY --from=fuseki-download ${FUSEKI_DIR}/${FUSEKI_JAR} ./

# Load all RDF file from data including subfolders and gzipped;
# Skip other files (READMEs, .DS_Store...);
# Fail the build rather than producing an empty store.
COPY --from=data . ./data/
RUN set -eu; \
    rdf_files() { \
        find ./data -type f -regextype posix-extended \
            -iregex '.*\.(ttl|nt|nq|trig|rdf|owl|jsonld)(\.gz)?' "$@"; \
    }; \
    if [ -z "$(rdf_files -print -quit)" ]; then \
        echo "No RDF files found in the data build context" >&2; \
        exit 1; \
    fi; \
    rdf_files -exec "$JAVA_HOME/bin/java" --add-modules jdk.incubator.vector \
        -cp "${FUSEKI_DIR}/${FUSEKI_JAR}" \
        tdb2.tdbloader --loader=parallel --loc ./raw-db {} +

# Inference: if inference.ttl exists, read the default graph through its reasoner and load the result into a fresh store, so queries don't pay for reasoning. Named graphs are copied as loaded, without inference.
# SELECT streams its rows (CONSTRUCT would build the whole result in memory).
# TSV rows are Turtle terms separated by tabs, and tabs inside literals are escaped: drop the header, then end each row with " ." (default graph) or wrap it as "<graph> { s p o . }" (TriG).
COPY --from=config . ./config/
RUN set -eu; \
    jena() { \
        "$JAVA_HOME/bin/java" --add-modules jdk.incubator.vector \
            -cp "${FUSEKI_DIR}/${FUSEKI_JAR}" "$@"; \
    }; \
    if [ -f config/inference.ttl ]; then \
        jena ${INFERENCE_JAVA_OPTIONS} -XX:+ExitOnOutOfMemoryError \
            arq.sparql --desc config/inference.ttl --results=tsv \
            'SELECT ?s ?p ?o WHERE { ?s ?p ?o }' > default.tsv; \
        sed -i '1d; s/$/ ./' default.tsv; \
        mv default.tsv default.ttl; \
        jena tdb2.tdbquery --loc ./raw-db --results=tsv \
            'SELECT ?s ?p ?o ?g WHERE { GRAPH ?g { ?s ?p ?o } }' > named.tsv; \
        sed -i '1d; s/^\(.*\)\t\([^\t]*\)$/\2 { \1 . }/' named.tsv; \
        mv named.tsv named.trig; \
        jena tdb2.tdbloader --loader=parallel --loc ./db default.ttl named.trig; \
        rm -r default.ttl named.trig raw-db; \
    else \
        mv raw-db db; \
    fi

RUN "$JAVA_HOME/bin/java" --add-modules jdk.incubator.vector \
        -cp "${FUSEKI_DIR}/${FUSEKI_JAR}" \
        jena.textindexer --desc config/config.ttl


## ---- Stage: runtime
FROM jre

ARG JENA_VERSION
ARG FUSEKI_DIR
ARG FUSEKI_JAR
ARG JENA_USER=fuseki
ARG JENA_GROUP=$JENA_USER
ARG JENA_GID=1000
ARG JENA_UID=1000

WORKDIR ${FUSEKI_DIR}

# Ubuntu images ship an "ubuntu" user and group with UID/GID 1000: remove them so the service user can take those IDs.
# -M : no home directory; useradd leaves the password locked by default
RUN if id -u ubuntu >/dev/null 2>&1; then userdel ubuntu; fi && \
    if getent group ubuntu >/dev/null; then groupdel ubuntu; fi && \
    groupadd -g "${JENA_GID}" "${JENA_GROUP}" && \
    useradd -u "${JENA_UID}" -g "${JENA_GROUP}" -s /usr/sbin/nologin -M "${JENA_USER}"

# JAR and config stay root-owned (read-only for the service user).
COPY --link --from=fuseki-download ${FUSEKI_DIR}/${FUSEKI_JAR} ./
COPY --link --from=config ./log4j2.properties .
COPY --link --from=loader --chown=${JENA_UID}:${JENA_GID} ${FUSEKI_DIR}/db/ ./db/
COPY --link --from=loader --chown=${JENA_UID}:${JENA_GID} ${FUSEKI_DIR}/fts-index/ ./fts-index/
COPY --link --from=config ./config.ttl .

USER ${JENA_USER}

# Heap sized from the container memory limit. TDB2 uses memory-mapped files
# outside the heap, so leave headroom rather than giving the heap everything.
ENV \
    JAVA_OPTIONS="--enable-native-access=ALL-UNNAMED --add-modules=jdk.incubator.vector -XX:MaxRAMPercentage=50 -XX:InitialRAMPercentage=50" \
    JENA_VERSION=${JENA_VERSION} \
    FUSEKI_JAR="${FUSEKI_JAR}" \
    FUSEKI_DIR="${FUSEKI_DIR}"

EXPOSE 3030

# FusekiBasicCmd serves only the endpoints in config.ttl.
# No UI, admin, /$/ping or /$/metrics, and nothing written to disk at runtime.
ENTRYPOINT ["/bin/sh", "-c", "exec \"$JAVA_HOME/bin/java\" $JAVA_OPTIONS -cp \"$FUSEKI_DIR/$FUSEKI_JAR\" org.apache.jena.fuseki.main.cmds.FusekiBasicCmd \"$@\"", "--"]

CMD ["--conf", "./config.ttl"]
