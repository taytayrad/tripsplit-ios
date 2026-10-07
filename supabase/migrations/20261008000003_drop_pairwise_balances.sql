-- Pairwise balances retire (TRIP-13): the app reads member nets and suggested payments (TRIP-10), and the header
-- total, Your Balance and person screens are gone.
drop function public.my_header_total();
drop function public.my_combined_balances();
drop function public.my_pair_balances();
drop view private.pair_balances;
