FROM postgres:15

RUN apt-get update && apt-get install -y \
  postgresql-15-cron \
  && rm -rf /var/lib/apt/lists/*

RUN echo "shared_preload_libraries = 'pg_cron'" >> /usr/share/postgresql/postgresql.conf.sample \
  && echo "cron.database_name = 'firecrawl'" >> /usr/share/postgresql/postgresql.conf.sample

COPY nuq.sql /docker-entrypoint-initdb.d/010-nuq.sql
