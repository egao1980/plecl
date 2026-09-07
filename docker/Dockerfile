FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        ecl \
        libgc-dev \
        libgmp-dev \
        postgresql \
        postgresql-server-dev-all \
        locales \
    && rm -rf /var/lib/apt/lists/* \
    && locale-gen en_US.UTF-8

WORKDIR /src
COPY . /src
RUN make && make install

COPY docker/run-tests.sh /run-tests.sh
RUN chmod +x /run-tests.sh
CMD ["/run-tests.sh"]
