-- BrandGuard schema v1. Run with a trusted PostgreSQL owner connection.
-- Idempotent initial migration, compatible with SQLAlchemy's repository.
BEGIN;
CREATE TABLE IF NOT EXISTS public.bg_entities (
    collection varchar(100) NOT NULL,
    entity_id varchar(200) NOT NULL,
    position integer NOT NULL,
    payload json NOT NULL,
    PRIMARY KEY (collection, entity_id)
);
CREATE INDEX IF NOT EXISTS bg_entities_collection_position
    ON public.bg_entities(collection, position);
CREATE TABLE IF NOT EXISTS public.bg_documents (
    name varchar(100) PRIMARY KEY,
    payload json NOT NULL
);
-- Backend-only tables: mobile never queries them through PostgREST.
-- Direct SQL uses the trusted server database role; authorization is in FastAPI.
ALTER TABLE public.bg_entities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bg_documents ENABLE ROW LEVEL SECURITY;
COMMIT;
