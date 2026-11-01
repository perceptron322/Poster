FROM postgres:17-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       python3 python3-pip python3-venv gettext-base curl \
    && python3 -m venv /opt/patroni-venv \
    && /opt/patroni-venv/bin/pip install --no-cache-dir \
       'patroni[etcd3]==4.1.5' 'psycopg2-binary==2.9.13' \
    && apt-get purge -y --auto-remove python3-pip \
    && rm -rf /var/lib/apt/lists/*

ENV PATH="/opt/patroni-venv/bin:${PATH}"

COPY entrypoint.sh /usr/local/bin/patroni-entrypoint.sh
RUN chmod +x /usr/local/bin/patroni-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/patroni-entrypoint.sh"]
