-- =====================================================================
-- More service types: every kind of health business in Bhutan
-- =====================================================================
-- The Service types master (venue_types, 20261127000001) started with six.
-- These twelve join it, each run by gym membership like the rest, with an
-- icon and colour the app already has and the facilities its form
-- suggests: Yoga & Meditation, Archery, Martial Arts, Trekking & Hiking,
-- Climbing, Racquet Sports, Golf, Sports Academy, Running Club,
-- Physiotherapy & Rehab, Hot Stone Bath, Nutrition & Diet.
--
-- Like the first six, each has its card on Services from the start, for
-- everyone: Coming soon until one of its places is verified.
--
-- Safe to re-run: types the team has changed keep their changes.
-- =====================================================================

insert into public.venue_types (key, module_key, name, description, icon, color, sort_order, show_when_empty, facilities) values
  ('yoga_meditation', 'gym_membership', 'Yoga & Meditation', 'Yoga classes, meditation and breathing sessions',
   'yoga', 'pink', 70, true,
   array['Yoga mats', 'Meditation room', 'Group classes', 'Private sessions', 'Changing rooms', 'Drinking water', 'Parking']),
  ('archery', 'gym_membership', 'Archery', 'Archery ranges and clubs for the national sport, with bows to hire and coaching',
   'archery', 'red', 80, true,
   array['Bamboo bows', 'Compound bows', 'Bow hire', 'Coaching', 'Target range', 'Floodlights', 'Spectator seats',
         'Drinking water', 'Parking']),
  ('martial_arts', 'gym_membership', 'Martial Arts', 'Taekwondo, karate, judo, boxing and self-defence classes',
   'martial_arts', 'violet', 90, true,
   array['Mat area', 'Punching bags', 'Boxing ring', 'Group classes', 'Grading', 'Kids'' classes', 'Changing rooms',
         'Shower', 'Drinking water']),
  ('trekking', 'gym_membership', 'Trekking & Hiking', 'Guided hikes, treks and walking groups in the hills',
   'hike', 'green', 100, true,
   array['Guided hikes', 'Group walks', 'Gear hire', 'Packed lunch', 'Transport', 'First aid', 'Camping gear']),
  ('climbing', 'gym_membership', 'Climbing', 'Climbing walls and outdoor rock climbing, with gear and instructors',
   'climb', 'amber', 110, true,
   array['Climbing wall', 'Bouldering', 'Outdoor routes', 'Gear hire', 'Instructors', 'Kids'' classes', 'Changing rooms']),
  ('racquet_sports', 'gym_membership', 'Racquet Sports', 'Tennis, badminton, table tennis and squash clubs',
   'tennis', 'teal', 120, true,
   array['Tennis court', 'Badminton court', 'Table tennis', 'Squash court', 'Racquet hire', 'Coaching', 'Floodlights',
         'Changing rooms', 'Parking']),
  ('golf', 'gym_membership', 'Golf', 'Golf courses, driving ranges and lessons',
   'golf', 'green', 130, true,
   array['Driving range', 'Putting green', 'Club hire', 'Lessons', 'Caddies', 'Clubhouse', 'Parking']),
  ('sports_academy', 'gym_membership', 'Sports Academy', 'Coaching for football, basketball, volleyball and athletics',
   'basketball', 'orange', 140, true,
   array['Football ground', 'Basketball court', 'Volleyball court', 'Athletics track', 'Coaching', 'Kids'' classes',
         'Equipment hire', 'Changing rooms', 'Floodlights']),
  ('running', 'gym_membership', 'Running Club', 'Running groups, race training and track sessions',
   'run', 'orange', 150, true,
   array['Group runs', 'Race training', 'Track sessions', 'Trail runs', 'Coaching', 'Drinking water']),
  ('physiotherapy', 'gym_membership', 'Physiotherapy & Rehab', 'Physiotherapy, sports injury care and rehabilitation',
   'health', 'blue', 160, true,
   array['Physiotherapy', 'Sports massage', 'Injury rehab', 'Exercise therapy', 'Hot and cold therapy', 'Home visits',
         'Parking']),
  ('hot_stone_bath', 'gym_membership', 'Hot Stone Bath', 'Traditional dotsho hot stone baths and hot spring soaks',
   'wellness', 'amber', 170, true,
   array['Hot stone bath', 'Private tubs', 'Herbal bath', 'Massage', 'Towels', 'Changing rooms', 'Tea', 'Parking']),
  ('nutrition', 'gym_membership', 'Nutrition & Diet', 'Dietitians, diet plans and weight management',
   'health', 'teal', 180, true,
   array['Diet plans', 'Weight management', 'Body check', 'Cooking classes', 'Online follow-up', 'Parking'])
on conflict (key) do nothing;
