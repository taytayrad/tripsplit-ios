"""Two real local database sessions: neither order may strand a deleted person with debt."""
import json
import subprocess
import time
import uuid

PSQL = ["docker", "exec", "-i", "supabase_db_tripsplit", "psql", "-U", "postgres",
        "-d", "postgres", "-Atq", "-v", "ON_ERROR_STOP=1"]


def sql(source, check=True):
    result = subprocess.run(PSQL, input="set statement_timeout = '15s';\n" + source,
                            text=True, capture_output=True, timeout=20)
    if check and result.returncode:
        raise AssertionError(result.stderr)
    return result


def start(source):
    process = subprocess.Popen(PSQL, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True)
    process.stdin.write("set statement_timeout = '15s';\n" + source)
    process.stdin.close()
    process.stdin = None
    return process


def wait_for_pause(application):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if sql(f"select exists(select 1 from pg_stat_activity where application_name='{application}' "
               "and wait_event='PgSleep');").stdout.strip() == "t":
            return
        time.sleep(0.05)
    raise AssertionError("The database session never reached its synchronization point")


def race(deletion_first):
    prefix = "account_race_" + uuid.uuid4().hex
    process = None
    try:
        sql(f"""
begin;
select tests.users('{prefix}person', '{prefix}friend');
select tests.trip('{prefix}shared', array['{prefix}person', '{prefix}friend']);
select tests.trip('{prefix}solo', array['{prefix}person']);
select tests.trip('{prefix}target', array['{prefix}friend']);
select tests.clear_authentication();
create function tests.{prefix}_pause() returns trigger language plpgsql as $$
begin
  if new.id = tests.id('{prefix}solo') then perform pg_sleep(3); end if;
  return new;
end;
$$;
create trigger {prefix}_pause before update on public.trips for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function tests.{prefix}_pause();
commit;
""")
        delete = f"""
set application_name = '{prefix}delete';
begin;
select tests.authenticate_as(tests.id('{prefix}person'));
select public.delete_account();
commit;
"""
        add = f"""
set application_name = '{prefix}add';
begin;
select tests.authenticate_as(tests.id('{prefix}person'));
select public.join_trip((select token from tests.names where k = '{prefix}target'));
select tests.equal('{prefix}target', '{prefix}friend', 2000, array['{prefix}person', '{prefix}friend']);
{'select pg_sleep(3);' if not deletion_first else ''}
commit;
"""
        process = start(delete if deletion_first else add)
        wait_for_pause(prefix + ("delete" if deletion_first else "add"))
        other = sql(add if deletion_first else delete, check=False)
        output, errors = process.communicate(timeout=15)
        assert process.returncode == 0, errors + output
        expected = ("that account was deleted" if deletion_first
                    else "settle up on every trip before deleting your account")
        assert other.returncode != 0 and expected in other.stderr, other.stdout + other.stderr
        state = json.loads(sql(f"""
select jsonb_build_object(
  'alive', exists(select 1 from auth.users where id = tests.id('{prefix}person')),
  'active', exists(select 1 from public.trip_members where trip_id = tests.id('{prefix}target')
                  and user_id = tests.id('{prefix}person') and removed_at is null),
  'cents', private.net_including_deleted(tests.id('{prefix}target'), tests.id('{prefix}person'))
);
""").stdout)
        assert state == ({"alive": False, "active": False, "cents": 0} if deletion_first
                         else {"alive": True, "active": True, "cents": -1000}), state
        print("PASS: " + ("deletion rejects a late membership" if deletion_first
                          else "deletion sees an earlier membership's balance"))
    finally:
        if process is not None and process.poll() is None:
            process.communicate(timeout=15)
        sql(f"""
begin;
drop trigger if exists {prefix}_pause on public.trips;
drop function if exists tests.{prefix}_pause();
delete from public.trips where id in (select id from tests.names where starts_with(k, '{prefix}'));
delete from auth.users where id in (select id from tests.names where starts_with(k, '{prefix}'));
delete from public.profiles where id in (select id from tests.names where starts_with(k, '{prefix}'));
delete from tests.names where starts_with(k, '{prefix}');
commit;
""")


if __name__ == "__main__":
    race(deletion_first=True)
    race(deletion_first=False)
