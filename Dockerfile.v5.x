# Official Ubuntu release; use --pull when rebuilding.
ARG BASE=ubuntu:20.04
FROM ${BASE}
LABEL maintainer="Eugene Volchek <eugene.volchek@gmail.com>"
LABEL org.opencontainers.image.source="https://github.com/evolchek/docker-omada-controller"

COPY healthcheck.sh install.sh build-inputs.env runtime-properties.sh /

# The recorded vendor archive supports linux/amd64 only.
ARG TARGETARCH
ARG ARCH=${TARGETARCH}

# Exact version must match build-inputs.env.
ARG INSTALL_VER="5.15.24.19"
LABEL org.opencontainers.image.version="${INSTALL_VER}"
ARG NO_MONGODB=false

# install omada controller (instructions taken from install.sh)
RUN /install.sh &&\
  rm /install.sh

COPY entrypoint-5.x.sh /entrypoint.sh
COPY entrypoint-rootless.sh /entrypoint-rootless.sh

WORKDIR /opt/tplink/EAPController/lib
EXPOSE 8088 8043 8843 19810/udp 27001/udp 29810/udp 29811 29812 29813 29814 29815 29816
HEALTHCHECK --start-period=5m CMD /healthcheck.sh
VOLUME ["/opt/tplink/EAPController/data","/opt/tplink/EAPController/logs"]
ENTRYPOINT ["/entrypoint.sh"]
CMD ["java","-server","-Xms128m","-Xmx1024m","-XX:MaxHeapFreeRatio=60","-XX:MinHeapFreeRatio=30","-XX:+HeapDumpOnOutOfMemoryError","-XX:HeapDumpPath=/opt/tplink/EAPController/logs/java_heapdump.hprof","-Djava.awt.headless=true","--add-opens","java.base/sun.security.x509=ALL-UNNAMED","--add-opens","java.base/sun.security.util=ALL-UNNAMED","-cp","/opt/tplink/EAPController/lib/*::/opt/tplink/EAPController/properties:","com.tplink.smb.omada.starter.OmadaLinuxMain"]
