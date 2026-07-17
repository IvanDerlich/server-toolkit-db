ARG MONGODB_IMAGE_TAG=7.0
FROM mongo:${MONGODB_IMAGE_TAG}

COPY image/mongod.conf /etc/mongo/mongod.conf
COPY image/mongod-init.conf /etc/mongo/mongod-init.conf
COPY image/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod 0755 /usr/local/bin/entrypoint.sh && \
	mkdir -p /etc/mongo && \
	chown -R 999:999 /etc/mongo

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["mongod", "--config", "/etc/mongo/mongod.conf"]