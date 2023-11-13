
FROM tharsishq/evmos:v15.0.0-rc2
WORKDIR /root
USER root

RUN apk add lz4-libs

COPY testnet_node.sh /usr/bin/testnet_node.sh
RUN chmod +x /usr/bin/testnet_node.sh

COPY statesync.sh /usr/bin/statesync.sh
RUN chmod +x /usr/bin/statesync.sh

COPY snapshot.sh /usr/bin/snapshot.sh
RUN chmod +x /usr/bin/snapshot.sh

USER 1000
WORKDIR /home/evmos

EXPOSE 26656 26657 1317 9090 8545 8546

CMD ["evmosd"]
