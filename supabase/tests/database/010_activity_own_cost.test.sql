-- An own-cost expense stores its amount on the activity event. A later edit does not change that row.
begin;
create extension if not exists pgtap with schema extensions;
select plan(6);

select tests.users('you');
select tests.trip('cr', array['you']);
select tests.authenticate_as(tests.id('you'));
select public.save_expense(tests.id('cr'), null, 'Lyft', 'rideshare', 10000, tests.id('you'), 'equal',
  jsonb_build_array(jsonb_build_object('user_id', tests.id('you'), 'value', 1)), current_date);

select is((select expense_amount_cents from public.activity_events where kind = 'expense_added'), 10000,
          'added: the own-cost amount is snapshotted');
select is((select expense_payer_share_cents from public.activity_events where kind = 'expense_added'), 10000,
          'added: the payer share is snapshotted');

select public.save_expense(tests.id('cr'),
  (select expense_id from public.activity_events where kind = 'expense_added'),
  'Lyft', 'rideshare', 20000, tests.id('you'), 'equal',
  jsonb_build_array(jsonb_build_object('user_id', tests.id('you'), 'value', 1)), current_date);

select is((select expense_amount_cents from public.activity_events where kind = 'expense_added'), 10000,
          'edit: the earlier row keeps $100');
select is((select expense_amount_cents from public.activity_events where kind = 'expense_updated'), 20000,
          'edit: the new row records $200');

select public.delete_expense((select expense_id from public.activity_events where kind = 'expense_added'));
select is((select expense_amount_cents from public.activity_events where kind = 'expense_deleted'), 20000,
          'delete: the removed expense is snapshotted at $200');
select is((select expense_amount_cents from public.activity_events where kind = 'expense_added'), 10000,
          'delete: the earlier row still says $100');

select * from finish();
rollback;
