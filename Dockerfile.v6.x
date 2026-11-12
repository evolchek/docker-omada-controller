# Official Ubuntu release; use --pull to refresh the base when rebuilding.
ARG BASE=ubuntu:24.04
FROM ${BASE}
LABEL maintainer="Eugene Volchek <eugene.volchek@gmail.com>"
LABEL org.opencontainers.image.source="https://github.com/evolchek/docker-omada-controller"

COPY healthcheck-6.x.sh /healthcheck.sh
COPY install.sh build-inputs.env /

# This pinned vendor package supports amd64 only.
ARG TARGETARCH
ARG ARCH=${TARGETARCH}

# install version (major.minor or full version); OMADA_URL set in install.sh
ARG INSTALL_VER="6.3.0.111"
LABEL org.opencontainers.image.version="${INSTALL_VER}"
ARG NO_MONGODB=false

# install omada controller (instructions taken from install.sh)
RUN /install.sh &&\
  rm /install.sh

COPY entrypoint-unified.sh /entrypoint.sh

WORKDIR /opt/tplink/EAPController/lib
EXPOSE 8044 8088 8043 8843 19810/udp 27001/udp 29810/udp 29811 29812 29813 29814 29815 29816 29817
HEALTHCHECK --start-period=5m CMD /healthcheck.sh
VOLUME ["/opt/tplink/EAPController/data","/opt/tplink/EAPController/logs"]
ENTRYPOINT ["/entrypoint.sh"]
CMD ["java","-server","-Xms128m","-Xmx1024m","-XX:MaxHeapFreeRatio=60","-XX:MinHeapFreeRatio=30","-XX:+HeapDumpOnOutOfMemoryError","-XX:HeapDumpPath=/opt/tplink/EAPController/logs/java_heapdump.hprof","-Djava.awt.headless=true","-cp","/opt/tplink/EAPController/lib/*:/opt/tplink/EAPController/properties","com.tplink.smb.omada.starter.OmadaLinuxMain"]
