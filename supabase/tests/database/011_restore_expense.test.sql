-- Deleting and restoring an expense (docs/money-rules.md › Deleting and restoring an expense, X1–X6).
begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

create function pg_temp.net(who text, trip text) returns bigint language plpgsql as $$
begin
  perform tests.authenticate_as(tests.id(who));
  return coalesce((select cents from public.my_trip_nets() where trip_id = tests.id(trip)), 0);
end $$;

-- G1: Coast Road with you, Atish, Tyler; Tyler pays the $60 stay, Atish pays $30 dinner, both equal.
select tests.users('you', 'atish', 'tyler');
select tests.trip('cr', array['you', 'atish', 'tyler']);
create temp table t_stay on commit drop as select tests.equal('cr', 'tyler', 6000, array['you', 'atish', 'tyler']) as id;
grant select on t_stay to authenticated;
select tests.equal('cr', 'atish', 3000, array['you', 'atish', 'tyler']);

-- X1: deleting the stay leaves only the dinner.
select tests.authenticate_as(tests.id('you'));
select public.delete_expense((select id from t_stay));
select is(pg_temp.net('you', 'cr'), -1000::bigint, 'X1 you −10');
select is(pg_temp.net('atish', 'cr'), 2000::bigint, 'X1 Atish +20');
select is(pg_temp.net('tyler', 'cr'), -1000::bigint, 'X1 Tyler −10');
select isnt((select deleted_at from public.expenses where id = (select id from t_stay)), null, 'X1 the stay is kept, marked deleted');
select is((select count(*) from public.expense_shares where expense_id = (select id from t_stay))::int, 3, 'X1 its shares are kept');
select is((select deltas from public.activity_events where kind = 'expense_deleted'),
          jsonb_build_object(tests.id('you'), 2000, tests.id('atish'), 2000, tests.id('tyler'), -4000),
          'X1 the delete event is the stay coming off');
select throws_ok(format('select public.delete_expense(%L)', (select id from t_stay)),
                 'P0001', 'expense not found', 'X1 deleting it again is refused');

-- X4: a deleted expense can't be edited.
select throws_ok(format('select public.save_expense(%L, %L, %L, %L, 9000, %L, %L, %L, current_date)',
                        tests.id('cr'), (select id from t_stay), 'Stay', 'lodging', tests.id('tyler'), 'equal',
                        jsonb_build_array(jsonb_build_object('user_id', tests.id('you'), 'value', 1))::text),
                 'P0001', 'this expense was deleted; restore it first', 'X4 editing a deleted expense is refused');

-- X5: not while the trip is deleted; after the undelete it's X1, and the restore works.
select public.delete_trip(tests.id('cr'));
select throws_ok(format('select public.restore_expense(%L)', (select id from t_stay)),
                 'P0001', 'this trip is deleted', 'X5 restoring on a deleted trip is refused');
select public.undelete_trip(tests.id('cr'));
select is(pg_temp.net('atish', 'cr'), 2000::bigint, 'X5 after the undelete it''s still X1');

-- X2: Atish restores it; the nets are G1 again.
select tests.authenticate_as(tests.id('atish'));
select public.restore_expense((select id from t_stay));
select is(pg_temp.net('you', 'cr'), -3000::bigint, 'X2 you −30');
select is(pg_temp.net('atish', 'cr'), 0::bigint, 'X2 Atish 0');
select is(pg_temp.net('tyler', 'cr'), 3000::bigint, 'X2 Tyler +30');
select tests.authenticate_as(tests.id('atish'));
select is((select deltas from public.activity_events where kind = 'expense_restored'),
          jsonb_build_object(tests.id('you'), -2000, tests.id('atish'), -2000, tests.id('tyler'), 4000),
          'X2 the restore event is the stay going back on');

-- X3: restoring again does nothing.
select public.restore_expense((select id from t_stay));
select is((select count(*) from public.activity_events where kind = 'expense_restored')::int, 1, 'X3 a second restore writes nothing');

-- X6: Jo left at $0 after the lunch was deleted; restoring it would give Jo a balance.
select tests.users('youJ', 'jo');
select tests.trip('lh', array['youJ', 'jo']);
create temp table t_lunch on commit drop as select tests.equal('lh', 'jo', 2000, array['youJ', 'jo']) as id;
grant select on t_lunch to authenticated;
select tests.authenticate_as(tests.id('youJ'));
select public.delete_expense((select id from t_lunch));
select tests.authenticate_as(tests.id('jo'));
select public.leave_trip(tests.id('lh'));
select tests.authenticate_as(tests.id('youJ'));
select throws_ok(format('select public.restore_expense(%L)', (select id from t_lunch)),
                 'P0001', 'someone on this expense left the trip; add them back first', 'X6 refused when Jo has left');

-- Only members can restore.
select tests.users('olive');
select tests.authenticate_as(tests.id('olive'));
select throws_ok(format('select public.restore_expense(%L)', (select id from t_stay)),
                 'P0001', 'not a member of this trip', 'an outsider can''t restore');

select * from finish();
rollback;
