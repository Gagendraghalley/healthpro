-- =====================================================================
-- Sample services for testing Find services (not a migration)
-- =====================================================================
-- Eight verified organisations of different types (two pools, two cycling
-- clubs, a wellness centre, a sports arena, a fitness studio and a gym) in
-- Thimphu, Paro and Punakha, each with its place on the map, opening hours,
-- facilities, packages and classes. Every one says "Sample data" in its
-- description.
--
-- Run it on purpose, on a test or local database: paste it into the
-- Supabase SQL editor (or psql -f). It is not in supabase/migrations, so a
-- deploy never adds it. Safe to run again: fixed ids, nothing doubled.
--
-- To run one as its owner (to try its console), sign up in the app, then:
--   insert into public.venue_staff (venue_id, user_id, role)
--   select '5a000000-0000-0000-0000-000000000001', id, 'owner' from public.profiles where email = 'you@example.com';
--
-- To take them all away again (their packages and classes go with them):
--   delete from public.venues where id::text like '5a000000-0000-0000-0000-0000000000%';
--   delete from public.organisations o where not exists (select 1 from public.venues v where v.organisation_id = o.id)
--     and o.name in ('Blue Lane Swimming Pool', 'Paro Valley Pool', 'Trail Riders Cycling Club', 'Punakha River Rides',
--                    'Lotus Wellness Spa', 'Babesa Sports Arena', 'Pulse Fitness Studio', 'Peak Mountain Gym');
-- =====================================================================

update public.app_modules set is_enabled = true where key = 'gym_membership';

insert into public.venues (id, type, name, description, dzongkhag, town, address, phone, email, contact_person,
                           latitude, longitude, opening_hours, facilities, payment_info, cancellation_policy,
                           verification_status, verified_at)
