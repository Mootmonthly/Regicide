# Regicide dedicated server in a container. Build from the unpacked server folder:
#   docker compose up -d        (or: docker build -t regicide-server . )
FROM ubuntu:24.04
WORKDIR /opt/regicide
COPY Regicide.x86_64 run-server.sh ./
RUN chmod +x Regicide.x86_64 run-server.sh && mkdir /config
EXPOSE 24565/udp
# server.cfg lives in the /config volume; a default one is written there on first start.
CMD ["./run-server.sh", "--config", "/config/server.cfg"]
