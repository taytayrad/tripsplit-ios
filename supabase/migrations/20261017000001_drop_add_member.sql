-- TRIP-40: the share link ("Invite someone new") is the only way to add people. Nobody adds someone else,
-- so a removed member stays out (join_trip still refuses their old link).
drop function public.add_member(uuid, uuid);