values
  ('5a000000-0000-0000-0000-000000000001', 'swimming', 'Blue Lane Swimming Pool',
   'An indoor 25 m pool with lanes for laps, a shallow pool for children and swimming lessons for every age. Sample data.',
   'Thimphu', 'Changlimithang', 'Beside the stadium', '+97517100001', 'hello@bluelane.example', 'Karma Choden',
   27.4655, 89.6420,
   '{"mon":[["06:00","10:00"],["15:00","20:00"]],"tue":[["06:00","10:00"],["15:00","20:00"]],"wed":[["06:00","10:00"],["15:00","20:00"]],"thu":[["06:00","10:00"],["15:00","20:00"]],"fri":[["06:00","10:00"],["15:00","20:00"]],"sat":[["07:00","18:00"]]}',
   array['Changing rooms', 'Shower', 'Lockers', 'Lifeguard', 'Swimming lessons', 'Kids'' pool', 'Heated pool'],
   'mBoB account 200000101, or cash at the counter.', 'Packages are not refunded once they have started.',
   'verified', now()),
  ('5a000000-0000-0000-0000-000000000002', 'swimming', 'Paro Valley Pool',
   'An open-air pool with mountain views, open in the warm months. Lessons on weekend mornings. Sample data.',
   'Paro', 'Paro town', 'Near the old bridge', '+97517100002', null, 'Sonam Tobgay',
   27.4287, 89.4164,
   '{"tue":[["08:00","18:00"]],"wed":[["08:00","18:00"]],"thu":[["08:00","18:00"]],"fri":[["08:00","18:00"]],"sat":[["08:00","18:00"]],"sun":[["08:00","18:00"]]}',
   array['Changing rooms', 'Shower', 'Lifeguard', 'Swimming lessons', 'Towels', 'Parking'],
   'Cash or mBoB at the gate.', null,
   'verified', now()),
  ('5a000000-0000-0000-0000-000000000003', 'cycling', 'Trail Riders Cycling Club',
   'Group rides on the trails above Thimphu, mountain bikes to hire and a workshop for repairs. Sample data.',
   'Thimphu', 'Motithang', 'At the top of the Motithang road', '+97517100003', 'ride@trailriders.example', 'Ugyen Dorji',
   27.4806, 89.6280,
   '{"sat":[["06:30","17:00"]],"sun":[["06:30","17:00"]],"wed":[["16:00","19:00"]]}',
   array['Bike hire', 'Helmets', 'Repairs', 'Group rides', 'Guided trails', 'Parking'],
   'mBoB account 200000103.', 'A ride cancelled by the club is refunded.',
   'verified', now()),
  ('5a000000-0000-0000-0000-000000000004', 'cycling', 'Punakha River Rides',
   'Easy rides along the river and to the dzong, with bikes for hire by the hour or the day. Sample data.',
   'Punakha', 'Khuruthang', 'Opposite the town square', '+97517100004', null, 'Pema Wangchuk',
   27.5877, 89.8650,
   '{"mon":[["08:00","17:00"]],"tue":[["08:00","17:00"]],"wed":[["08:00","17:00"]],"thu":[["08:00","17:00"]],"fri":[["08:00","17:00"]],"sat":[["08:00","17:00"]],"sun":[["08:00","17:00"]]}',
   array['Bike hire', 'Helmets', 'Guided trails', 'Drinking water'],
   'Cash or mBoB.', null,
   'verified', now()),
  ('5a000000-0000-0000-0000-000000000005', 'wellness_centre', 'Lotus Wellness Spa',
   'Massage, a hot stone bath, sauna and steam, and morning yoga and meditation. Sample data.',
   'Thimphu', 'Norzin Lam', 'Second floor, above the bookshop', '+97517100005', 'relax@lotus.example', 'Dechen Yangzom',
   27.4740, 89.6385,
   '{"mon":[["09:00","20:00"]],"tue":[["09:00","20:00"]],"wed":[["09:00","20:00"]],"thu":[["09:00","20:00"]],"fri":[["09:00","20:00"]],"sat":[["09:00","20:00"]],"sun":[["10:00","17:00"]]}',
   array['Massage', 'Sauna', 'Steam room', 'Hot stone bath', 'Yoga', 'Meditation', 'Changing rooms'],
   'mBoB account 200000105, or card at the desk.', 'Book a day ahead; a missed booking is not refunded.',
   'verified', now()),
  ('5a000000-0000-0000-0000-000000000006', 'sports_facility', 'Babesa Sports Arena',
   'Indoor courts for badminton, basketball and futsal, floodlit at night, with coaching for juniors. Sample data.',
   'Thimphu', 'Babesa', 'Off the expressway, behind the petrol station', '+97517100006', null, 'Tshering Penjor',
   27.4300, 89.6510,
   '{"mon":[["06:00","22:00"]],"tue":[["06:00","22:00"]],"wed":[["06:00","22:00"]],"thu":[["06:00","22:00"]],"fri":[["06:00","22:00"]],"sat":[["06:00","22:00"]],"sun":[["08:00","20:00"]]}',
   array['Indoor court', 'Floodlights', 'Equipment hire', 'Coaching', 'Changing rooms', 'Spectator seats', 'Parking'],
   'Cash or mBoB at the counter.', null,
   'verified', now()),
  ('5a000000-0000-0000-0000-000000000007', 'fitness_centre', 'Pulse Fitness Studio',
   'Aerobics, Zumba and circuit classes every day, and personal training by booking. Sample data.',
   'Thimphu', 'Chubachu', 'Ground floor, the blue building', '+97517100007', 'move@pulse.example', 'Kinley Wangmo',
   27.4760, 89.6360,
   '{"mon":[["06:00","09:00"],["17:00","21:00"]],"tue":[["06:00","09:00"],["17:00","21:00"]],"wed":[["06:00","09:00"],["17:00","21:00"]],"thu":[["06:00","09:00"],["17:00","21:00"]],"fri":[["06:00","09:00"],["17:00","21:00"]],"sat":[["07:00","12:00"]]}',
   array['Group classes', 'Aerobics', 'Zumba', 'Personal training', 'Changing rooms', 'Drinking water'],
   'mBoB account 200000107.', 'Memberships are not refunded once they have started.',
   'verified', now()),
  ('5a000000-0000-0000-0000-000000000008', 'gym', 'Peak Mountain Gym',
   'Free weights, machines and a cardio floor, with trainers on hand mornings and evenings. Sample data.',
   'Paro', 'Bondey', 'On the airport road', '+97517100008', null, 'Jigme Namgyel',
   27.4310, 89.4140,
   '{"mon":[["06:00","21:00"]],"tue":[["06:00","21:00"]],"wed":[["06:00","21:00"]],"thu":[["06:00","21:00"]],"fri":[["06:00","21:00"]],"sat":[["07:00","19:00"]]}',
   array['Shower', 'Lockers', 'Cardio machines', 'Free weights', 'Personal training', 'Parking'],
   'Cash or mBoB at the front desk.', 'Memberships are not refunded once they have started.',
   'verified', now())
on conflict (id) do nothing;

