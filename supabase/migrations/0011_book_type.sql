-- ZutLib: a "book" resource type for the library's physical books.
--
-- On its own because Postgres will not let a new enum value be used in the
-- same transaction that adds it. Run this file, then 0012.
alter type public.resource_type add value if not exists 'book';
