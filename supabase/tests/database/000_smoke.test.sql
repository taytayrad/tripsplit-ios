-- Proves the pgTAP pipeline runs locally and in CI. Phase 1 golden cases live beside this file.
begin;
create extension if not exists pgtap with schema extensions;
select plan(1);
select ok(true, 'pgTAP runs');
select * from finish();
rollback;