-- Packages: what each one sells, and the price (Nu.).
insert into public.gym_plans (venue_id, name, description, duration_days, price, sort_order)
select p.venue_id::uuid, p.name, p.description, p.days, p.price, p.sort_order
from (values
  ('5a000000-0000-0000-0000-000000000001', 'Single swim', 'One session in the lanes', 1, 150, 1),
  ('5a000000-0000-0000-0000-000000000001', 'Monthly swim', 'Every session, all month', 30, 2000, 2),
  ('5a000000-0000-0000-0000-000000000001', 'Learn to swim (8 lessons)', 'Two lessons a week with a coach', 30, 3500, 3),
  ('5a000000-0000-0000-0000-000000000002', 'Day pass', 'Swim all day', 1, 200, 1),
  ('5a000000-0000-0000-0000-000000000002', 'Season pass', 'Every day the pool is open, three months', 90, 4500, 2),
  ('5a000000-0000-0000-0000-000000000003', 'Weekend group ride', 'One guided ride, bike and helmet included', 1, 600, 1),
  ('5a000000-0000-0000-0000-000000000003', 'Club membership', 'Every group ride and the workshop, all month', 30, 2500, 2),
  ('5a000000-0000-0000-0000-000000000004', 'Bike for a day', 'A bike and helmet, 8 am to 5 pm', 1, 800, 1),
  ('5a000000-0000-0000-0000-000000000004', 'Weekly rider', 'A bike every day for a week', 7, 3500, 2),
  ('5a000000-0000-0000-0000-000000000005', 'Spa day', 'Massage, sauna and steam', 1, 2500, 1),
  ('5a000000-0000-0000-0000-000000000005', 'Wellness month', 'Yoga and meditation every morning, sauna and steam', 30, 5000, 2),
  ('5a000000-0000-0000-0000-000000000006', 'Court hour', 'One court for an hour', 1, 400, 1),
  ('5a000000-0000-0000-0000-000000000006', 'Monthly player', 'Two hours a day on any court', 30, 3000, 2),
  ('5a000000-0000-0000-0000-000000000007', 'Drop-in class', 'Any one class', 1, 250, 1),
  ('5a000000-0000-0000-0000-000000000007', 'Unlimited classes', 'Every class, all month', 30, 2200, 2),
  ('5a000000-0000-0000-0000-000000000008', 'Monthly', 'All equipment', 30, 1800, 1),
  ('5a000000-0000-0000-0000-000000000008', '3 months', 'All equipment', 90, 5000, 2)
) as p(venue_id, name, description, days, price, sort_order)
where not exists (select 1 from public.gym_plans g where g.venue_id = p.venue_id::uuid and g.name = p.name);

-- Classes on the timetable: day of the week (1 Monday ... 7 Sunday) and time.
insert into public.gym_classes (venue_id, name, description, trainer_name, weekday, starts_at, duration_minutes, capacity)
select c.venue_id::uuid, c.name, c.description, c.trainer, c.weekday, c.starts::time, c.minutes, c.capacity
from (values
  ('5a000000-0000-0000-0000-000000000001', 'Swimming lessons for children', 'Ages 6 to 12', 'Karma Choden', 2, '16:00', 45, 10),
  ('5a000000-0000-0000-0000-000000000001', 'Swimming lessons for children', 'Ages 6 to 12', 'Karma Choden', 4, '16:00', 45, 10),
  ('5a000000-0000-0000-0000-000000000001', 'Adult lap swim', 'Lanes kept for laps', null, 6, '07:00', 60, 20),
  ('5a000000-0000-0000-0000-000000000002', 'Weekend swimming lessons', 'Beginners welcome', 'Sonam Tobgay', 6, '09:00', 60, 12),
  ('5a000000-0000-0000-0000-000000000003', 'Saturday trail ride', 'Two hours, intermediate', 'Ugyen Dorji', 6, '07:00', 120, 15),
  ('5a000000-0000-0000-0000-000000000003', 'Beginners'' ride', 'Easy roads, all bikes', 'Ugyen Dorji', 7, '08:00', 90, 15),
  ('5a000000-0000-0000-0000-000000000004', 'Riverside ride to the dzong', 'Easy, about two hours', 'Pema Wangchuk', 6, '09:00', 120, 12),
  ('5a000000-0000-0000-0000-000000000005', 'Morning yoga', 'All levels', 'Dechen Yangzom', 1, '07:00', 60, 14),
  ('5a000000-0000-0000-0000-000000000005', 'Guided meditation', 'Quiet room', 'Dechen Yangzom', 3, '18:00', 45, 14),
  ('5a000000-0000-0000-0000-000000000006', 'Junior badminton coaching', 'Ages 8 to 16', 'Tshering Penjor', 6, '10:00', 90, 16),
  ('5a000000-0000-0000-0000-000000000006', 'Evening futsal', 'Teams made on the night', null, 5, '19:00', 90, 20),
  ('5a000000-0000-0000-0000-000000000007', 'Zumba', 'High energy, all levels', 'Kinley Wangmo', 1, '18:00', 60, 25),
  ('5a000000-0000-0000-0000-000000000007', 'Aerobics', 'Low impact', 'Kinley Wangmo', 3, '06:30', 45, 25),
  ('5a000000-0000-0000-0000-000000000007', 'Circuit training', 'Strength and cardio', 'Kinley Wangmo', 5, '18:00', 45, 20),
  ('5a000000-0000-0000-0000-000000000008', 'Strength basics', 'Learn the main lifts', 'Jigme Namgyel', 2, '07:00', 60, 10)
) as c(venue_id, name, description, trainer, weekday, starts, minutes, capacity)
where not exists (select 1 from public.gym_classes g
                  where g.venue_id = c.venue_id::uuid and g.name = c.name and g.weekday = c.weekday);
