ARG JAVA_VERSION=21
FROM eclipse-temurin:${JAVA_VERSION}-alpine AS base

ENV FUSEKI_SHA512 ba65f5867d2d4741b2ed9e2af5a0d4fbb447909894ab2a0c6bc4dac8997f4fe339c87b13c48d45d054977769f0f8bf763ea346b1f7792d5cdc458041bd43a132
ENV FUSEKI_VERSION 6.2.0
ENV JENA_SHA512 2b467d2ff940c207aea935e012ecbb0f0ab3e6bf59b3fc4b3fbc6cf9cea11f1428e97882ec078a5ffc57e114e0f5c88ea98c4575e687cc1dd232f99324b7b2a2
ENV JENA_VERSION 6.2.0

ENV MIRROR https://dlcdn.apache.org
ENV ARCHIVE http://archive.apache.org/dist

# Fuseki installation
ENV FUSEKI_HOME /jena-fuseki
ENV FUSEKI_JAR=fuseki-server.jar

ENV JENA_HOME /jena
ENV JENA_BIN $JENA_HOME/bin

## Default environment variables.
ENV JAVA_OPTIONS="-Xmx2048m -Xms2048m"

WORKDIR /tmp
# sha512 checksum
RUN echo "$FUSEKI_SHA512  fuseki.tar.gz" > fuseki.tar.gz.sha512
# Download/check/unpack/move Fuseki in one go (to reduce image size)
RUN wget -O fuseki.tar.gz $MIRROR/jena/binaries/apache-jena-fuseki-$FUSEKI_VERSION.tar.gz || \
    wget -O fuseki.tar.gz $ARCHIVE/jena/binaries/apache-jena-fuseki-$FUSEKI_VERSION.tar.gz && \
    sha512sum -c fuseki.tar.gz.sha512 && \
    tar zxf fuseki.tar.gz && \
    mv apache-jena-fuseki* $FUSEKI_HOME && \
    rm fuseki.tar.gz* && \
    cd $FUSEKI_HOME && rm -rf fuseki.war

# jq needed for tdb2.xloader
RUN apk add --update bash ca-certificates coreutils findutils jq pwgen ruby wget && rm -rf /var/cache/apk/*

# Get tdb1.xloader and tdb2.xloader from Jena
# sha512 checksum
RUN echo "$JENA_SHA512  jena.tar.gz" > jena.tar.gz.sha512
# Download/check/unpack/move Jena in one go (to reduce image size)
RUN wget -O jena.tar.gz $MIRROR/jena/binaries/apache-jena-$JENA_VERSION.tar.gz || \
    wget -O jena.tar.gz $ARCHIVE/jena/binaries/apache-jena-$JENA_VERSION.tar.gz && \
    sha512sum -c jena.tar.gz.sha512 && \
    tar zxf jena.tar.gz && \
    mkdir -p $JENA_BIN && \
    mv apache-jena*/lib $JENA_HOME && \
    mv apache-jena*/bin/tdb2.tdbloader $JENA_BIN && \
    rm -rf apache-jena* && \
    rm jena.tar.gz*

WORKDIR $FUSEKI_HOME

# Load indexer config
ADD ./fuseki/config.ttl .
RUN "$JAVA_HOME/bin/java" -cp "${FUSEKI_HOME}/${FUSEKI_JAR}" jena.textindexer --desc config.ttl

#Load data
ARG DATABASE=./db
COPY --from=data-folder . ./data/
RUN for file in ./data/*.ttl; do $JENA_HOME/bin/tdb2.tdbloader --loc $DATABASE "$file"; done

ADD ./fuseki/entrypoint.sh .
RUN chmod a+x entrypoint.sh

EXPOSE 3030

ENTRYPOINT ["./entrypoint.sh" ]

CMD [ "--conf", "./config.ttl" ]
