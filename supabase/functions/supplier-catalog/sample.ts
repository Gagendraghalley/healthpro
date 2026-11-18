// The dummy gym suppliers' catalogue (api_kind 'sample'), for trying the
// Suppliers page until a real supplier is connected. Built in, so nothing is
// fetched. A supplier's category picks its section. Gym things only, prices
// in Ngultrum.
//
// Photos: Wikimedia Commons, each one CC0 or public domain (no credit
// needed), 500 px wide. Commons serves them to the web app (CORS) and the
// phone app alike.

export type SampleItem = {
  id: string;
  section: 'equipment' | 'nutrition' | 'accessories';
  name: string;
  category: string;
  description: string;
  price: number;
  stock: number;
  image: string;
};

const commons = (path: string): string => `https://upload.wikimedia.org/wikipedia/commons/thumb/${path}`;

export const SAMPLE_ITEMS: SampleItem[] = [
  // Equipment
  { id: 'eq-01', section: 'equipment', name: 'Vinyl hex dumbbells 1-5 kg (5 pairs)', category: 'Free weights', description: 'Colour-coded by weight, with a shelf rack.', price: 6500, stock: 14,
    image: commons('c/cd/Colorful_barbells_on_a_shelf.jpg/500px-Colorful_barbells_on_a_shelf.jpg') },
  { id: 'eq-02', section: 'equipment', name: 'Spin-lock dumbbells 15 kg (pair)', category: 'Free weights', description: 'Black plates and threaded handles, adjust from 2 to 15 kg.', price: 4800, stock: 12,
    image: commons('c/c1/A_pair_of_dumbbells.jpeg/500px-A_pair_of_dumbbells.jpeg') },
  { id: 'eq-03', section: 'equipment', name: 'Chrome dumbbell with plates 10 kg', category: 'Free weights', description: 'Knurled chrome handle, cast iron plates, spin-lock collars.', price: 3600, stock: 3,
    image: commons('9/98/Gfp-weight.jpg/500px-Gfp-weight.jpg') },
  { id: 'eq-04', section: 'equipment', name: 'Kettlebell 16 kg', category: 'Free weights', description: 'Cast iron, flat base, wide handle.', price: 4500, stock: 9,
    image: commons('c/cb/3_kettlebells.jpg/500px-3_kettlebells.jpg') },
  { id: 'eq-05', section: 'equipment', name: 'Olympic barbell 20 kg', category: 'Strength', description: '2.2 m, 28 mm grip, takes 50 mm plates.', price: 14000, stock: 5,
    image: commons('1/15/Fitman.jpg/500px-Fitman.jpg') },
  { id: 'eq-06', section: 'equipment', name: 'Cast iron weight plate 5 kg', category: 'Strength', description: 'Standard 28 mm hole, sold singly.', price: 1300, stock: 0,
    image: commons('1/10/Gewichtschijf.jpg/500px-Gewichtschijf.jpg') },
  { id: 'eq-07', section: 'equipment', name: 'Bench press station', category: 'Strength', description: 'Flat bench with bar rests and plate storage; holds 300 kg.', price: 38000, stock: 4,
    image: commons('a/aa/Bench_press_1.jpg/500px-Bench_press_1.jpg') },
  { id: 'eq-08', section: 'equipment', name: 'Motorised treadmill', category: 'Cardio', description: '3 HP motor, 0-18 km/h, 15 incline levels.', price: 145000, stock: 1,
    image: commons('0/0f/Treadmills_at_gym.jpg/500px-Treadmills_at_gym.jpg') },
  { id: 'eq-09', section: 'equipment', name: 'Spin bike', category: 'Cardio', description: '18 kg flywheel, adjustable seat and handlebars.', price: 42000, stock: 6,
    image: commons('8/83/Berkeley_Heights_NJ_cycling_exercise_room.jpg/500px-Berkeley_Heights_NJ_cycling_exercise_room.jpg') },
  { id: 'eq-10', section: 'equipment', name: 'Rowing machine', category: 'Cardio', description: 'Air resistance, performance monitor, splits in two to store.', price: 72000, stock: 2,
    image: commons('0/0d/Concept_2_Indoor_Rowers.JPG/500px-Concept_2_Indoor_Rowers.JPG') },
  { id: 'eq-11', section: 'equipment', name: 'Floor mats 1 m x 1 m', category: 'Flooring', description: 'Interlocking, 40 mm, for stretching and floor work. Price per mat.', price: 2400, stock: 80,
    image: commons('b/b6/07_Wrestling_gym_%28Poly_Haven%29.jpg/500px-07_Wrestling_gym_%28Poly_Haven%29.jpg') },

  // Nutrition
  { id: 'nu-01', section: 'nutrition', name: 'Protein drink mix 700 g', category: 'Protein', description: 'Whey blend, 20 g protein a scoop, chocolate.', price: 2600, stock: 30,
    image: commons('7/7b/Bodybuilding_supplement_high_protein_drink_mix_700g.jpg/500px-Bodybuilding_supplement_high_protein_drink_mix_700g.jpg') },
  { id: 'nu-02', section: 'nutrition', name: 'Creatine monohydrate 500 g', category: 'Supplements', description: 'Micronised, unflavoured, 166 servings.', price: 2900, stock: 25,
    image: commons('7/7f/Creatine_monohydrate_supplement.jpg/500px-Creatine_monohydrate_supplement.jpg') },
  { id: 'nu-03', section: 'nutrition', name: 'Creatine monohydrate 1 kg (pouch)', category: 'Supplements', description: 'Unflavoured, resealable pouch.', price: 4900, stock: 4,
    image: commons('8/87/Creatine_monohydrate.jpg/500px-Creatine_monohydrate.jpg') },
  { id: 'nu-04', section: 'nutrition', name: 'Protein bars (box of 12)', category: 'Snacks', description: '20 g protein a bar, chocolate mint.', price: 1800, stock: 40,
    image: commons('1/12/Clif_Chocolate_Mint_Builder%27s_Bar_cut_in_half.jpg/500px-Clif_Chocolate_Mint_Builder%27s_Bar_cut_in_half.jpg') },
  { id: 'nu-05', section: 'nutrition', name: 'Sports drink 473 ml (case of 12)', category: 'Hydration', description: 'Electrolytes and coconut water, fruit punch.', price: 1500, stock: 0,
    image: commons('2/25/BODYARMOR_SuperDrink_Fruit_Punch_Bottle.jpg/500px-BODYARMOR_SuperDrink_Fruit_Punch_Bottle.jpg') },
  { id: 'nu-06', section: 'nutrition', name: 'Multivitamin (60 tablets)', category: 'Supplements', description: 'One a day, for active adults.', price: 1200, stock: 15,
    image: commons('9/9d/Centrum_multivitamin_pills.jpg/500px-Centrum_multivitamin_pills.jpg') },

  // Accessories
  { id: 'ac-01', section: 'accessories', name: 'Cotton yoga mat', category: 'Mats', description: 'Woven cotton, 183 x 61 cm, tie-up strap. Six colours.', price: 1200, stock: 35,
    image: commons('6/6e/Cotton_Yoga_Mats.png/500px-Cotton_Yoga_Mats.png') },
  { id: 'ac-02', section: 'accessories', name: 'Toning kit: band, dumbbells and ball', category: 'Training', description: 'Resistance tube, two 1 kg dumbbells and a mini ball.', price: 1500, stock: 22,
    image: commons('8/8b/Exercise_equipment_%28rubber_ball%2C_light-weight_dumbbells%2C_jump_rope%29.jpg/500px-Exercise_equipment_%28rubber_ball%2C_light-weight_dumbbells%2C_jump_rope%29.jpg') },
  { id: 'ac-03', section: 'accessories', name: 'Speed skipping rope', category: 'Training', description: 'Steel cable, ball-bearing handles, adjustable.', price: 450, stock: 40,
    image: commons('a/a1/A_profession_jump_roper_jumps_rope_between_wheelchair_rugby_matches_at_the_2016_Invictus_Games_%2826896679991%29.jpg/500px-A_profession_jump_roper_jumps_rope_between_wheelchair_rugby_matches_at_the_2016_Invictus_Games_%2826896679991%29.jpg') },
  { id: 'ac-04', section: 'accessories', name: 'Medicine ball 7 kg', category: 'Training', description: 'Rubber, textured grip, bounces.', price: 2800, stock: 5,
    image: commons('0/04/Medicine_balls-1038438.jpg/500px-Medicine_balls-1038438.jpg') },
  { id: 'ac-05', section: 'accessories', name: 'Shaker bottle 700 ml', category: 'Bottles', description: 'Leak-proof lid, mixing ball.', price: 450, stock: 60,
    image: commons('1/1b/Osaka_protein_shaker.jpg/500px-Osaka_protein_shaker.jpg') },
  { id: 'ac-06', section: 'accessories', name: 'Microfibre gym towel', category: 'Towels', description: '40 x 80 cm, quick-dry.', price: 350, stock: 100,
    image: commons('5/56/History_of_towels.jpg/500px-History_of_towels.jpg') },
  { id: 'ac-07', section: 'accessories', name: 'Disinfectant spray 1 L', category: 'Cleaning', description: 'Chlorhexidine, for benches, mats and handles.', price: 650, stock: 20,
    image: commons('4/4b/Atomizador_con_clorhexidina.jpg/500px-Atomizador_con_clorhexidina.jpg') },
];
